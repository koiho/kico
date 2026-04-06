use anyhow::{Context, Result, anyhow};
use clap::Parser;
use csv::WriterBuilder;
use half::f16;
use image::{ColorType, GrayImage, ImageReader, codecs::jpeg::JpegEncoder, imageops::FilterType};
use ndarray::Array2;
use ndarray_npy::{NpzReader, NpzWriter};
use rand::{Rng, SeedableRng, rngs::StdRng, seq::SliceRandom};
use renderer::{
    GATE_NAMES, PARAMETER_SPECS, RenderBuffer, RenderBufferFormat, RenderModelOutputsRequest,
    render_with_model_outputs,
};
use serde::Deserialize;
use serde::Serialize;
use serde_json::json;
use std::{
    collections::BTreeMap,
    fs::{self, File},
    path::{Path, PathBuf},
};
use walkdir::WalkDir;

#[derive(Debug, Parser)]
#[command(about = "Synthetic cold-start dataset generator for the current render architecture")]
struct Args {
    #[arg(long)]
    neutral_dir: PathBuf,
    #[arg(long)]
    output_dir: PathBuf,
    #[arg(long, default_value_t = 256)]
    image_size: u32,
    #[arg(long, default_value_t = 4)]
    samples_per_image: usize,
    #[arg(long, default_value_t = 0.1)]
    val_ratio: f32,
    #[arg(long, default_value_t = 42)]
    seed: u64,
}

#[derive(Debug, Clone)]
struct ImageData {
    width: u32,
    height: u32,
    original_width: u32,
    original_height: u32,
    rgba8: Vec<u8>,
    rgb: Vec<[f32; 3]>,
}

#[derive(Debug, Clone)]
struct MaskSet {
    face: Vec<f32>,
    person: Vec<f32>,
    highlight: Vec<f32>,
    shadow: Vec<f32>,
    foreground_subject: Vec<f32>,
}

#[derive(Debug, Clone, Serialize)]
struct SceneStats {
    mean_luma: f32,
    p10_luma: f32,
    p50_luma: f32,
    p90_luma: f32,
    dynamic_range: f32,
    saturation_mean: f32,
    detail_energy: f32,
    warm_balance: f32,
    face_presence: f32,
    person_presence: f32,
    foreground_presence: f32,
    highlight_presence: f32,
    shadow_presence: f32,
}

#[derive(Debug, Clone, Serialize)]
struct StyleCode {
    brightness: f32,
    contrast: f32,
    fade: f32,
    warmth: f32,
    saturation: f32,
    colorfulness: f32,
    split_tone: f32,
    cool_shadow: f32,
    highlight_warm: f32,
    local_pop: f32,
    texture: f32,
    grain: f32,
    glow: f32,
    vignette: f32,
    film_bias: f32,
    teal_orange: f32,
    magenta_bias: f32,
    sector_strength: f32,
}

#[derive(Debug, Clone, Serialize)]
struct ControlJitter {
    red_hue_shift: f32,
    yellow_hue_shift: f32,
    green_hue_shift: f32,
    cyan_hue_shift: f32,
    blue_hue_shift: f32,
    magenta_hue_shift: f32,
    vignette_roundness: f32,
}

#[derive(Debug, Clone)]
struct SceneRecord {
    capture_dir: PathBuf,
    image: ImageData,
    masks: MaskSet,
    render_neutral: RenderBuffer,
    render_masks: MaskSet,
    stats: SceneStats,
}

#[derive(Debug, Clone)]
struct CaptureInput {
    capture_dir: PathBuf,
    preview_path: PathBuf,
    payload_path: PathBuf,
    mask_path: PathBuf,
}

#[derive(Debug, Clone)]
struct AssignedSample {
    sample_id: String,
    is_val: bool,
}

#[derive(Debug, Clone, Serialize)]
struct ManifestRow {
    sample_id: String,
    reference_image_path: String,
    neutral_preview_path: String,
    neutral_image_path: String,
    mask_bundle_path: String,
    label_json_path: String,
}

#[derive(Debug, Deserialize)]
struct PayloadMetadata {
    width: u32,
    height: u32,
    #[serde(rename = "bytesPerRow")]
    bytes_per_row: u32,
}

fn clamp(value: f32, low: f32, high: f32) -> f32 {
    value.max(low).min(high)
}

fn mean(values: &[f32]) -> f32 {
    if values.is_empty() {
        0.0
    } else {
        values.iter().sum::<f32>() / values.len() as f32
    }
}

fn percentile(values: &[f32], q: f32) -> f32 {
    if values.is_empty() {
        return 0.0;
    }
    let mut sorted = values.to_vec();
    sorted.sort_by(|a, b| a.total_cmp(b));
    let index = ((sorted.len().saturating_sub(1)) as f32 * q).round() as usize;
    sorted[index.min(sorted.len().saturating_sub(1))]
}

fn latent(rng: &mut StdRng, scale: f32) -> f32 {
    clamp(
        rng.gen_range(-1.0..=1.0) * scale + rng.gen_range(-0.35..=0.35),
        -1.0,
        1.0,
    )
}

fn param_index(name: &str) -> Result<usize> {
    PARAMETER_SPECS
        .iter()
        .position(|spec| spec.name == name)
        .ok_or_else(|| anyhow!("unknown parameter: {name}"))
}

fn normalize_param(name: &str, value: f32) -> Result<f32> {
    let spec = PARAMETER_SPECS[param_index(name)?];
    Ok(clamp(
        (clamp(value, spec.min, spec.max) - spec.min) / (spec.max - spec.min),
        0.0,
        1.0,
    ))
}

fn load_image(path: &Path, image_size: u32) -> Result<ImageData> {
    let decoded = ImageReader::open(path)
        .with_context(|| format!("failed to open image: {}", path.display()))?
        .decode()
        .with_context(|| format!("failed to decode image: {}", path.display()))?;
    let original_width = decoded.width();
    let original_height = decoded.height();
    let image = decoded
        .resize_exact(image_size, image_size, FilterType::Lanczos3)
        .to_rgba8();

    let (width, height) = image.dimensions();
    let rgba8 = image.into_raw();
    let rgb = rgba8
        .chunks_exact(4)
        .map(|px| {
            [
                px[0] as f32 / 255.0,
                px[1] as f32 / 255.0,
                px[2] as f32 / 255.0,
            ]
        })
        .collect();

    Ok(ImageData {
        width,
        height,
        original_width,
        original_height,
        rgba8,
        rgb,
    })
}

