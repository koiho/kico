use super::pass_schedule::ShaderKey;

#[cfg(test)]
use std::collections::HashSet;

#[cfg(test)]
use crate::api::contract::{GATE_NAMES, MASK_NAMES, PARAMETER_SPECS, RENDER_STAGE_ORDER};

pub struct StageModelBinding {
    pub stage: &'static str,
    pub group: &'static str,
    pub params: &'static [&'static str],
    pub param_indices: &'static [usize],
    pub gates: &'static [&'static str],
    pub gate_indices: &'static [usize],
    pub masks: &'static [&'static str],
    pub uniform_pack_field: Option<&'static str>,
    pub uniform_blocks: &'static [&'static str],
    pub gpu_pass_name: Option<&'static str>,
    pub shader: Option<ShaderKey>,
    pub note: &'static str,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct IndexedModelBinding {
    pub index: usize,
    pub name: &'static str,
    pub stage: &'static str,
    pub group: &'static str,
    pub uniform_pack_field: Option<&'static str>,
    pub gpu_pass_name: Option<&'static str>,
    pub shader: Option<ShaderKey>,
}

const NONE: &[&str] = &[];
const ALL_MASKS: &[&str] = &[
    "face",
    "person",
    "highlight",
    "shadow",
    "foreground_subject",
];
const MASK_PREP_PARAMS: &[&str] = &[
    "highlight_mask_threshold",
    "highlight_mask_feather",
    "shadow_mask_threshold",
    "shadow_mask_feather",
];
const MASK_PREP_PARAM_INDICES: &[usize] = &[65, 66, 67, 68];

