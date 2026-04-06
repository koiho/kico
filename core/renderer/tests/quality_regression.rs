use std::{
    future::Future,
    task::{Context, Poll, Waker},
    thread,
    time::Duration,
};

use renderer::{
    BloomParams, FaceLocalParams, ForegroundSubjectLocalParams, GpuImage, HalationParams,
    LensCharacterParams, MaskBundle, OutputFinishParams, PersonLocalParams, RenderContext,
    RenderGates, RenderParams, Renderer, SemanticLocalParams, TextureSurfaceParams,
    TonalLocalParams, VignetteParams,
};
use serde::{Deserialize, Serialize};

#[test]
fn quality_regression_matches_baseline() {
    let Some(ctx) = create_test_context() else {
        return;
    };

    let actual = [
        render_case(&ctx, cinematic_glow_case()),
        render_case(&ctx, semantic_local_case()),
        render_case(&ctx, texture_finish_case()),
    ];
    let expected: Vec<CaseSignature> =
        serde_json::from_str(include_str!("baselines/quality_signatures.json"))
            .expect("quality baselines json should parse");

    assert_eq!(
        actual.len(),
        expected.len(),
        "baseline case count should match"
    );
    for (actual_case, expected_case) in actual.iter().zip(expected.iter()) {
        assert_eq!(
            actual_case.name, expected_case.name,
            "case ordering should stay stable"
        );
        assert_signature_close(&actual_case.signature, &expected_case.signature);
    }
}

#[test]
#[ignore]
fn quality_signature_probe() {
    let Some(ctx) = create_test_context() else {
        return;
    };

    let signatures = [
        render_case(&ctx, cinematic_glow_case()),
        render_case(&ctx, semantic_local_case()),
        render_case(&ctx, texture_finish_case()),
    ];

    println!(
        "{}",
        serde_json::to_string_pretty(&signatures).expect("signatures should serialize")
    );
}

fn render_case(ctx: &RenderContext, case: RenderCase) -> CaseSignature {
    let renderer = Renderer::default();
    let neutral = create_color_image(ctx, case.width, case.height, &case.scene);
    let masks = MaskBundle {
        face: case
            .face_mask
            .map(|mask| create_mask_image(ctx, case.width, case.height, &mask)),
        person: case
            .person_mask
            .map(|mask| create_mask_image(ctx, case.width, case.height, &mask)),
        highlight: case
            .highlight_mask
            .map(|mask| create_mask_image(ctx, case.width, case.height, &mask)),
        shadow: case
            .shadow_mask
            .map(|mask| create_mask_image(ctx, case.width, case.height, &mask)),
        foreground_subject: case
            .foreground_mask
            .map(|mask| create_mask_image(ctx, case.width, case.height, &mask)),
    };

    let outputs = renderer
        .render_and_submit(ctx, &neutral, &case.params, &case.gates, &masks)
        .expect("quality case should render successfully");

    let pixels = download_rgba8_image(ctx, &outputs.final_image);
    CaseSignature {
        name: case.name.to_string(),
        signature: compute_signature(case.width, case.height, &pixels),
    }
}

#[derive(Debug, Clone)]
struct RenderCase {
    name: &'static str,
    width: u32,
    height: u32,
    scene: SceneKind,
    face_mask: Option<MaskKind>,
    person_mask: Option<MaskKind>,
    highlight_mask: Option<MaskKind>,
    shadow_mask: Option<MaskKind>,
    foreground_mask: Option<MaskKind>,
    params: RenderParams,
    gates: RenderGates,
}

#[derive(Debug, Clone, Copy)]
enum SceneKind {
    CinematicGlow,
    PortraitSemantic,
    TextureFinish,
}

