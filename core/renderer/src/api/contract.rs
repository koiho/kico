use crate::api::{
    error::{RenderError, RenderResult},
    types::{
        BloomParams, ExposureWbParams, FaceLocalParams, ForegroundSubjectLocalParams,
        GlobalColorParams, GlobalToneParams, HalationParams, HueSectorAdjustment,
        LensCharacterParams, OutputFinishParams, PersonLocalParams, RenderGates, RenderParams,
        SectorColorParams, SemanticLocalParams, TextureSurfaceParams, TonalLocalParams,
        VignetteParams,
    },
};

#[derive(Debug, Clone, Copy)]
pub struct ParameterSpec {
    pub name: &'static str,
    pub min: f32,
    pub max: f32,
}

impl ParameterSpec {
    pub const fn new(name: &'static str, min: f32, max: f32) -> Self {
        Self { name, min, max }
    }

    pub fn decode(self, normalized: f32) -> f32 {
        let t = normalized.clamp(0.0, 1.0);
        self.min + t * (self.max - self.min)
    }
}

fn ensure_all_finite(values: &[f32], what: &'static str) -> RenderResult<()> {
    if let Some((index, _)) = values
        .iter()
        .enumerate()
        .find(|(_, value)| !value.is_finite())
    {
        return Err(RenderError::NonFiniteInput { what, index });
    }

    Ok(())
}

