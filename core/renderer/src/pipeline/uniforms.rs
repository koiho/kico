use bytemuck::{Pod, Zeroable};

use crate::api::types::{RenderGates, RenderParams};

#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
pub struct ExposureWbToneUniform {
    pub exposure_wb: [f32; 4],
    pub tone_a: [f32; 4],
    pub tone_b: [f32; 4],
    pub tone_c: [f32; 4],
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
pub struct GlobalColorSectorUniform {
    pub global_a: [f32; 4],
    pub global_b: [f32; 4],
    pub split_shadow: [f32; 4],
    pub split_midtone: [f32; 4],
    pub split_highlight: [f32; 4],
    pub red: [f32; 4],
    pub yellow: [f32; 4],
    pub green: [f32; 4],
    pub cyan: [f32; 4],
    pub blue: [f32; 4],
    pub magenta: [f32; 4],
    pub sector_shared: [f32; 4],
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
pub struct SemanticLocalUniform {
    pub face_a: [f32; 4],
    pub face_b: [f32; 4],
    pub person_a: [f32; 4],
    pub foreground_a: [f32; 4],
    pub foreground_b: [f32; 4],
    pub tonal_a: [f32; 4],
    pub gates: [f32; 4],
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
pub struct BloomUniform {
    pub params: [f32; 4],
    pub gate: [f32; 4],
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
pub struct HalationUniform {
    pub params_a: [f32; 4],
    pub params_b: [f32; 4],
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
pub struct VignetteLensUniform {
    pub vignette: [f32; 4],
    pub lens: [f32; 4],
    pub scale: [f32; 4],
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
pub struct TextureFinishUniform {
    pub grain_a: [f32; 4],
    pub grain_b: [f32; 4],
    pub texture: [f32; 4],
    pub finish: [f32; 4],
    pub scale: [f32; 4],
}

#[derive(Debug, Clone, Copy)]
pub struct RenderPassUniformPack {
    pub exposure_wb_tone: ExposureWbToneUniform,
    pub global_color_sector: GlobalColorSectorUniform,
    pub semantic_local: SemanticLocalUniform,
    pub bloom: BloomUniform,
    pub halation: HalationUniform,
    pub vignette_lens: VignetteLensUniform,
    pub texture_finish: TextureFinishUniform,
}

impl RenderPassUniformPack {
    pub fn from_params_with_size(
        params: &RenderParams,
        gates: &RenderGates,
        image_width: u32,
    ) -> Self {
        let texel_scale = image_width.max(1) as f32 / 256.0_f32;
        Self {
            exposure_wb_tone: ExposureWbToneUniform {
                exposure_wb: [
                    params.exposure_wb.exposure_ev,
                    params.exposure_wb.wb_r_gain,
                    params.exposure_wb.wb_b_gain,
                    params.global_tone.contrast,
                ],
                tone_a: [
                    params.global_tone.contrast_pivot,
                    params.global_tone.blacks,
                    params.global_tone.whites,
                    params.global_tone.shadows,
                ],
                tone_b: [
                    params.global_tone.highlights,
                    params.global_tone.toe_strength,
                    params.global_tone.shoulder_strength,
                    params.global_tone.fade,
                ],
                tone_c: [
                    params.global_tone.midtone_boost,
                    params.global_tone.clarity_global,
                    texel_scale,
                    0.0,
                ],
            },
            global_color_sector: GlobalColorSectorUniform {
                global_a: [
                    params.global_color.global_saturation,
                    params.global_color.global_vibrance,
                    params.global_color.global_hue_shift,
                    params.global_color.color_density,
                ],
                global_b: [
                    params.global_color.warmth_bias,
                    params.global_color.green_magenta_bias,
                    params.global_color.split_balance,
                    gates.sector_color_gate,
                ],
                split_shadow: [
                    params.global_color.shadow_hue,
                    params.global_color.shadow_sat,
                    0.0,
                    0.0,
                ],
                split_midtone: [
                    params.global_color.midtone_hue,
                    params.global_color.midtone_sat,
                    0.0,
                    0.0,
                ],
                split_highlight: [
                    params.global_color.highlight_hue,
                    params.global_color.highlight_sat,
                    0.0,
                    0.0,
                ],
                red: [
                    params.sector_color.red.hue_shift,
                    params.sector_color.red.sat_scale,
                    params.sector_color.red.luma_shift,
                    0.0,
                ],
                yellow: [
                    params.sector_color.yellow.hue_shift,
                    params.sector_color.yellow.sat_scale,
                    params.sector_color.yellow.luma_shift,
                    0.0,
                ],
                green: [
                    params.sector_color.green.hue_shift,
                    params.sector_color.green.sat_scale,
                    params.sector_color.green.luma_shift,
                    0.0,
                ],
                cyan: [
                    params.sector_color.cyan.hue_shift,
                    params.sector_color.cyan.sat_scale,
                    params.sector_color.cyan.luma_shift,
                    0.0,
                ],
                blue: [
                    params.sector_color.blue.hue_shift,
                    params.sector_color.blue.sat_scale,
                    params.sector_color.blue.luma_shift,
                    0.0,
                ],
                magenta: [
                    params.sector_color.magenta.hue_shift,
                    params.sector_color.magenta.sat_scale,
                    params.sector_color.magenta.luma_shift,
                    0.0,
                ],
                sector_shared: [
                    params.sector_color.sector_width_scale,
                    params.sector_color.sector_smoothness,
                    0.0,
                    0.0,
                ],
            },
            semantic_local: SemanticLocalUniform {
                face_a: [
                    params.semantic_local.face.exposure,
                    params.semantic_local.face.saturation,
                    params.semantic_local.face.hue_shift,
                    params.semantic_local.face.warmth,
                ],
                face_b: [params.semantic_local.face.soft_clarity, 0.0, 0.0, 0.0],
                person_a: [
                    params.semantic_local.person.exposure,
                    params.semantic_local.person.saturation,
                    params.semantic_local.person.hue_shift,
                    params.semantic_local.person.clarity,
                ],
                foreground_a: [
                    params.semantic_local.foreground_subject.hue_shift,
                    params.semantic_local.foreground_subject.saturation,
                    params.semantic_local.foreground_subject.luma,
                    params.semantic_local.foreground_subject.exposure,
                ],
                foreground_b: [
                    params.semantic_local.foreground_subject.contrast,
                    params.semantic_local.foreground_subject.pop,
                    0.0,
                    0.0,
                ],
                tonal_a: [
                    params.semantic_local.tonal_local.highlight_warmth,
                    params.semantic_local.tonal_local.shadow_tint,
                    params.semantic_local.tonal_local.shadow_desat,
                    texel_scale,
                ],
                gates: [
                    gates.face_gate,
                    gates.person_gate,
                    gates.foreground_subject_gate,
                    gates.tonal_local_gate,
                ],
            },
            bloom: BloomUniform {
                params: [
                    params.bloom.threshold,
                    params.bloom.intensity,
                    params.bloom.radius,
                    params.bloom.softness,
                ],
                gate: [gates.bloom_gate, params.bloom.veil_mix, 0.0, 0.0],
            },
            halation: HalationUniform {
                params_a: [
                    params.halation.threshold,
                    params.halation.intensity,
                    params.halation.radius,
                    params.halation.red_bias,
                ],
                params_b: [
                    params.halation.warmth,
                    gates.halation_gate,
                    params.halation.core_balance,
                    0.0,
                ],
            },
            vignette_lens: VignetteLensUniform {
                vignette: [
                    params.vignette.amount,
                    params.vignette.midpoint,
                    params.vignette.feather,
                    params.vignette.roundness,
                ],
                lens: [
                    params.lens_character.soft_glow,
                    params.lens_character.edge_softness,
                    gates.vignette_gate,
                    gates.lens_character_gate,
                ],
                scale: [texel_scale, 0.0, 0.0, 0.0],
            },
            texture_finish: TextureFinishUniform {
                grain_a: [
                    params.texture_surface.grain_luma_amount,
                    params.texture_surface.grain_chroma_amount,
                    params.texture_surface.grain_size,
                    gates.grain_gate,
                ],
                grain_b: [
                    params.texture_surface.grain_shadow_bias,
                    params.texture_surface.grain_highlight_suppress,
                    params.texture_surface.microcontrast_balance,
                    params.output_finish.shadow_floor,
                ],
                texture: [
                    params.texture_surface.texture_boost,
                    params.texture_surface.noise_clean_bias,
                    params.texture_surface.detail_preserve,
                    gates.texture_gate,
                ],
                finish: [
                    params.output_finish.gamut_compress,
                    params.output_finish.final_gamma_bias,
                    params.output_finish.highlight_clip_softness,
                    params.output_finish.highlight_rolloff_pivot,
                ],
                scale: [texel_scale, 0.0, 0.0, 0.0],
            },
        }
    }
}