#[derive(Debug, Clone, Copy)]
enum MaskKind {
    Face,
    Person,
    Foreground,
    Highlight,
    Shadow,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct CaseSignature {
    name: String,
    signature: ImageSignature,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ImageSignature {
    mean_rgb: [f32; 3],
    luma_p10: f32,
    luma_p50: f32,
    luma_p90: f32,
    saturation_mean: f32,
    edge_energy: f32,
    highlight_ratio: f32,
    shadow_ratio: f32,
}

fn assert_signature_close(actual: &ImageSignature, expected: &ImageSignature) {
    assert_close(actual.mean_rgb[0], expected.mean_rgb[0], 0.02, "mean_r");
    assert_close(actual.mean_rgb[1], expected.mean_rgb[1], 0.02, "mean_g");
    assert_close(actual.mean_rgb[2], expected.mean_rgb[2], 0.02, "mean_b");
    assert_close(actual.luma_p10, expected.luma_p10, 0.025, "luma_p10");
    assert_close(actual.luma_p50, expected.luma_p50, 0.025, "luma_p50");
    assert_close(actual.luma_p90, expected.luma_p90, 0.03, "luma_p90");
    assert_close(
        actual.saturation_mean,
        expected.saturation_mean,
        0.03,
        "saturation_mean",
    );
    assert_close(
        actual.edge_energy,
        expected.edge_energy,
        0.012,
        "edge_energy",
    );
    assert_close(
        actual.highlight_ratio,
        expected.highlight_ratio,
        0.03,
        "highlight_ratio",
    );
    assert_close(
        actual.shadow_ratio,
        expected.shadow_ratio,
        0.03,
        "shadow_ratio",
    );
}

fn assert_close(actual: f32, expected: f32, tolerance: f32, label: &str) {
    let delta = (actual - expected).abs();
    assert!(
        delta <= tolerance,
        "{label} drifted too far: actual={actual:.6}, expected={expected:.6}, tolerance={tolerance:.6}"
    );
}

fn cinematic_glow_case() -> RenderCase {
    let mut params = RenderParams::default();
    params.bloom = BloomParams {
        threshold: 0.48,
        intensity: 0.72,
        radius: 0.84,
        softness: 0.68,
        ..BloomParams::default()
    };
    params.halation = HalationParams {
        threshold: 0.58,
        intensity: 0.64,
        radius: 0.78,
        red_bias: 0.92,
        warmth: 0.66,
        ..HalationParams::default()
    };
    params.lens_character = LensCharacterParams {
        soft_glow: 0.42,
        edge_softness: 0.28,
    };
    params.vignette = VignetteParams {
        amount: 0.10,
        midpoint: 0.62,
        feather: 0.28,
        roundness: -0.1,
    };
    params.output_finish = OutputFinishParams {
        gamut_compress: 0.52,
        final_gamma_bias: 1.02,
        highlight_clip_softness: 0.58,
        shadow_floor: 0.01,
        ..OutputFinishParams::default()
    };

    RenderCase {
        name: "cinematic_glow",
        width: 128,
        height: 96,
        scene: SceneKind::CinematicGlow,
        face_mask: None,
        person_mask: None,
        highlight_mask: None,
        shadow_mask: None,
        foreground_mask: None,
        params,
        gates: RenderGates::default(),
    }
}

fn semantic_local_case() -> RenderCase {
    let mut params = RenderParams::default();
    params.semantic_local = SemanticLocalParams {
        face: FaceLocalParams {
            exposure: 0.22,
            saturation: 1.08,
            hue_shift: -4.0,
            warmth: 0.18,
            soft_clarity: -0.16,
        },
        person: PersonLocalParams {
            exposure: 0.12,
            saturation: 1.06,
            hue_shift: 3.0,
            clarity: 0.14,
        },
        foreground_subject: ForegroundSubjectLocalParams {
            hue_shift: -2.0,
            saturation: 1.10,
            luma: 0.10,
            exposure: 0.14,
            contrast: 0.12,
            pop: 0.18,
        },
        tonal_local: TonalLocalParams {
            highlight_warmth: 0.24,
            shadow_tint: 0.20,
            shadow_desat: 0.18,
            ..TonalLocalParams::default()
        },
    };
    params.output_finish = OutputFinishParams {
        gamut_compress: 0.48,
        final_gamma_bias: 1.0,
        highlight_clip_softness: 0.42,
        shadow_floor: 0.02,
        ..OutputFinishParams::default()
    };

    RenderCase {
        name: "semantic_local",
        width: 128,
        height: 96,
        scene: SceneKind::PortraitSemantic,
        face_mask: Some(MaskKind::Face),
        person_mask: Some(MaskKind::Person),
        highlight_mask: Some(MaskKind::Highlight),
        shadow_mask: Some(MaskKind::Shadow),
        foreground_mask: Some(MaskKind::Foreground),
        params,
        gates: RenderGates::default(),
    }
}

fn texture_finish_case() -> RenderCase {
    let mut params = RenderParams::default();
    params.texture_surface = TextureSurfaceParams {
        grain_luma_amount: 0.62,
        grain_chroma_amount: 0.28,
        grain_size: 0.82,
        grain_shadow_bias: 0.56,
        grain_highlight_suppress: 0.48,
        texture_boost: 0.32,
        noise_clean_bias: 0.24,
        detail_preserve: 0.78,
        ..TextureSurfaceParams::default()
    };
    params.output_finish = OutputFinishParams {
        gamut_compress: 0.60,
        final_gamma_bias: 0.96,
        highlight_clip_softness: 0.64,
        shadow_floor: 0.015,
        ..OutputFinishParams::default()
    };

    let mut gates = RenderGates::default();
    gates.bloom_gate = 0.0;
    gates.halation_gate = 0.0;
    gates.vignette_gate = 0.0;
    gates.lens_character_gate = 0.0;

    RenderCase {
        name: "texture_finish",
        width: 128,
        height: 96,
        scene: SceneKind::TextureFinish,
        face_mask: None,
        person_mask: None,
        highlight_mask: None,
        shadow_mask: None,
        foreground_mask: None,
        params,
        gates,
    }
}

fn create_test_context() -> Option<RenderContext> {
    let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor::default());
    let adapter =
        block_on(instance.request_adapter(&wgpu::RequestAdapterOptions::default())).ok()?;
    let (device, queue) =
        block_on(adapter.request_device(&wgpu::DeviceDescriptor::default())).ok()?;

    RenderContext::new(device, queue, wgpu::TextureFormat::Rgba16Float).ok()
}

fn create_color_image(ctx: &RenderContext, width: u32, height: u32, scene: &SceneKind) -> GpuImage {
    let mut data = Vec::with_capacity((width * height * 4) as usize);
    for y in 0..height {
        for x in 0..width {
            let color = scene_color(*scene, x, y, width, height);
            data.extend_from_slice(&[
                float_to_u8(color[0]),
                float_to_u8(color[1]),
                float_to_u8(color[2]),
                255,
            ]);
        }
    }
    upload_rgba8(ctx, width, height, "quality_scene", &data)
}

fn create_mask_image(ctx: &RenderContext, width: u32, height: u32, kind: &MaskKind) -> GpuImage {
    let mut data = Vec::with_capacity((width * height * 4) as usize);
    for y in 0..height {
        for x in 0..width {
            let mask = mask_value(*kind, x, y, width, height);
            let byte = float_to_u8(mask);
            data.extend_from_slice(&[byte, byte, byte, 255]);
        }
    }
    upload_rgba8(ctx, width, height, "quality_mask", &data)
}

fn upload_rgba8(
    ctx: &RenderContext,
    width: u32,
    height: u32,
    label: &str,
    data: &[u8],
) -> GpuImage {
    let texture = ctx.device.create_texture(&wgpu::TextureDescriptor {
        label: Some(label),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUsages::TEXTURE_BINDING
            | wgpu::TextureUsages::RENDER_ATTACHMENT
            | wgpu::TextureUsages::COPY_DST
            | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });

    ctx.queue.write_texture(
        wgpu::TexelCopyTextureInfo {
            texture: &texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        data,
        wgpu::TexelCopyBufferLayout {
            offset: 0,
            bytes_per_row: Some(width * 4),
            rows_per_image: Some(height),
        },
        wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
    );

    let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
    GpuImage::new(
        texture,
        view,
        width,
        height,
        wgpu::TextureFormat::Rgba8Unorm,
        label,
    )
}

fn download_rgba8_image(ctx: &RenderContext, image: &GpuImage) -> Vec<u8> {
    let bytes_per_row = image.width * 4;
    let padded_bytes_per_row = align_to(bytes_per_row, wgpu::COPY_BYTES_PER_ROW_ALIGNMENT);
    let buffer_size = (padded_bytes_per_row as u64) * image.height as u64;

    let readback = ctx.device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("quality_regression_readback"),
        size: buffer_size,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });

    let mut encoder = ctx.create_encoder("quality_regression_readback_encoder");
    encoder.copy_texture_to_buffer(
        wgpu::TexelCopyTextureInfo {
            texture: &image.texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::TexelCopyBufferInfo {
            buffer: &readback,
            layout: wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(padded_bytes_per_row),
                rows_per_image: Some(image.height),
            },
        },
        wgpu::Extent3d {
            width: image.width,
            height: image.height,
            depth_or_array_layers: 1,
        },
    );
    ctx.submit_and_wait(encoder)
        .expect("quality regression readback submission should succeed");

    let slice = readback.slice(..);
    let (sender, receiver) = std::sync::mpsc::channel();
    slice.map_async(
        wgpu::MapMode::Read,
        move |result: Result<(), wgpu::BufferAsyncError>| {
            let _ = sender.send(result);
        },
    );
    ctx.device
        .poll(wgpu::PollType::wait_indefinitely())
        .expect("quality regression readback poll should succeed");
    receiver
        .recv()
        .expect("quality regression readback receive should succeed")
        .expect("quality regression map_async should succeed");

    let mapped = slice.get_mapped_range();
    let mut tight = vec![0_u8; (bytes_per_row * image.height) as usize];
    for row in 0..image.height as usize {
        let src_start = row * padded_bytes_per_row as usize;
        let src_end = src_start + bytes_per_row as usize;
        let dst_start = row * bytes_per_row as usize;
        let dst_end = dst_start + bytes_per_row as usize;
        tight[dst_start..dst_end].copy_from_slice(&mapped[src_start..src_end]);
    }
    drop(mapped);
    readback.unmap();