pub const PARAMETER_SPECS: [ParameterSpec; 100] = [
    ParameterSpec::new("exposure_ev", -2.5, 2.5),
    ParameterSpec::new("contrast", -1.0, 1.0),
    ParameterSpec::new("contrast_pivot", 0.18, 0.65),
    ParameterSpec::new("blacks", -0.4, 0.4),
    ParameterSpec::new("whites", -0.4, 0.4),
    ParameterSpec::new("shadows", -1.0, 1.0),
    ParameterSpec::new("highlights", -1.0, 1.0),
    ParameterSpec::new("toe_strength", 0.0, 1.0),
    ParameterSpec::new("shoulder_strength", 0.0, 1.0),
    ParameterSpec::new("fade", 0.0, 0.35),
    ParameterSpec::new("midtone_boost", -0.6, 0.6),
    ParameterSpec::new("clarity_global", -0.5, 0.5),
    ParameterSpec::new("wb_r_gain", 0.6, 1.8),
    ParameterSpec::new("wb_b_gain", 0.6, 1.8),
    ParameterSpec::new("global_saturation", 0.4, 1.8),
    ParameterSpec::new("global_vibrance", -0.8, 0.8),
    ParameterSpec::new("global_hue_shift", -12.0, 12.0),
    ParameterSpec::new("color_density", -0.5, 0.5),
    ParameterSpec::new("warmth_bias", -0.5, 0.5),
    ParameterSpec::new("green_magenta_bias", -0.35, 0.35),
    ParameterSpec::new("shadow_hue", 0.0, 360.0),
    ParameterSpec::new("shadow_sat", 0.0, 0.5),
    ParameterSpec::new("midtone_hue", 0.0, 360.0),
    ParameterSpec::new("midtone_sat", 0.0, 0.4),
    ParameterSpec::new("highlight_hue", 0.0, 360.0),
    ParameterSpec::new("highlight_sat", 0.0, 0.5),
    ParameterSpec::new("split_balance", -1.0, 1.0),
    ParameterSpec::new("red_hue_shift", -20.0, 20.0),
    ParameterSpec::new("red_sat_scale", 0.3, 1.8),
    ParameterSpec::new("red_luma_shift", -0.4, 0.4),
    ParameterSpec::new("yellow_hue_shift", -20.0, 20.0),
    ParameterSpec::new("yellow_sat_scale", 0.3, 1.8),
    ParameterSpec::new("yellow_luma_shift", -0.4, 0.4),
    ParameterSpec::new("green_hue_shift", -20.0, 20.0),
    ParameterSpec::new("green_sat_scale", 0.3, 1.8),
    ParameterSpec::new("green_luma_shift", -0.4, 0.4),
    ParameterSpec::new("cyan_hue_shift", -20.0, 20.0),
    ParameterSpec::new("cyan_sat_scale", 0.3, 1.8),
    ParameterSpec::new("cyan_luma_shift", -0.4, 0.4),
    ParameterSpec::new("blue_hue_shift", -20.0, 20.0),
    ParameterSpec::new("blue_sat_scale", 0.3, 1.8),
    ParameterSpec::new("blue_luma_shift", -0.4, 0.4),
    ParameterSpec::new("magenta_hue_shift", -20.0, 20.0),
    ParameterSpec::new("magenta_sat_scale", 0.3, 1.8),
    ParameterSpec::new("magenta_luma_shift", -0.4, 0.4),
    ParameterSpec::new("sector_width_scale", 0.7, 1.4),
    ParameterSpec::new("sector_smoothness", 0.0, 1.0),
    ParameterSpec::new("face_exposure", -0.4, 0.4),
    ParameterSpec::new("face_sat", 0.6, 1.4),
    ParameterSpec::new("face_hue_shift", -10.0, 10.0),
    ParameterSpec::new("face_warmth", -0.3, 0.3),
    ParameterSpec::new("face_soft_clarity", -0.5, 0.3),
    ParameterSpec::new("person_exposure", -0.5, 0.5),
    ParameterSpec::new("person_sat", 0.5, 1.6),
    ParameterSpec::new("person_hue_shift", -18.0, 18.0),
    ParameterSpec::new("person_clarity", -0.4, 0.6),
    ParameterSpec::new("foreground_subject_hue_shift", -18.0, 18.0),
    ParameterSpec::new("foreground_subject_sat", 0.5, 1.5),
    ParameterSpec::new("foreground_subject_luma", -0.3, 0.3),
    ParameterSpec::new("foreground_subject_exposure", -0.4, 0.4),
    ParameterSpec::new("foreground_subject_contrast", -0.3, 0.3),
    ParameterSpec::new("foreground_subject_pop", 0.0, 1.0),
    ParameterSpec::new("highlight_warmth_local", -0.4, 0.4),
    ParameterSpec::new("shadow_tint_local", -0.4, 0.4),
    ParameterSpec::new("shadow_desat", 0.0, 0.8),
    ParameterSpec::new("highlight_mask_threshold", 0.45, 0.95),
    ParameterSpec::new("highlight_mask_feather", 0.02, 0.25),
    ParameterSpec::new("shadow_mask_threshold", 0.05, 0.55),
    ParameterSpec::new("shadow_mask_feather", 0.02, 0.25),
    ParameterSpec::new("bloom_threshold", 0.55, 1.2),
    ParameterSpec::new("bloom_intensity", 0.0, 1.0),
    ParameterSpec::new("bloom_radius", 0.0, 1.0),
    ParameterSpec::new("bloom_softness", 0.0, 1.0),
    ParameterSpec::new("bloom_veil_mix", 0.0, 1.0),
    ParameterSpec::new("halation_threshold", 0.65, 1.3),
    ParameterSpec::new("halation_intensity", 0.0, 1.0),
    ParameterSpec::new("halation_radius", 0.0, 1.0),
    ParameterSpec::new("halation_red_bias", 0.0, 1.0),
    ParameterSpec::new("halation_warmth", 0.0, 1.0),
    ParameterSpec::new("halation_core_balance", 0.0, 1.0),
    ParameterSpec::new("vignette_amount", 0.0, 1.0),
    ParameterSpec::new("vignette_midpoint", 0.2, 0.9),
    ParameterSpec::new("vignette_feather", 0.0, 1.0),
    ParameterSpec::new("vignette_roundness", -1.0, 1.0),
    ParameterSpec::new("soft_glow", 0.0, 1.0),
    ParameterSpec::new("edge_softness", 0.0, 1.0),
    ParameterSpec::new("grain_luma_amount", 0.0, 1.0),
    ParameterSpec::new("grain_chroma_amount", 0.0, 0.6),
    ParameterSpec::new("grain_size", 0.2, 1.5),
    ParameterSpec::new("grain_shadow_bias", 0.0, 1.0),
    ParameterSpec::new("grain_highlight_suppress", 0.0, 1.0),
    ParameterSpec::new("texture_boost", -0.5, 0.6),
    ParameterSpec::new("noise_clean_bias", 0.0, 1.0),
    ParameterSpec::new("detail_preserve", 0.0, 1.0),
    ParameterSpec::new("texture_microcontrast_balance", -1.0, 1.0),
    ParameterSpec::new("gamut_compress", 0.0, 1.0),
    ParameterSpec::new("final_gamma_bias", 0.85, 1.15),
    ParameterSpec::new("highlight_clip_softness", 0.0, 1.0),
    ParameterSpec::new("highlight_rolloff_pivot", 0.7, 1.2),
    ParameterSpec::new("shadow_floor", 0.0, 0.2),
];