fn compute_scene_stats(image: &ImageData, masks: &MaskSet) -> SceneStats {
    let mut luma = Vec::with_capacity(image.rgb.len());
    let mut sat = Vec::with_capacity(image.rgb.len());
    let mut detail = vec![0.0; image.rgb.len()];
    for rgb in &image.rgb {
        let max_c = rgb[0].max(rgb[1].max(rgb[2]));
        let min_c = rgb[0].min(rgb[1].min(rgb[2]));
        luma.push(0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]);
        sat.push(if max_c > 1e-6 {
            (max_c - min_c) / max_c
        } else {
            0.0
        });
    }
    for y in 0..image.height {
        for x in 0..image.width {
            let i = (y * image.width + x) as usize;
            let dx = if x + 1 < image.width {
                (luma[(y * image.width + x + 1) as usize] - luma[i]).abs()
            } else {
                0.0
            };
            let dy = if y + 1 < image.height {
                (luma[((y + 1) * image.width + x) as usize] - luma[i]).abs()
            } else {
                0.0
            };
            detail[i] = dx + dy;
        }
    }

    let warm_balance =
        image.rgb.iter().map(|rgb| rgb[0] - rgb[2]).sum::<f32>() / image.rgb.len() as f32;

    SceneStats {
        mean_luma: mean(&luma),
        p10_luma: percentile(&luma, 0.10),
        p50_luma: percentile(&luma, 0.50),
        p90_luma: percentile(&luma, 0.90),
        dynamic_range: clamp(percentile(&luma, 0.90) - percentile(&luma, 0.10), 0.0, 1.0),
        saturation_mean: clamp(mean(&sat), 0.0, 1.0),
        detail_energy: clamp(mean(&detail) * 5.0, 0.0, 1.0),
        warm_balance: clamp(warm_balance * 2.0, -1.0, 1.0),
        face_presence: clamp(mean(&masks.face), 0.0, 1.0),
        person_presence: clamp(mean(&masks.person), 0.0, 1.0),
        foreground_presence: clamp(mean(&masks.foreground_subject), 0.0, 1.0),
        highlight_presence: clamp(mean(&masks.highlight), 0.0, 1.0),
        shadow_presence: clamp(mean(&masks.shadow), 0.0, 1.0),
    }
}

fn sample_style_code(rng: &mut StdRng) -> StyleCode {
    let film_push = rng.gen_range(0.0..=1.0);
    let clean_push = rng.gen_range(0.0..=1.0);
    StyleCode {
        brightness: clamp(
            latent(rng, 0.65) + 0.35 * clean_push - 0.25 * film_push,
            -1.0,
            1.0,
        ),
        contrast: clamp(latent(rng, 0.65) + 0.25 * film_push, -1.0, 1.0),
        fade: clamp(
            latent(rng, 0.52) + 0.45 * film_push - 0.25 * clean_push,
            -1.0,
            1.0,
        ),
        warmth: clamp(latent(rng, 0.58), -1.0, 1.0),
        saturation: clamp(latent(rng, 0.58) + 0.20 * clean_push, -1.0, 1.0),
        colorfulness: clamp(latent(rng, 0.62) + 0.35 * clean_push, -1.0, 1.0),
        split_tone: clamp(latent(rng, 0.50) + 0.35 * film_push, -1.0, 1.0),
        cool_shadow: clamp(latent(rng, 0.45) + 0.20 * film_push, -1.0, 1.0),
        highlight_warm: clamp(latent(rng, 0.45) + 0.25 * clean_push, -1.0, 1.0),
        local_pop: clamp(latent(rng, 0.55) + 0.25 * clean_push, -1.0, 1.0),
        texture: clamp(latent(rng, 0.50) + 0.15 * film_push, -1.0, 1.0),
        grain: clamp(
            latent(rng, 0.55) + 0.40 * film_push - 0.20 * clean_push,
            -1.0,
            1.0,
        ),
        glow: clamp(latent(rng, 0.50) + 0.25 * film_push, -1.0, 1.0),
        vignette: clamp(latent(rng, 0.45) + 0.20 * film_push, -1.0, 1.0),
        film_bias: clamp(
            latent(rng, 0.48) + 0.55 * film_push - 0.20 * clean_push,
            -1.0,
            1.0,
        ),
        teal_orange: clamp(latent(rng, 0.55), -1.0, 1.0),
        magenta_bias: clamp(latent(rng, 0.42), -1.0, 1.0),
        sector_strength: clamp(latent(rng, 0.55) + 0.25 * clean_push, -1.0, 1.0),
    }
}

fn set_param(params: &mut BTreeMap<String, f32>, name: &str, value: f32) {
    params.insert(name.to_string(), value);
}

fn sample_control_jitter(rng: &mut StdRng) -> ControlJitter {
    ControlJitter {
        red_hue_shift: rng.gen_range(-1.5..=1.5),
        yellow_hue_shift: rng.gen_range(-1.5..=1.5),
        green_hue_shift: rng.gen_range(-1.8..=1.8),
        cyan_hue_shift: rng.gen_range(-1.8..=1.8),
        blue_hue_shift: rng.gen_range(-1.8..=1.8),
        magenta_hue_shift: rng.gen_range(-1.5..=1.5),
        vignette_roundness: rng.gen_range(-0.18..=0.18),
    }
}