    tight
}

fn compute_signature(width: u32, height: u32, pixels: &[u8]) -> ImageSignature {
    let mut lumas = Vec::with_capacity((width * height) as usize);
    let mut mean_rgb = [0.0_f32; 3];
    let mut saturation_sum = 0.0_f32;
    let mut edge_energy = 0.0_f32;
    let mut highlight_count = 0.0_f32;
    let mut shadow_count = 0.0_f32;

    for y in 0..height {
        for x in 0..width {
            let idx = ((y * width + x) * 4) as usize;
            let rgb = [
                pixels[idx] as f32 / 255.0,
                pixels[idx + 1] as f32 / 255.0,
                pixels[idx + 2] as f32 / 255.0,
            ];
            let luma = luminance(rgb);
            let c_max = rgb[0].max(rgb[1].max(rgb[2]));
            let c_min = rgb[0].min(rgb[1].min(rgb[2]));
            let sat = if c_max <= 1e-5 {
                0.0
            } else {
                (c_max - c_min) / c_max
            };

            mean_rgb[0] += rgb[0];
            mean_rgb[1] += rgb[1];
            mean_rgb[2] += rgb[2];
            saturation_sum += sat;
            highlight_count += if luma > 0.82 { 1.0 } else { 0.0 };
            shadow_count += if luma < 0.18 { 1.0 } else { 0.0 };
            lumas.push(luma);

            if x + 1 < width {
                let right = pixel_rgb(pixels, width, x + 1, y);
                edge_energy += (luma - luminance(right)).abs();
            }
            if y + 1 < height {
                let down = pixel_rgb(pixels, width, x, y + 1);
                edge_energy += (luma - luminance(down)).abs();
            }
        }
    }

    let total = (width * height) as f32;
    mean_rgb[0] /= total;
    mean_rgb[1] /= total;
    mean_rgb[2] /= total;
    lumas.sort_by(|a, b| a.partial_cmp(b).expect("luma should be comparable"));

    ImageSignature {
        mean_rgb,
        luma_p10: percentile(&lumas, 0.10),
        luma_p50: percentile(&lumas, 0.50),
        luma_p90: percentile(&lumas, 0.90),
        saturation_mean: saturation_sum / total,
        edge_energy: edge_energy / total,
        highlight_ratio: highlight_count / total,
        shadow_ratio: shadow_count / total,
    }
}

fn scene_color(scene: SceneKind, x: u32, y: u32, width: u32, height: u32) -> [f32; 3] {
    let fx = x as f32 / (width.saturating_sub(1).max(1)) as f32;
    let fy = y as f32 / (height.saturating_sub(1).max(1)) as f32;
    let centered_x = fx * 2.0 - 1.0;
    let centered_y = fy * 2.0 - 1.0;
    let radial = (1.0 - (centered_x * centered_x + centered_y * centered_y).sqrt()).clamp(0.0, 1.0);

    match scene {
        SceneKind::CinematicGlow => {
            let warm_core = 0.28 + radial.powf(2.4) * 0.85;
            let cool_sides = 0.16 + (1.0 - radial) * 0.22;
            let horizon = (1.0 - (fy - 0.62).abs() * 1.8).clamp(0.0, 1.0);
            [
                (warm_core + horizon * 0.18).clamp(0.0, 1.0),
                (0.18 + warm_core * 0.72 + horizon * 0.10).clamp(0.0, 1.0),
                (cool_sides + horizon * 0.04).clamp(0.0, 1.0),
            ]
        }
        SceneKind::PortraitSemantic => {
            let skin_blob = smooth_ellipse(centered_x, centered_y, 0.0, -0.04, 0.34, 0.48);
            let body_blob = smooth_ellipse(centered_x, centered_y, 0.0, 0.16, 0.52, 0.82);
            let bg = 0.18 + fx * 0.10 + (1.0 - fy) * 0.12;
            [
                (bg + skin_blob * 0.46 + body_blob * 0.18).clamp(0.0, 1.0),
                (bg + skin_blob * 0.26 + body_blob * 0.14).clamp(0.0, 1.0),
                (bg + skin_blob * 0.18 + body_blob * 0.10 + (1.0 - fx) * 0.08).clamp(0.0, 1.0),
            ]
        }
        SceneKind::TextureFinish => {
            let ramp = 0.12 + fx * 0.70;
            let stripe = ((fx * 18.0).sin() * 0.5 + 0.5) * 0.08;
            let plate = smooth_ellipse(centered_x, centered_y, 0.0, 0.0, 0.78, 0.62) * 0.16;
            [
                (ramp + stripe + plate).clamp(0.0, 1.0),
                (0.10 + fy * 0.58 + plate).clamp(0.0, 1.0),
                (0.18 + (1.0 - fx) * 0.42 + stripe * 0.6).clamp(0.0, 1.0),
            ]
        }
    }
}