pub const GATE_NAMES: [&str; 11] = [
    "sector_color_gate",
    "face_gate",
    "person_gate",
    "foreground_subject_gate",
    "tonal_local_gate",
    "bloom_gate",
    "halation_gate",
    "vignette_gate",
    "lens_character_gate",
    "grain_gate",
    "texture_gate",
];

pub const MASK_NAMES: [&str; 5] = [
    "face",
    "person",
    "highlight",
    "shadow",
    "foreground_subject",
];

pub const RENDER_STAGE_ORDER: [&str; 12] = [
    "mask_prep",
    "exposure_wb",
    "global_tone",
    "global_color",
    "sector_color",
    "semantic_local",
    "bloom",
    "halation",
    "lens_character",
    "vignette",
    "texture_grain",
    "output_finish",
];

pub fn decode_render_params(values: &[f32]) -> RenderResult<RenderParams> {
    if values.len() != PARAMETER_SPECS.len() {
        return Err(RenderError::LengthMismatch {
            what: "renderer_params",
            expected: PARAMETER_SPECS.len(),
            actual: values.len(),
        });
    }
    ensure_all_finite(values, "renderer_params")?;

    let decode = |index: usize| PARAMETER_SPECS[index].decode(values[index]);

    Ok(RenderParams {
        exposure_wb: ExposureWbParams {
            exposure_ev: decode(0),
            wb_r_gain: decode(12),
            wb_b_gain: decode(13),
        },
        global_tone: GlobalToneParams {
            contrast: decode(1),
            contrast_pivot: decode(2),
            blacks: decode(3),
            whites: decode(4),
            shadows: decode(5),
            highlights: decode(6),
            toe_strength: decode(7),
            shoulder_strength: decode(8),
            fade: decode(9),
            midtone_boost: decode(10),
            clarity_global: decode(11),
        },
        global_color: GlobalColorParams {
            global_saturation: decode(14),
            global_vibrance: decode(15),
            global_hue_shift: decode(16),
            color_density: decode(17),
            warmth_bias: decode(18),
            green_magenta_bias: decode(19),
            shadow_hue: decode(20),
            shadow_sat: decode(21),
            midtone_hue: decode(22),
            midtone_sat: decode(23),
            highlight_hue: decode(24),
            highlight_sat: decode(25),
            split_balance: decode(26),
        },
        sector_color: SectorColorParams {
            red: HueSectorAdjustment {
                hue_shift: decode(27),
                sat_scale: decode(28),
                luma_shift: decode(29),
            },
            yellow: HueSectorAdjustment {
                hue_shift: decode(30),
                sat_scale: decode(31),
                luma_shift: decode(32),
            },
            green: HueSectorAdjustment {
                hue_shift: decode(33),
                sat_scale: decode(34),
                luma_shift: decode(35),
            },
            cyan: HueSectorAdjustment {
                hue_shift: decode(36),
                sat_scale: decode(37),
                luma_shift: decode(38),
            },
            blue: HueSectorAdjustment {
                hue_shift: decode(39),
                sat_scale: decode(40),
                luma_shift: decode(41),
            },
            magenta: HueSectorAdjustment {
                hue_shift: decode(42),
                sat_scale: decode(43),
                luma_shift: decode(44),
            },
            sector_width_scale: decode(45),
            sector_smoothness: decode(46),
        },
        semantic_local: SemanticLocalParams {
            face: FaceLocalParams {
                exposure: decode(47),
                saturation: decode(48),
                hue_shift: decode(49),
                warmth: decode(50),
                soft_clarity: decode(51),
            },
            person: PersonLocalParams {
                exposure: decode(52),
                saturation: decode(53),
                hue_shift: decode(54),
                clarity: decode(55),
            },
            foreground_subject: ForegroundSubjectLocalParams {
                hue_shift: decode(56),
                saturation: decode(57),
                luma: decode(58),
                exposure: decode(59),
                contrast: decode(60),
                pop: decode(61),
            },
            tonal_local: TonalLocalParams {
                highlight_warmth: decode(62),
                shadow_tint: decode(63),
                shadow_desat: decode(64),
                highlight_mask_threshold: decode(65),
                highlight_mask_feather: decode(66),
                shadow_mask_threshold: decode(67),
                shadow_mask_feather: decode(68),
            },
        },
        bloom: BloomParams {
            threshold: decode(69),
            intensity: decode(70),
            radius: decode(71),
            softness: decode(72),
            veil_mix: decode(73),
        },
        halation: HalationParams {
            threshold: decode(74),
            intensity: decode(75),
            radius: decode(76),
            red_bias: decode(77),
            warmth: decode(78),
            core_balance: decode(79),
        },
        vignette: VignetteParams {
            amount: decode(80),
            midpoint: decode(81),
            feather: decode(82),
            roundness: decode(83),
        },
        lens_character: LensCharacterParams {
            soft_glow: decode(84),
            edge_softness: decode(85),
        },
        texture_surface: TextureSurfaceParams {
            grain_luma_amount: decode(86),
            grain_chroma_amount: decode(87),
            grain_size: decode(88),
            grain_shadow_bias: decode(89),
            grain_highlight_suppress: decode(90),
            texture_boost: decode(91),
            noise_clean_bias: decode(92),
            detail_preserve: decode(93),
            microcontrast_balance: decode(94),
        },
        output_finish: OutputFinishParams {
            gamut_compress: decode(95),
            final_gamma_bias: decode(96),
            highlight_clip_softness: decode(97),
            highlight_rolloff_pivot: decode(98),
            shadow_floor: decode(99),
        },
    })
}