fn physical_params_from_code(
    scene: &SceneStats,
    code: &StyleCode,
    jitter: &ControlJitter,
) -> BTreeMap<String, f32> {
    let warm_target = clamp(code.warmth - scene.warm_balance * 0.30, -1.0, 1.0);
    let airy = -code.contrast * 0.25 + code.brightness * 0.45 - code.fade * 0.15;
    let moody = code.contrast * 0.35 - code.brightness * 0.25 + code.fade * 0.20;
    let split_abs = code.split_tone.abs();
    let glow_strength = code.glow.max(0.0);
    let texture_strength = code.texture.max(0.0);
    let sector_push = 0.22 * code.sector_strength;
    let warm_sector = 0.18 * warm_target;
    let cool_sector = -0.18 * warm_target;
    let teal_orange = 0.20 * code.teal_orange;

    let mut params = BTreeMap::new();
    set_param(
        &mut params,
        "exposure_ev",
        0.9 * code.brightness + 0.45 * (0.45 - scene.mean_luma) - 0.15 * moody,
    );
    set_param(
        &mut params,
        "contrast",
        0.55 * code.contrast + 0.20 * (0.48 - scene.dynamic_range),
    );
    set_param(
        &mut params,
        "contrast_pivot",
        clamp(
            0.36 + 0.08 * (scene.p50_luma - 0.5) - 0.03 * code.fade,
            0.18,
            0.65,
        ),
    );
    set_param(
        &mut params,
        "blacks",
        0.18 * moody - 0.12 * code.fade - 0.08 * code.brightness,
    );
    set_param(
        &mut params,
        "whites",
        0.10 * code.brightness + 0.12 * airy - 0.10 * split_abs,
    );
    set_param(
        &mut params,
        "shadows",
        0.35 * airy - 0.25 * moody + 0.12 * code.brightness,
    );
    set_param(
        &mut params,
        "highlights",
        -0.18 * code.contrast - 0.12 * glow_strength + 0.06 * airy,
    );
    set_param(
        &mut params,
        "toe_strength",
        clamp(
            0.20 + 0.32 * code.fade.max(0.0) + 0.18 * code.film_bias.max(0.0),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "shoulder_strength",
        clamp(0.18 + 0.30 * glow_strength + 0.10 * split_abs, 0.0, 1.0),
    );
    set_param(
        &mut params,
        "fade",
        clamp(
            0.10 + 0.18 * code.fade.max(0.0) + 0.10 * code.film_bias.max(0.0),
            0.0,
            0.35,
        ),
    );
    set_param(
        &mut params,
        "midtone_boost",
        0.18 * code.brightness + 0.12 * airy - 0.10 * code.contrast,
    );
    set_param(
        &mut params,
        "clarity_global",
        0.22 * code.local_pop + 0.16 * texture_strength - 0.18 * code.fade.max(0.0),
    );

    set_param(
        &mut params,
        "wb_r_gain",
        clamp(
            1.0 + 0.26 * warm_target + 0.06 * code.highlight_warm,
            0.6,
            1.8,
        ),
    );
    set_param(
        &mut params,
        "wb_b_gain",
        clamp(
            1.0 - 0.22 * warm_target - 0.04 * code.highlight_warm,
            0.6,
            1.8,
        ),
    );
    set_param(
        &mut params,
        "global_saturation",
        clamp(
            1.0 + 0.28 * code.saturation + 0.12 * code.colorfulness - 0.08 * code.fade.max(0.0),
            0.4,
            1.8,
        ),
    );
    set_param(
        &mut params,
        "global_vibrance",
        clamp(
            0.35 * code.colorfulness + 0.12 * airy - 0.08 * moody,
            -0.8,
            0.8,
        ),
    );
    set_param(
        &mut params,
        "global_hue_shift",
        clamp(
            code.teal_orange * 4.5 + code.magenta_bias * 2.0,
            -12.0,
            12.0,
        ),
    );
    set_param(
        &mut params,
        "color_density",
        clamp(
            0.20 * code.colorfulness + 0.18 * code.film_bias.max(0.0) - 0.10 * airy,
            -0.5,
            0.5,
        ),
    );
    set_param(
        &mut params,
        "warmth_bias",
        clamp(0.28 * warm_target + 0.10 * code.highlight_warm, -0.5, 0.5),
    );
    set_param(
        &mut params,
        "green_magenta_bias",
        clamp(0.14 * code.magenta_bias, -0.35, 0.35),
    );
    set_param(
        &mut params,
        "shadow_hue",
        220.0 + 120.0 * clamp(code.cool_shadow, -1.0, 1.0),
    );
    set_param(
        &mut params,
        "shadow_sat",
        clamp(
            0.05 + 0.18 * split_abs + 0.08 * (-code.cool_shadow).max(0.0),
            0.0,
            0.5,
        ),
    );
    set_param(
        &mut params,
        "midtone_hue",
        (35.0 + 70.0 * warm_target + 20.0 * code.teal_orange).rem_euclid(360.0),
    );
    set_param(
        &mut params,
        "midtone_sat",
        clamp(0.04 + 0.12 * split_abs, 0.0, 0.4),
    );
    set_param(
        &mut params,
        "highlight_hue",
        (42.0 + 55.0 * code.highlight_warm - 15.0 * code.cool_shadow).rem_euclid(360.0),
    );
    set_param(
        &mut params,
        "highlight_sat",
        clamp(
            0.06 + 0.18 * split_abs + 0.08 * code.highlight_warm.max(0.0),
            0.0,
            0.5,
        ),
    );
    set_param(
        &mut params,
        "split_balance",
        clamp(
            0.22 * code.brightness - 0.30 * code.cool_shadow + 0.18 * code.highlight_warm,
            -1.0,
            1.0,
        ),
    );

    set_param(
        &mut params,
        "red_hue_shift",
        clamp(
            3.5 * teal_orange - 1.2 * code.magenta_bias + jitter.red_hue_shift,
            -20.0,
            20.0,
        ),
    );
    set_param(
        &mut params,
        "red_sat_scale",
        clamp(1.0 + sector_push + 0.08 * warm_target, 0.3, 1.8),
    );
    set_param(
        &mut params,
        "red_luma_shift",
        clamp(0.08 * airy - 0.04 * moody, -0.4, 0.4),
    );
    set_param(
        &mut params,
        "yellow_hue_shift",
        clamp(-3.0 * warm_target + jitter.yellow_hue_shift, -20.0, 20.0),
    );
    set_param(
        &mut params,
        "yellow_sat_scale",
        clamp(1.0 + sector_push + 0.12 * warm_sector, 0.3, 1.8),
    );
    set_param(
        &mut params,
        "yellow_luma_shift",
        clamp(0.10 * airy + 0.05 * warm_sector, -0.4, 0.4),
    );
    set_param(
        &mut params,
        "green_hue_shift",
        clamp(-5.0 * teal_orange + jitter.green_hue_shift, -20.0, 20.0),
    );
    set_param(
        &mut params,
        "green_sat_scale",
        clamp(
            1.0 - 0.10 * code.film_bias.max(0.0) + 0.08 * code.colorfulness,
            0.3,
            1.8,
        ),
    );
    set_param(
        &mut params,
        "green_luma_shift",
        clamp(0.05 * airy - 0.04 * code.fade, -0.4, 0.4),
    );
    set_param(
        &mut params,
        "cyan_hue_shift",
        clamp(6.0 * teal_orange + jitter.cyan_hue_shift, -20.0, 20.0),
    );
    set_param(
        &mut params,
        "cyan_sat_scale",
        clamp(1.0 + 0.12 * sector_push + 0.10 * cool_sector, 0.3, 1.8),
    );
    set_param(
        &mut params,
        "cyan_luma_shift",
        clamp(0.06 * airy + 0.05 * cool_sector, -0.4, 0.4),
    );
    set_param(
        &mut params,
        "blue_hue_shift",
        clamp(7.0 * teal_orange + jitter.blue_hue_shift, -20.0, 20.0),
    );
    set_param(
        &mut params,
        "blue_sat_scale",
        clamp(
            1.0 + 0.18 * cool_sector + 0.12 * code.film_bias.max(0.0),
            0.3,
            1.8,
        ),
    );
    set_param(
        &mut params,
        "blue_luma_shift",
        clamp(-0.08 * moody + 0.04 * airy, -0.4, 0.4),
    );
    set_param(
        &mut params,
        "magenta_hue_shift",
        clamp(
            3.5 * code.magenta_bias + jitter.magenta_hue_shift,
            -20.0,
            20.0,
        ),
    );
    set_param(
        &mut params,
        "magenta_sat_scale",
        clamp(
            1.0 + 0.10 * sector_push + 0.08 * code.magenta_bias,
            0.3,
            1.8,
        ),
    );
    set_param(
        &mut params,
        "magenta_luma_shift",
        clamp(0.06 * airy, -0.4, 0.4),
    );
    set_param(
        &mut params,
        "sector_width_scale",
        clamp(1.0 + 0.12 * code.sector_strength, 0.7, 1.4),
    );
    set_param(
        &mut params,
        "sector_smoothness",
        clamp(
            0.48 + 0.18 * code.fade.max(0.0) - 0.08 * code.contrast,
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "face_exposure",
        clamp(
            (0.12 * airy + 0.06 * warm_target) * scene.face_presence,
            -0.4,
            0.4,
        ),
    );
    set_param(
        &mut params,
        "face_sat",
        clamp(
            1.0 + (0.10 * code.saturation + 0.06 * warm_target) * scene.face_presence,
            0.6,
            1.4,
        ),
    );
    set_param(
        &mut params,
        "face_hue_shift",
        clamp(
            (-2.5 * code.magenta_bias - 1.5 * teal_orange) * scene.face_presence,
            -10.0,
            10.0,
        ),
    );
    set_param(
        &mut params,
        "face_warmth",
        clamp(
            (0.12 * warm_target + 0.08 * code.highlight_warm) * scene.face_presence,
            -0.3,
            0.3,
        ),
    );
    set_param(
        &mut params,
        "face_soft_clarity",
        clamp(
            (-0.18 * code.film_bias.max(0.0) + 0.10 * code.local_pop) * scene.face_presence,
            -0.5,
            0.3,
        ),
    );
    set_param(
        &mut params,
        "person_exposure",
        clamp(
            (0.14 * airy + 0.08 * code.brightness) * scene.person_presence,
            -0.5,
            0.5,
        ),
    );
    set_param(
        &mut params,
        "person_sat",
        clamp(
            1.0 + (0.10 * code.saturation) * scene.person_presence,
            0.5,
            1.6,
        ),
    );
    set_param(
        &mut params,
        "person_hue_shift",
        clamp((-3.0 * teal_orange) * scene.person_presence, -18.0, 18.0),
    );
    set_param(
        &mut params,
        "person_clarity",
        clamp(
            (0.14 * code.local_pop + 0.10 * texture_strength) * scene.person_presence,
            -0.4,
            0.6,
        ),
    );
    set_param(
        &mut params,
        "foreground_subject_hue_shift",
        clamp(
            (-3.0 * teal_orange + 2.0 * warm_target) * scene.foreground_presence,
            -18.0,
            18.0,
        ),
    );
    set_param(
        &mut params,
        "foreground_subject_sat",
        clamp(
            1.0 + (0.16 * code.colorfulness) * scene.foreground_presence,
            0.5,
            1.5,
        ),
    );
    set_param(
        &mut params,
        "foreground_subject_luma",
        clamp(
            (0.10 * airy - 0.08 * moody) * scene.foreground_presence,
            -0.3,
            0.3,
        ),
    );
    set_param(
        &mut params,
        "foreground_subject_exposure",
        clamp(
            (0.14 * airy + 0.08 * code.brightness) * scene.foreground_presence,
            -0.4,
            0.4,
        ),
    );
    set_param(
        &mut params,
        "foreground_subject_contrast",
        clamp(
            (0.12 * code.local_pop + 0.08 * code.contrast) * scene.foreground_presence,
            -0.3,
            0.3,
        ),
    );
    set_param(
        &mut params,
        "foreground_subject_pop",
        clamp(
            (0.35 + 0.30 * code.local_pop.max(0.0)) * scene.foreground_presence,
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "highlight_warmth_local",
        clamp(0.18 * code.highlight_warm + 0.10 * warm_target, -0.4, 0.4),
    );
    set_param(
        &mut params,
        "shadow_tint_local",
        clamp(
            -0.18 * code.cool_shadow + 0.08 * code.magenta_bias,
            -0.4,
            0.4,
        ),
    );
    set_param(
        &mut params,
        "shadow_desat",
        clamp(
            0.18 + 0.25 * code.film_bias.max(0.0) + 0.10 * split_abs,
            0.0,
            0.8,
        ),
    );
    set_param(
        &mut params,
        "highlight_mask_threshold",
        clamp(
            0.62 + 0.12 * (scene.p90_luma - 0.7) - 0.04 * glow_strength,
            0.45,
            0.95,
        ),
    );
    set_param(
        &mut params,
        "highlight_mask_feather",
        clamp(0.06 + 0.08 * glow_strength + 0.04 * split_abs, 0.02, 0.25),
    );
    set_param(
        &mut params,
        "shadow_mask_threshold",
        clamp(0.22 + 0.12 * scene.p10_luma - 0.06 * moody, 0.05, 0.55),
    );
    set_param(
        &mut params,
        "shadow_mask_feather",
        clamp(0.06 + 0.06 * code.fade.max(0.0), 0.02, 0.25),
    );
    set_param(
        &mut params,
        "bloom_threshold",
        clamp(0.78 - 0.12 * glow_strength + 0.06 * moody, 0.55, 1.2),
    );
    set_param(
        &mut params,
        "bloom_intensity",
        clamp(
            0.08 + 0.42 * glow_strength * (0.35 + 0.65 * scene.highlight_presence),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "bloom_radius",
        clamp(
            0.12 + 0.42 * glow_strength + 0.10 * code.film_bias.max(0.0),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "bloom_softness",
        clamp(
            0.35 + 0.25 * glow_strength + 0.10 * code.fade.max(0.0),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "bloom_veil_mix",
        clamp(
            0.45 + 0.18 * glow_strength + 0.06 * code.film_bias.max(0.0),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "halation_threshold",
        clamp(0.88 - 0.10 * glow_strength + 0.08 * moody, 0.65, 1.3),
    );
    set_param(
        &mut params,
        "halation_intensity",
        clamp(
            0.05 + 0.32 * glow_strength * (0.25 + 0.75 * scene.highlight_presence),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "halation_radius",
        clamp(
            0.10 + 0.32 * glow_strength + 0.12 * code.film_bias.max(0.0),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "halation_red_bias",
        clamp(
            0.55 + 0.20 * warm_target.max(0.0) + 0.10 * code.film_bias.max(0.0),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "halation_warmth",
        clamp(
            0.45 + 0.25 * code.highlight_warm.max(0.0) + 0.12 * warm_target.max(0.0),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "halation_core_balance",
        clamp(
            0.45 + 0.18 * glow_strength - 0.08 * code.fade.max(0.0),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "vignette_amount",
        clamp(
            0.10 + 0.18 * code.vignette.max(0.0) + 0.08 * code.film_bias.max(0.0),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "vignette_midpoint",
        clamp(0.58 - 0.10 * code.vignette.max(0.0), 0.2, 0.9),
    );
    set_param(
        &mut params,
        "vignette_feather",
        clamp(0.45 + 0.20 * code.fade.max(0.0), 0.0, 1.0),
    );
    set_param(
        &mut params,
        "vignette_roundness",
        clamp(jitter.vignette_roundness, -1.0, 1.0),
    );
    set_param(
        &mut params,
        "soft_glow",
        clamp(
            0.08 + 0.22 * glow_strength + 0.10 * code.film_bias.max(0.0),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "edge_softness",
        clamp(
            0.06 + 0.18 * glow_strength + 0.08 * code.fade.max(0.0),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "grain_luma_amount",
        clamp(
            0.06 + 0.34 * code.grain.max(0.0) + 0.12 * code.film_bias.max(0.0),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "grain_chroma_amount",
        clamp(0.02 + 0.14 * code.grain.max(0.0), 0.0, 0.6),
    );
    set_param(
        &mut params,
        "grain_size",
        clamp(
            0.55 + 0.38 * code.film_bias.max(0.0) + 0.20 * code.grain.max(0.0),
            0.2,
            1.5,
        ),
    );
    set_param(
        &mut params,
        "grain_shadow_bias",
        clamp(
            0.45 + 0.22 * code.grain.max(0.0) + 0.10 * scene.shadow_presence,
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "grain_highlight_suppress",
        clamp(0.45 + 0.18 * glow_strength, 0.0, 1.0),
    );
    set_param(
        &mut params,
        "texture_boost",
        clamp(
            0.16 * code.local_pop + 0.20 * texture_strength - 0.12 * code.fade.max(0.0),
            -0.5,
            0.6,
        ),
    );
    set_param(
        &mut params,
        "noise_clean_bias",
        clamp(0.56 - 0.18 * code.grain.max(0.0) + 0.08 * airy, 0.0, 1.0),
    );
    set_param(
        &mut params,
        "detail_preserve",
        clamp(
            0.52 + 0.18 * texture_strength + 0.08 * scene.detail_energy,
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "texture_microcontrast_balance",
        clamp(0.22 * code.local_pop - 0.10 * code.fade.max(0.0), -1.0, 1.0),
    );
    set_param(
        &mut params,
        "gamut_compress",
        clamp(
            0.42 + 0.16 * code.colorfulness.max(0.0) + 0.10 * code.film_bias.max(0.0),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "final_gamma_bias",
        clamp(1.0 - 0.05 * airy + 0.04 * moody, 0.85, 1.15),
    );
    set_param(
        &mut params,
        "highlight_clip_softness",
        clamp(
            0.36 + 0.22 * glow_strength + 0.12 * code.fade.max(0.0),
            0.0,
            1.0,
        ),
    );
    set_param(
        &mut params,
        "highlight_rolloff_pivot",
        clamp(0.95 - 0.10 * glow_strength + 0.05 * airy, 0.7, 1.2),
    );
    set_param(
        &mut params,
        "shadow_floor",
        clamp(
            0.01 + 0.05 * code.fade.max(0.0) + 0.03 * code.film_bias.max(0.0),
            0.0,
            0.2,
        ),
    );
    params
}

fn build_controls(
    scene: &SceneStats,
    code: &StyleCode,
    jitter: &ControlJitter,
) -> Result<(Vec<f32>, Vec<f32>, BTreeMap<String, f32>)> {
    let physical = physical_params_from_code(scene, code, jitter);
    let mut params = vec![0.0_f32; PARAMETER_SPECS.len()];
    for (index, spec) in PARAMETER_SPECS.iter().enumerate() {
        params[index] = normalize_param(
            spec.name,
            *physical
                .get(spec.name)
                .ok_or_else(|| anyhow!("missing physical param: {}", spec.name))?,
        )?;
    }

    let split_abs = code.split_tone.abs();
    let glow_strength = code.glow.max(0.0);
    let grain_strength = code.grain.max(0.0);
    let texture_strength = code.texture.max(0.0);
    let local_pop = code.local_pop.max(0.0);
    let sector_strength = code.sector_strength.max(0.0);

    let gates = [
        clamp(
            0.25 + 0.55 * sector_strength + 0.15 * code.teal_orange.abs(),
            0.0,
            1.0,
        ),
        clamp(
            scene.face_presence * (0.50 + 0.35 * code.highlight_warm.max(0.0) + 0.20 * local_pop),
            0.0,
            1.0,
        ),
        clamp(scene.person_presence * (0.45 + 0.35 * local_pop), 0.0, 1.0),
        clamp(
            scene.foreground_presence * (0.40 + 0.40 * local_pop),
            0.0,
            1.0,
        ),
        clamp(
            scene.highlight_presence.max(scene.shadow_presence)
                * (0.35 + 0.35 * split_abs + 0.15 * code.cool_shadow.abs()),
            0.0,
            1.0,
        ),
        clamp(
            scene.highlight_presence * (0.20 + 0.65 * glow_strength),
            0.0,
            1.0,
        ),
        clamp(
            scene.highlight_presence
                * (0.10 + 0.55 * glow_strength + 0.10 * code.film_bias.max(0.0)),
            0.0,
            1.0,
        ),
        clamp(0.25 + 0.45 * code.vignette.max(0.0), 0.0, 1.0),
        clamp(
            scene.highlight_presence * (0.10 + 0.55 * glow_strength),
            0.0,
            1.0,
        ),
        clamp(
            (0.25 + 0.55 * grain_strength) * (0.35 + 0.65 * scene.shadow_presence),
            0.0,
            1.0,
        ),
        clamp(
            (0.20 + 0.55 * texture_strength) * (0.40 + 0.60 * scene.detail_energy),
            0.0,
            1.0,
        ),
    ];

    Ok((params, gates.to_vec(), physical))
}

fn load_rgba16f_payload(path: &Path, width: u32, height: u32) -> Result<RenderBuffer> {
    let data =
        fs::read(path).with_context(|| format!("failed to read payload: {}", path.display()))?;
    let bytes_per_row = width
        .checked_mul(8)
        .ok_or_else(|| anyhow!("payload bytes_per_row overflow for {}", path.display()))?;
    let expected_len = bytes_per_row
        .checked_mul(height)
        .ok_or_else(|| anyhow!("payload byte count overflow for {}", path.display()))?;

    if data.len() != expected_len as usize {
        return Err(anyhow!(
            "payload size mismatch for {}: expected {} bytes, got {}",
            path.display(),
            expected_len,
            data.len()
        ));
    }

    Ok(RenderBuffer {
        width,
        height,
        bytes_per_row,
        format: RenderBufferFormat::Rgba16Float,
        data,
    })
}

fn resolve_payload_dimensions(
    payload_path: &Path,
    preview_width: u32,
    preview_height: u32,
) -> Result<(u32, u32)> {
    let metadata_path = payload_path.with_file_name("neutral_linear.rgba16f.json");
    if metadata_path.exists() {
        let metadata: PayloadMetadata =
            serde_json::from_slice(&fs::read(&metadata_path).with_context(|| {
                format!(
                    "failed to read payload metadata: {}",
                    metadata_path.display()
                )
            })?)
            .with_context(|| {
                format!(
                    "failed to parse payload metadata: {}",
                    metadata_path.display()
                )
            })?;
        if metadata.width == 0 || metadata.height == 0 {
            return Err(anyhow!(
                "invalid payload metadata in {}: width/height must be positive",
                metadata_path.display()
            ));
        }
        let expected_bytes_per_row = metadata.width.checked_mul(8).ok_or_else(|| {
            anyhow!(
                "payload bytes_per_row overflow for {}",
                metadata_path.display()
            )
        })?;
        if metadata.bytes_per_row != expected_bytes_per_row {
            return Err(anyhow!(
                "invalid payload metadata in {}: bytesPerRow={} does not match width={} for rgba16f",
                metadata_path.display(),
                metadata.bytes_per_row,
                metadata.width
            ));
        }
        return Ok((metadata.width, metadata.height));
    }

    let preview_expected_len = preview_width
        .checked_mul(preview_height)
        .and_then(|pixels| pixels.checked_mul(8))
        .ok_or_else(|| anyhow!("payload byte count overflow for {}", payload_path.display()))?;
    let payload_len = fs::metadata(payload_path)
        .with_context(|| format!("failed to stat payload: {}", payload_path.display()))?
        .len();
    if payload_len == preview_expected_len as u64 {
        return Ok((preview_width, preview_height));
    }

    Err(anyhow!(
        "cannot infer rgba16f payload dimensions for {}: payload metadata {} is missing and preview size {}x{} does not match file length {} bytes",
        payload_path.display(),
        metadata_path.display(),
        preview_width,
        preview_height,
        payload_len
    ))
}

fn mask_to_buffer(mask: &[f32], width: u32, height: u32) -> RenderBuffer {
    let data = mask
        .iter()
        .map(|v| (clamp(*v, 0.0, 1.0) * 255.0).round() as u8)
        .collect::<Vec<_>>();
    RenderBuffer {
        width,
        height,
        bytes_per_row: width,
        format: RenderBufferFormat::R8Unorm,
        data,
    }
}

fn render_buffer_to_rgb8(buffer: &RenderBuffer) -> Result<Vec<u8>> {
    match buffer.format {
        RenderBufferFormat::Rgba8Unorm => Ok(buffer
            .data
            .chunks_exact(4)
            .flat_map(|pixel| [pixel[0], pixel[1], pixel[2]])
            .collect()),
        RenderBufferFormat::Rgba16Float => {
            let packed_row_bytes = (buffer.width as usize) * 8;
            if (buffer.bytes_per_row as usize) < packed_row_bytes {
                return Err(anyhow!(
                    "invalid rgba16f buffer row stride: got {}, need at least {}",
                    buffer.bytes_per_row,
                    packed_row_bytes
                ));
            }

            let expected_min_len = (buffer.bytes_per_row as usize) * (buffer.height as usize);
            if buffer.data.len() < expected_min_len {
                return Err(anyhow!(
                    "rgba16f buffer too small: got {} bytes, need at least {}",
                    buffer.data.len(),
                    expected_min_len
                ));
            }

            let mut out =
                Vec::with_capacity((buffer.width as usize) * (buffer.height as usize) * 3);
            for row in 0..buffer.height as usize {
                let row_start = row * buffer.bytes_per_row as usize;
                let row_data = &buffer.data[row_start..row_start + packed_row_bytes];
                for pixel in row_data.chunks_exact(8) {
                    for channel in pixel[..6].chunks_exact(2) {
                        let value = f16::from_bits(u16::from_le_bytes([channel[0], channel[1]]))
                            .to_f32()
                            .clamp(0.0, 1.0);
                        out.push(encode_display_u8(value));
                    }
                }
            }
            Ok(out)
        }
        RenderBufferFormat::R8Unorm => Err(anyhow!("final image buffer must be RGBA, got R8Unorm")),
    }
}

fn encode_display_u8(linear_value: f32) -> u8 {
    let linear = clamp(linear_value, 0.0, 1.0);
    let encoded = if linear <= 0.003_130_8 {
        linear * 12.92
    } else {
        1.055 * linear.powf(1.0 / 2.4) - 0.055
    };
    (clamp(encoded, 0.0, 1.0) * 255.0).round() as u8
}

fn relative_posix(path: &Path, base: &Path) -> Result<String> {
    Ok(path
        .strip_prefix(base)
        .with_context(|| {
            format!(
                "failed to strip prefix: {} from {}",
                base.display(),
                path.display()
            )
        })?
        .to_string_lossy()
        .replace('\\', "/"))
}

fn list_capture_inputs(root: &Path) -> Vec<CaptureInput> {
    WalkDir::new(root)
        .into_iter()
        .filter_map(|entry| entry.ok())
        .filter(|entry| entry.file_type().is_file())
        .filter(|entry| entry.file_name().to_string_lossy() == "neutral_preview.png")
        .filter_map(|entry| {
            let preview_path = entry.path().to_path_buf();
            let capture_dir = preview_path
                .parent()
                .map(Path::to_path_buf)
                .unwrap_or_else(|| preview_path.clone());
            let payload_candidate = capture_dir.join("neutral_linear.rgba16f.bin");
            let mask_candidate = capture_dir.join("mask_bundle.npz");
            if !(payload_candidate.exists() && mask_candidate.exists()) {
                return None;
            }
            Some(CaptureInput {
                capture_dir,
                preview_path,
                payload_path: payload_candidate,
                mask_path: mask_candidate,
            })
        })
        .collect()
}

fn resize_mask_array(mask: Array2<f32>, target_width: u32, target_height: u32) -> Result<Vec<f32>> {
    let (source_height, source_width) = mask.dim();
    if source_width as u32 == target_width && source_height as u32 == target_height {
        return Ok(mask.iter().copied().collect());
    }

    let bytes = mask
        .iter()
        .map(|value| (clamp(*value, 0.0, 1.0) * 255.0).round() as u8)
        .collect::<Vec<_>>();
    let image = GrayImage::from_raw(source_width as u32, source_height as u32, bytes)
        .ok_or_else(|| anyhow!("failed to create grayscale mask image"))?;
    let resized = image::DynamicImage::ImageLuma8(image)
        .resize_exact(target_width, target_height, FilterType::Triangle)
        .to_luma8();
    Ok(resized
        .into_raw()
        .into_iter()
        .map(|value| value as f32 / 255.0)
        .collect())
}

fn load_mask_set(path: &Path, target_width: u32, target_height: u32) -> Result<MaskSet> {
    let file =
        File::open(path).with_context(|| format!("failed to open mask npz: {}", path.display()))?;
    let mut npz = NpzReader::new(file)
        .with_context(|| format!("failed to read mask npz: {}", path.display()))?;

    let face: Array2<f32> = npz
        .by_name("face.npy")
        .context("missing face.npy in mask bundle")?;
    let person: Array2<f32> = npz
        .by_name("person.npy")
        .context("missing person.npy in mask bundle")?;
    let highlight: Array2<f32> = npz
        .by_name("highlight.npy")
        .context("missing highlight.npy in mask bundle")?;
    let shadow: Array2<f32> = npz
        .by_name("shadow.npy")
        .context("missing shadow.npy in mask bundle")?;
    let foreground_subject: Array2<f32> = npz
        .by_name("foreground_subject.npy")
        .context("missing foreground_subject.npy in mask bundle")?;

    Ok(MaskSet {
        face: resize_mask_array(face, target_width, target_height)?,
        person: resize_mask_array(person, target_width, target_height)?,
        highlight: resize_mask_array(highlight, target_width, target_height)?,
        shadow: resize_mask_array(shadow, target_width, target_height)?,
        foreground_subject: resize_mask_array(foreground_subject, target_width, target_height)?,
    })
}

fn write_mask_npz(path: &Path, width: u32, height: u32, masks: &MaskSet) -> Result<()> {
    let file =
        File::create(path).with_context(|| format!("failed to create npz: {}", path.display()))?;
    let mut npz = NpzWriter::new(file);
    for (name, data) in [
        ("face", &masks.face),
        ("person", &masks.person),
        ("highlight", &masks.highlight),
        ("shadow", &masks.shadow),
        ("foreground_subject", &masks.foreground_subject),
    ] {
        let array = Array2::from_shape_vec((height as usize, width as usize), data.clone())
            .with_context(|| format!("failed to build ndarray for mask {name}"))?;
        npz.add_array(name, &array)
            .with_context(|| format!("failed to add mask {name} to npz"))?;
    }
    npz.finish().context("failed to finish npz writer")?;
    Ok(())
}

fn save_reference_jpeg(path: &Path, rgb8: &[u8], width: u32, height: u32) -> Result<()> {
    let file = File::create(path)
        .with_context(|| format!("failed to create reference image: {}", path.display()))?;
    let mut encoder = JpegEncoder::new_with_quality(file, 92);
    encoder
        .encode(rgb8, width, height, ColorType::Rgb8.into())
        .with_context(|| format!("failed to encode reference image: {}", path.display()))?;
    Ok(())
}

fn main() -> Result<()> {
    let args = Args::parse();
    let mut rng = StdRng::seed_from_u64(args.seed);

    fs::create_dir_all(&args.output_dir)
        .with_context(|| format!("failed to create output dir: {}", args.output_dir.display()))?;
    let refs_dir = args.output_dir.join("refs");
    let previews_dir = args.output_dir.join("previews");
    let masks_dir = args.output_dir.join("masks");
    let labels_dir = args.output_dir.join("labels");
    let metadata_dir = args.output_dir.join("metadata");
    for dir in [
        &refs_dir,
        &previews_dir,
        &masks_dir,
        &labels_dir,
        &metadata_dir,
    ] {
        fs::create_dir_all(dir)
            .with_context(|| format!("failed to create directory: {}", dir.display()))?;
    }

    let capture_inputs = list_capture_inputs(&args.neutral_dir);
    if capture_inputs.is_empty() {
        return Err(anyhow!(
            "no valid app captures found under {} (expected neutral_preview.png + neutral_linear.rgba16f.bin + mask_bundle.npz)",
            args.neutral_dir.display()
        ));
    }
    println!(
        "found {} capture folders under {}",
        capture_inputs.len(),
        args.neutral_dir.display()
    );
    let total_planned_samples = capture_inputs.len() * args.samples_per_image;
    let mut planned_samples = Vec::with_capacity(total_planned_samples);
    let mut sample_counter = 0usize;
    for capture_index in 0..capture_inputs.len() {
        for _ in 0..args.samples_per_image {
            sample_counter += 1;
            planned_samples.push((capture_index, format!("sample_{sample_counter:06}")));
        }
    }
    planned_samples.shuffle(&mut rng);
    let val_count = ((planned_samples.len() as f32) * args.val_ratio).round() as usize;
    let val_count = val_count.min(planned_samples.len());
    let mut assignments_by_capture = vec![Vec::<AssignedSample>::new(); capture_inputs.len()];
    for (index, (capture_index, sample_id)) in planned_samples.into_iter().enumerate() {
        assignments_by_capture[capture_index].push(AssignedSample {
            sample_id,
            is_val: index < val_count,
        });
    }

    let train_manifest_path = args.output_dir.join("train_manifest.csv");
    let val_manifest_path = args.output_dir.join("val_manifest.csv");
    println!("writing manifest: {}", train_manifest_path.display());
    println!("writing manifest: {}", val_manifest_path.display());
    let mut train_writer = WriterBuilder::new()
        .has_headers(true)
        .from_path(&train_manifest_path)
        .with_context(|| {
            format!(
                "failed to create manifest: {}",
                train_manifest_path.display()
            )
        })?;
    let mut val_writer = WriterBuilder::new()
        .has_headers(true)
        .from_path(&val_manifest_path)
        .with_context(|| format!("failed to create manifest: {}", val_manifest_path.display()))?;

    for (capture_index, input) in capture_inputs.iter().enumerate() {
        println!(
            "loading capture {}/{}: {}",
            capture_index + 1,
            capture_inputs.len(),
            input.capture_dir.display()
        );
        let image = load_image(&input.preview_path, args.image_size)?;
        let masks = load_mask_set(&input.mask_path, image.width, image.height)?;
        let (payload_width, payload_height) = resolve_payload_dimensions(
            &input.payload_path,
            image.original_width,
            image.original_height,
        )?;
        let render_neutral =
            load_rgba16f_payload(&input.payload_path, payload_width, payload_height)?;
        let render_masks = load_mask_set(&input.mask_path, payload_width, payload_height)?;
        let stats = compute_scene_stats(&image, &masks);
        let target = SceneRecord {
            capture_dir: input.capture_dir.clone(),
            image,
            masks,
            render_neutral,
            render_masks,
            stats,
        };
        println!(
            "generating samples for capture {}/{}: {}",
            capture_index + 1,
            capture_inputs.len(),
            target.capture_dir.display()
        );
        for (sample_index, assignment) in assignments_by_capture[capture_index].iter().enumerate() {
            let sample_id = assignment.sample_id.clone();
            println!(
                "  sample {}/{} -> {}",
                sample_index + 1,
                assignments_by_capture[capture_index].len(),
                sample_id
            );
            let style_code = sample_style_code(&mut rng);
            let control_jitter = sample_control_jitter(&mut rng);
            let (target_params, target_gates, target_physical) =
                build_controls(&target.stats, &style_code, &control_jitter)?;

            let response = render_with_model_outputs(RenderModelOutputsRequest {
                neutral_image: target.render_neutral.clone(),
                face_mask: Some(mask_to_buffer(
                    &target.render_masks.face,
                    target.render_neutral.width,
                    target.render_neutral.height,
                )),
                person_mask: Some(mask_to_buffer(
                    &target.render_masks.person,
                    target.render_neutral.width,
                    target.render_neutral.height,
                )),
                highlight_mask: Some(mask_to_buffer(
                    &target.render_masks.highlight,
                    target.render_neutral.width,
                    target.render_neutral.height,
                )),
                shadow_mask: Some(mask_to_buffer(
                    &target.render_masks.shadow,
                    target.render_neutral.width,
                    target.render_neutral.height,
                )),
                foreground_subject_mask: Some(mask_to_buffer(
                    &target.render_masks.foreground_subject,
                    target.render_neutral.width,
                    target.render_neutral.height,
                )),
                normalized_params: target_params.clone(),
                gate_values: target_gates.clone(),
            })
            .map_err(|err| anyhow!("render generation failed for {sample_id}: {err}"))?;

            let ref_path = refs_dir.join(format!("{sample_id}.jpg"));
            let preview_path = previews_dir.join(format!("{sample_id}.png"));
            let mask_path = masks_dir.join(format!("{sample_id}.npz"));
            let label_path = labels_dir.join(format!("{sample_id}.json"));
            let metadata_path = metadata_dir.join(format!("{sample_id}.json"));

            let reference_rgb8 = render_buffer_to_rgb8(&response.final_image)?;
            save_reference_jpeg(
                &ref_path,
                &reference_rgb8,
                response.final_image.width,
                response.final_image.height,
            )?;
            image::save_buffer(
                &preview_path,
                &target.image.rgba8,
                target.image.width,
                target.image.height,
                ColorType::Rgba8,
            )
            .with_context(|| format!("failed to save preview image: {}", preview_path.display()))?;
            write_mask_npz(
                &mask_path,
                target.image.width,
                target.image.height,
                &target.masks,
            )?;

            let param_json = PARAMETER_SPECS
                .iter()
                .enumerate()
                .map(|(index, spec)| (spec.name.to_string(), target_params[index]))
                .collect::<BTreeMap<_, _>>();
            let gate_json = GATE_NAMES
                .iter()
                .enumerate()
                .map(|(index, name)| ((*name).to_string(), target_gates[index]))
                .collect::<BTreeMap<_, _>>();
            fs::write(
                &label_path,
                serde_json::to_vec_pretty(&json!({
                    "renderer_params": param_json,
                    "module_gates": gate_json,
                }))?,
            )
            .with_context(|| format!("failed to write label: {}", label_path.display()))?;

            fs::write(
                &metadata_path,
                serde_json::to_vec_pretty(&json!({
                    "sample_id": sample_id,
                    "capture_path": target.capture_dir,
                    "style_code": style_code,
                    "control_jitter": control_jitter,
                    "target_scene_stats": target.stats,
                    "target_physical_params": target_physical,
                }))?,
            )
            .with_context(|| format!("failed to write metadata: {}", metadata_path.display()))?;

            let row = ManifestRow {
                sample_id: sample_id.clone(),
                reference_image_path: relative_posix(&ref_path, &args.output_dir)?,
                neutral_preview_path: relative_posix(&preview_path, &args.output_dir)?,
                neutral_image_path: input
                    .payload_path
                    .canonicalize()?
                    .to_string_lossy()
                    .to_string(),
                mask_bundle_path: relative_posix(&mask_path, &args.output_dir)?,
                label_json_path: relative_posix(&label_path, &args.output_dir)?,
            };
            if assignment.is_val {
                val_writer.serialize(&row)?;
            } else {
                train_writer.serialize(&row)?;
            }
        }
    }
    train_writer.flush()?;
    val_writer.flush()?;

    fs::write(
        args.output_dir.join("generation_summary.json"),
        serde_json::to_vec_pretty(&json!({
            "num_input_images": capture_inputs.len(),
            "samples_per_image": args.samples_per_image,
            "num_train_samples": total_planned_samples - val_count,
            "num_val_samples": val_count,
            "image_size": args.image_size,
            "seed": args.seed,
        }))?,
    )?;

    println!(
        "{}",
        serde_json::to_string_pretty(&json!({
            "num_input_images": capture_inputs.len(),
            "num_train_samples": total_planned_samples - val_count,
            "num_val_samples": val_count,
            "output_dir": args.output_dir,
        }))?
    );

    Ok(())
}