fn mask_value(kind: MaskKind, x: u32, y: u32, width: u32, height: u32) -> f32 {
    let fx = x as f32 / (width.saturating_sub(1).max(1)) as f32;
    let fy = y as f32 / (height.saturating_sub(1).max(1)) as f32;
    let centered_x = fx * 2.0 - 1.0;
    let centered_y = fy * 2.0 - 1.0;

    match kind {
        MaskKind::Face => smooth_ellipse(centered_x, centered_y, 0.0, -0.20, 0.22, 0.28),
        MaskKind::Person => smooth_ellipse(centered_x, centered_y, 0.0, 0.14, 0.40, 0.72),
        MaskKind::Foreground => smooth_ellipse(centered_x, centered_y, 0.0, 0.02, 0.56, 0.80),
        MaskKind::Highlight => (smooth_ellipse(centered_x, centered_y, 0.0, -0.10, 0.30, 0.24)
            * smoothstep_scalar(0.48, 0.88, 1.0 - fy))
        .clamp(0.0, 1.0),
        MaskKind::Shadow => ((1.0 - smoothstep_scalar(0.30, 0.76, 1.0 - fy))
            * smooth_ellipse(centered_x, centered_y, 0.0, 0.26, 0.58, 0.52))
        .clamp(0.0, 1.0),
    }
}

fn smooth_ellipse(x: f32, y: f32, cx: f32, cy: f32, rx: f32, ry: f32) -> f32 {
    let dx = (x - cx) / rx.max(1e-4);
    let dy = (y - cy) / ry.max(1e-4);
    let dist = (dx * dx + dy * dy).sqrt();
    (1.0 - smoothstep_scalar(0.82, 1.02, dist)).clamp(0.0, 1.0)
}

fn smoothstep_scalar(edge0: f32, edge1: f32, x: f32) -> f32 {
    let t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

fn pixel_rgb(pixels: &[u8], width: u32, x: u32, y: u32) -> [f32; 3] {
    let idx = ((y * width + x) * 4) as usize;
    [
        pixels[idx] as f32 / 255.0,
        pixels[idx + 1] as f32 / 255.0,
        pixels[idx + 2] as f32 / 255.0,
    ]
}

fn luminance(rgb: [f32; 3]) -> f32 {
    rgb[0] * 0.2126 + rgb[1] * 0.7152 + rgb[2] * 0.0722
}

fn percentile(sorted: &[f32], q: f32) -> f32 {
    let last = sorted.len().saturating_sub(1);
    let index = ((last as f32) * q).round() as usize;
    sorted[index.min(last)]
}

fn float_to_u8(value: f32) -> u8 {
    (value.clamp(0.0, 1.0) * 255.0).round() as u8
}

fn align_to(value: u32, alignment: u32) -> u32 {
    let remainder = value % alignment;
    if remainder == 0 {
        value
    } else {
        value + (alignment - remainder)
    }
}

fn block_on<F: Future>(future: F) -> F::Output {
    let mut future = std::pin::pin!(future);
    let mut context = Context::from_waker(Waker::noop());

    loop {
        match future.as_mut().poll(&mut context) {
            Poll::Ready(value) => return value,
            Poll::Pending => thread::sleep(Duration::from_millis(1)),
        }
    }
}