pub fn decode_render_gates(values: &[f32]) -> RenderResult<RenderGates> {
    if values.len() != GATE_NAMES.len() {
        return Err(RenderError::LengthMismatch {
            what: "module_gates",
            expected: GATE_NAMES.len(),
            actual: values.len(),
        });
    }
    ensure_all_finite(values, "module_gates")?;

    let gate = |index: usize| values[index].clamp(0.0, 1.0);

    Ok(RenderGates {
        sector_color_gate: gate(0),
        face_gate: gate(1),
        person_gate: gate(2),
        foreground_subject_gate: gate(3),
        tonal_local_gate: gate(4),
        bloom_gate: gate(5),
        halation_gate: gate(6),
        vignette_gate: gate(7),
        lens_character_gate: gate(8),
        grain_gate: gate(9),
        texture_gate: gate(10),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn contract_counts_match_model() {
        assert_eq!(PARAMETER_SPECS.len(), 100);
        assert_eq!(GATE_NAMES.len(), 11);
        assert_eq!(MASK_NAMES.len(), 5);
        assert_eq!(RENDER_STAGE_ORDER.len(), 12);
    }

    #[test]
    fn normalized_midpoint_decodes_reasonably() {
        let params = decode_render_params(&vec![0.5; PARAMETER_SPECS.len()]).unwrap();
        assert!((params.exposure_wb.exposure_ev - 0.0).abs() < 1e-6);
        assert!((params.global_tone.contrast - 0.0).abs() < 1e-6);
        assert!((params.exposure_wb.wb_r_gain - 1.2).abs() < 1e-6);
    }

    #[test]
    fn decode_render_params_rejects_non_finite_values() {
        let mut values = vec![0.5; PARAMETER_SPECS.len()];
        values[7] = f32::NAN;

        let error = decode_render_params(&values).unwrap_err();
        assert!(matches!(
            error,
            RenderError::NonFiniteInput {
                what: "renderer_params",
                index: 7,
            }
        ));
    }

    #[test]
    fn decode_render_gates_rejects_non_finite_values() {
        let mut values = vec![1.0; GATE_NAMES.len()];
        values[3] = f32::INFINITY;

        let error = decode_render_gates(&values).unwrap_err();
        assert!(matches!(
            error,
            RenderError::NonFiniteInput {
                what: "module_gates",
                index: 3,
            }
        ));
    }
}