const EXPOSURE_WB_PARAMS: &[&str] = &["exposure_ev", "wb_r_gain", "wb_b_gain"];
const EXPOSURE_WB_PARAM_INDICES: &[usize] = &[0, 12, 13];
const GLOBAL_TONE_PARAMS: &[&str] = &[
    "contrast",
    "contrast_pivot",
    "blacks",
    "whites",
    "shadows",
    "highlights",
    "toe_strength",
    "shoulder_strength",
    "fade",
    "midtone_boost",
    "clarity_global",
];
const GLOBAL_TONE_PARAM_INDICES: &[usize] = &[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
const GLOBAL_COLOR_PARAMS: &[&str] = &[
    "global_saturation",
    "global_vibrance",
    "global_hue_shift",
    "color_density",
    "warmth_bias",
    "green_magenta_bias",
    "shadow_hue",
    "shadow_sat",
    "midtone_hue",
    "midtone_sat",
    "highlight_hue",
    "highlight_sat",
    "split_balance",
];
const GLOBAL_COLOR_PARAM_INDICES: &[usize] = &[14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26];
const SECTOR_COLOR_PARAMS: &[&str] = &[
    "red_hue_shift",
    "red_sat_scale",
    "red_luma_shift",
    "yellow_hue_shift",
    "yellow_sat_scale",
    "yellow_luma_shift",
    "green_hue_shift",
    "green_sat_scale",
    "green_luma_shift",
    "cyan_hue_shift",
    "cyan_sat_scale",
    "cyan_luma_shift",
    "blue_hue_shift",
    "blue_sat_scale",
    "blue_luma_shift",
    "magenta_hue_shift",
    "magenta_sat_scale",
    "magenta_luma_shift",
    "sector_width_scale",
    "sector_smoothness",
];
const SECTOR_COLOR_PARAM_INDICES: &[usize] = &[
    27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46,
];
const SEMANTIC_LOCAL_PARAMS: &[&str] = &[
    "face_exposure",
    "face_sat",
    "face_hue_shift",
    "face_warmth",
    "face_soft_clarity",
    "person_exposure",
    "person_sat",
    "person_hue_shift",
    "person_clarity",
    "foreground_subject_hue_shift",
    "foreground_subject_sat",
    "foreground_subject_luma",
    "foreground_subject_exposure",
    "foreground_subject_contrast",
    "foreground_subject_pop",
    "highlight_warmth_local",
    "shadow_tint_local",
    "shadow_desat",
];
const SEMANTIC_LOCAL_PARAM_INDICES: &[usize] = &[
    47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64,
];
const SEMANTIC_LOCAL_GATES: &[&str] = &[
    "face_gate",
    "person_gate",
    "foreground_subject_gate",
    "tonal_local_gate",
];
const SEMANTIC_LOCAL_GATE_INDICES: &[usize] = &[1, 2, 3, 4];
const SEMANTIC_LOCAL_MASKS: &[&str] = &[
    "face",
    "person",
    "highlight",
    "shadow",
    "foreground_subject",
];
const BLOOM_PARAMS: &[&str] = &[
    "bloom_threshold",
    "bloom_intensity",
    "bloom_radius",
    "bloom_softness",
    "bloom_veil_mix",
];
const BLOOM_PARAM_INDICES: &[usize] = &[69, 70, 71, 72, 73];
const HALATION_PARAMS: &[&str] = &[
    "halation_threshold",
    "halation_intensity",
    "halation_radius",
    "halation_red_bias",
    "halation_warmth",
    "halation_core_balance",
];
const HALATION_PARAM_INDICES: &[usize] = &[74, 75, 76, 77, 78, 79];
const VIGNETTE_PARAMS: &[&str] = &[
    "vignette_amount",
    "vignette_midpoint",
    "vignette_feather",
    "vignette_roundness",
];
const VIGNETTE_PARAM_INDICES: &[usize] = &[80, 81, 82, 83];
const LENS_CHARACTER_PARAMS: &[&str] = &["soft_glow", "edge_softness"];
const LENS_CHARACTER_PARAM_INDICES: &[usize] = &[84, 85];
const TEXTURE_GRAIN_PARAMS: &[&str] = &[
    "grain_luma_amount",
    "grain_chroma_amount",
    "grain_size",
    "grain_shadow_bias",
    "grain_highlight_suppress",
    "texture_boost",
    "noise_clean_bias",
    "detail_preserve",
    "texture_microcontrast_balance",
];
const TEXTURE_GRAIN_PARAM_INDICES: &[usize] = &[86, 87, 88, 89, 90, 91, 92, 93, 94];
const TEXTURE_GRAIN_GATES: &[&str] = &["grain_gate", "texture_gate"];
const TEXTURE_GRAIN_GATE_INDICES: &[usize] = &[9, 10];
const OUTPUT_FINISH_PARAMS: &[&str] = &[
    "gamut_compress",
    "final_gamma_bias",
    "highlight_clip_softness",
    "highlight_rolloff_pivot",
    "shadow_floor",
];
const OUTPUT_FINISH_PARAM_INDICES: &[usize] = &[95, 96, 97, 98, 99];

pub const STAGE_MODEL_BINDINGS: [StageModelBinding; 12] = [
    StageModelBinding {
        stage: "mask_prep",
        group: "input",
        params: MASK_PREP_PARAMS,
        param_indices: MASK_PREP_PARAM_INDICES,
        gates: NONE,
        gate_indices: &[],
        masks: ALL_MASKS,
        uniform_pack_field: None,
        uniform_blocks: NONE,
        gpu_pass_name: None,
        shader: None,
        note: "Normalize incoming masks and synthesize tonal masks with learned threshold and feather controls before any local stage reads them.",
    },
    StageModelBinding {
        stage: "exposure_wb",
        group: "global",
        params: EXPOSURE_WB_PARAMS,
        param_indices: EXPOSURE_WB_PARAM_INDICES,
        gates: NONE,
        gate_indices: &[],
        masks: NONE,
        uniform_pack_field: Some("exposure_wb_tone"),
        uniform_blocks: &["exposure_wb"],
        gpu_pass_name: Some("pass_1_exposure_wb_tone"),
        shader: Some(ShaderKey::ExposureWbTone),
        note: "Fused into pass 1 with global_tone for fewer full-resolution reads and writes.",
    },
    StageModelBinding {
        stage: "global_tone",
        group: "global",
        params: GLOBAL_TONE_PARAMS,
        param_indices: GLOBAL_TONE_PARAM_INDICES,
        gates: NONE,
        gate_indices: &[],
        masks: NONE,
        uniform_pack_field: Some("exposure_wb_tone"),
        uniform_blocks: &["tone_a", "tone_b", "tone_c"],
        gpu_pass_name: Some("pass_1_exposure_wb_tone"),
        shader: Some(ShaderKey::ExposureWbTone),
        note: "Shares a uniform pack and shader pass with exposure_wb because both act globally in linear space.",
    },
    StageModelBinding {
        stage: "global_color",
        group: "global",
        params: GLOBAL_COLOR_PARAMS,
        param_indices: GLOBAL_COLOR_PARAM_INDICES,
        gates: NONE,
        gate_indices: &[],
        masks: NONE,
        uniform_pack_field: Some("global_color_sector"),
        uniform_blocks: &[
            "global_a",
            "global_b",
            "split_shadow",
            "split_midtone",
            "split_highlight",
        ],
        gpu_pass_name: Some("pass_2_global_color_sector"),
        shader: Some(ShaderKey::GlobalColorSector),
        note: "Carries the scene-wide color mood before hue-sector isolation refines specific bands.",
    },
    StageModelBinding {
        stage: "sector_color",
        group: "global",
        params: SECTOR_COLOR_PARAMS,
        param_indices: SECTOR_COLOR_PARAM_INDICES,
        gates: &["sector_color_gate"],
        gate_indices: &[0],
        masks: NONE,
        uniform_pack_field: Some("global_color_sector"),
        uniform_blocks: &[
            "red",
            "yellow",
            "green",
            "cyan",
            "blue",
            "magenta",
            "sector_shared",
        ],
        gpu_pass_name: Some("pass_2_global_color_sector"),
        shader: Some(ShaderKey::GlobalColorSector),
        note: "Also fused into pass 2, with one gate controlling whether sector adjustments meaningfully contribute.",
    },
    StageModelBinding {
        stage: "semantic_local",
        group: "local",
        params: SEMANTIC_LOCAL_PARAMS,
        param_indices: SEMANTIC_LOCAL_PARAM_INDICES,
        gates: SEMANTIC_LOCAL_GATES,
        gate_indices: SEMANTIC_LOCAL_GATE_INDICES,
        masks: SEMANTIC_LOCAL_MASKS,
        uniform_pack_field: Some("semantic_local"),
        uniform_blocks: &[
            "face_a",
            "face_b",
            "person_a",
            "foreground_a",
            "foreground_b",
            "tonal_a",
            "gates",
        ],
        gpu_pass_name: Some("pass_3_semantic_local"),
        shader: Some(ShaderKey::SemanticLocal),
        note: "This is the only full-resolution pass that consumes prepared masks directly.",
    },
    StageModelBinding {
        stage: "bloom",
        group: "optical",
        params: BLOOM_PARAMS,
        param_indices: BLOOM_PARAM_INDICES,
        gates: &["bloom_gate"],
        gate_indices: &[5],
        masks: NONE,
        uniform_pack_field: Some("bloom"),
        uniform_blocks: &["params", "gate"],
        gpu_pass_name: Some("pass_4_bloom"),
        shader: Some(ShaderKey::Bloom),
        note: "Triggers a high-resolution multi-scale bloom pyramid rather than a lightweight fullscreen blur.",
    },
    StageModelBinding {
        stage: "halation",
        group: "optical",
        params: HALATION_PARAMS,
        param_indices: HALATION_PARAM_INDICES,
        gates: &["halation_gate"],
        gate_indices: &[6],
        masks: NONE,
        uniform_pack_field: Some("halation"),
        uniform_blocks: &["params_a", "params_b"],
        gpu_pass_name: Some("pass_5_halation"),
        shader: Some(ShaderKey::Halation),
        note: "Uses highlight extraction plus warm-biased blur, separate from bloom for film-like glow control.",
    },
    StageModelBinding {
        stage: "lens_character",
        group: "optical",
        params: LENS_CHARACTER_PARAMS,
        param_indices: LENS_CHARACTER_PARAM_INDICES,
        gates: &["lens_character_gate"],
        gate_indices: &[8],
        masks: NONE,
        uniform_pack_field: Some("vignette_lens"),
        uniform_blocks: &["vignette", "lens"],
        gpu_pass_name: Some("pass_6_lens_character"),
        shader: Some(ShaderKey::VignetteLens),
        note: "Runs after bloom and halation are merged so glow extraction sees the pre-vignette optical result.",
    },
    StageModelBinding {
        stage: "vignette",
        group: "optical",
        params: VIGNETTE_PARAMS,
        param_indices: VIGNETTE_PARAM_INDICES,
        gates: &["vignette_gate"],
        gate_indices: &[7],
        masks: NONE,
        uniform_pack_field: Some("vignette_lens"),
        uniform_blocks: &["vignette", "lens"],
        gpu_pass_name: Some("pass_7_vignette"),
        shader: Some(ShaderKey::VignetteLens),
        note: "Runs after lens character so edge darkening does not suppress later glow extraction.",
    },
    StageModelBinding {
        stage: "texture_grain",
        group: "output",
        params: TEXTURE_GRAIN_PARAMS,
        param_indices: TEXTURE_GRAIN_PARAM_INDICES,
        gates: TEXTURE_GRAIN_GATES,
        gate_indices: TEXTURE_GRAIN_GATE_INDICES,
        masks: NONE,
        uniform_pack_field: Some("texture_finish"),
        uniform_blocks: &["grain_a", "grain_b", "texture"],
        gpu_pass_name: Some("pass_8_texture_grain"),
        shader: Some(ShaderKey::TextureFinish),
        note: "Owns texture and grain shaping as its own full-resolution pass before output finishing.",
    },
    StageModelBinding {
        stage: "output_finish",
        group: "output",
        params: OUTPUT_FINISH_PARAMS,
        param_indices: OUTPUT_FINISH_PARAM_INDICES,
        gates: NONE,
        gate_indices: &[],
        masks: NONE,
        uniform_pack_field: Some("texture_finish"),
        uniform_blocks: &["finish"],
        gpu_pass_name: Some("pass_9_output_finish"),
        shader: Some(ShaderKey::TextureFinish),
        note: "Handles export-facing tone finishing while leaving final color-space conversion to the native layer.",
    },
];

pub fn parameter_model_binding(index: usize) -> Option<IndexedModelBinding> {
    for binding in &STAGE_MODEL_BINDINGS {
        for (offset, param_index) in binding.param_indices.iter().copied().enumerate() {
            if param_index == index {
                return Some(IndexedModelBinding {
                    index,
                    name: binding.params[offset],
                    stage: binding.stage,
                    group: binding.group,
                    uniform_pack_field: binding.uniform_pack_field,
                    gpu_pass_name: binding.gpu_pass_name,
                    shader: binding.shader,
                });
            }
        }
    }

    None
}

pub fn gate_model_binding(index: usize) -> Option<IndexedModelBinding> {
    for binding in &STAGE_MODEL_BINDINGS {
        for (offset, gate_index) in binding.gate_indices.iter().copied().enumerate() {
            if gate_index == index {
                return Some(IndexedModelBinding {
                    index,
                    name: binding.gates[offset],
                    stage: binding.stage,
                    group: binding.group,
                    uniform_pack_field: binding.uniform_pack_field,
                    gpu_pass_name: binding.gpu_pass_name,
                    shader: binding.shader,
                });
            }
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stage_bindings_follow_contract_stage_order() {
        let stages: Vec<_> = STAGE_MODEL_BINDINGS
            .iter()
            .map(|binding| binding.stage)
            .collect();
        assert_eq!(stages.as_slice(), RENDER_STAGE_ORDER.as_slice());
    }

    #[test]
    fn stage_bindings_cover_all_params_exactly_once() {
        let mut seen = HashSet::new();

        for binding in &STAGE_MODEL_BINDINGS {
            assert_eq!(binding.params.len(), binding.param_indices.len());
            for name in binding.params {
                assert!(seen.insert(*name), "duplicate param binding for {name}");
            }
        }

        let expected: HashSet<_> = PARAMETER_SPECS.iter().map(|spec| spec.name).collect();
        assert_eq!(seen, expected);
    }

    #[test]
    fn stage_bindings_cover_all_gates_exactly_once() {
        let mut seen = HashSet::new();

        for binding in &STAGE_MODEL_BINDINGS {
            assert_eq!(binding.gates.len(), binding.gate_indices.len());
            for name in binding.gates {
                assert!(seen.insert(*name), "duplicate gate binding for {name}");
            }
        }

        let expected: HashSet<_> = GATE_NAMES.iter().copied().collect();
        assert_eq!(seen, expected);
    }

    #[test]
    fn stage_bindings_only_reference_known_masks() {
        let known: HashSet<_> = MASK_NAMES.iter().copied().collect();

        for binding in &STAGE_MODEL_BINDINGS {
            for name in binding.masks {
                assert!(
                    known.contains(name),
                    "unknown mask binding {name} in stage {}",
                    binding.stage
                );
            }
        }
    }

    #[test]
    fn parameter_model_binding_matches_contract_order() {
        for (index, spec) in PARAMETER_SPECS.iter().enumerate() {
            let binding = parameter_model_binding(index).expect("param binding should exist");
            assert_eq!(binding.index, index);
            assert_eq!(binding.name, spec.name);
        }
    }

    #[test]
    fn gate_model_binding_matches_contract_order() {
        for (index, name) in GATE_NAMES.iter().copied().enumerate() {
            let binding = gate_model_binding(index).expect("gate binding should exist");
            assert_eq!(binding.index, index);
            assert_eq!(binding.name, name);
        }
    }
}
