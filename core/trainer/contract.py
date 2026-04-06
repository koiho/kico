from __future__ import annotations


EXPORT_SCHEMA_VERSION = 1

# These contiguous slices define the model head layout in trainer.
GLOBAL_TONE_DIM = 12
GLOBAL_COLOR_DIM = 15
SECTOR_COLOR_DIM = 20
FACE_PARAM_DIM = 5
PERSON_PARAM_DIM = 4
FOREGROUND_PARAM_DIM = 6
TONAL_PARAM_DIM = 7
OPTICS_ATMOSPHERE_DIM = 17
TEXTURE_SURFACE_DIM = 9
OUTPUT_FINISH_DIM = 5

PARAMETER_NAMES = (
    "exposure_ev",
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
    "wb_r_gain",
    "wb_b_gain",
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
    "highlight_mask_threshold",
    "highlight_mask_feather",
    "shadow_mask_threshold",
    "shadow_mask_feather",
    "bloom_threshold",
    "bloom_intensity",
    "bloom_radius",
    "bloom_softness",
    "bloom_veil_mix",
    "halation_threshold",
    "halation_intensity",
    "halation_radius",
    "halation_red_bias",
    "halation_warmth",
    "halation_core_balance",
    "vignette_amount",
    "vignette_midpoint",
    "vignette_feather",
    "vignette_roundness",
    "soft_glow",
    "edge_softness",
    "grain_luma_amount",
    "grain_chroma_amount",
    "grain_size",
    "grain_shadow_bias",
    "grain_highlight_suppress",
    "texture_boost",
    "noise_clean_bias",
    "detail_preserve",
    "texture_microcontrast_balance",
    "gamut_compress",
    "final_gamma_bias",
    "highlight_clip_softness",
    "highlight_rolloff_pivot",
    "shadow_floor",
)

PARAMETER_RANGES = (
    (-2.5, 2.5),
    (-1.0, 1.0),
    (0.18, 0.65),
    (-0.4, 0.4),
    (-0.4, 0.4),
    (-1.0, 1.0),
    (-1.0, 1.0),
    (0.0, 1.0),
    (0.0, 1.0),
    (0.0, 0.35),
    (-0.6, 0.6),
    (-0.5, 0.5),
    (0.6, 1.8),
    (0.6, 1.8),
    (0.4, 1.8),
    (-0.8, 0.8),
    (-12.0, 12.0),
    (-0.5, 0.5),
    (-0.5, 0.5),
    (-0.35, 0.35),
    (0.0, 360.0),
    (0.0, 0.5),
    (0.0, 360.0),
    (0.0, 0.4),
    (0.0, 360.0),
    (0.0, 0.5),
    (-1.0, 1.0),
    (-20.0, 20.0),
    (0.3, 1.8),
    (-0.4, 0.4),
    (-20.0, 20.0),
    (0.3, 1.8),
    (-0.4, 0.4),
    (-20.0, 20.0),
    (0.3, 1.8),
    (-0.4, 0.4),
    (-20.0, 20.0),
    (0.3, 1.8),
    (-0.4, 0.4),
    (-20.0, 20.0),
    (0.3, 1.8),
    (-0.4, 0.4),
    (-20.0, 20.0),
    (0.3, 1.8),
    (-0.4, 0.4),
    (0.7, 1.4),
    (0.0, 1.0),
    (-0.4, 0.4),
    (0.6, 1.4),
    (-10.0, 10.0),
    (-0.3, 0.3),
    (-0.5, 0.3),
    (-0.5, 0.5),
    (0.5, 1.6),
    (-18.0, 18.0),
    (-0.4, 0.6),
    (-18.0, 18.0),
    (0.5, 1.5),
    (-0.3, 0.3),
    (-0.4, 0.4),
    (-0.3, 0.3),
    (0.0, 1.0),
    (-0.4, 0.4),
    (-0.4, 0.4),
    (0.0, 0.8),
    (0.45, 0.95),
    (0.02, 0.25),
    (0.05, 0.55),
    (0.02, 0.25),
    (0.55, 1.2),
    (0.0, 1.0),
    (0.0, 1.0),
    (0.0, 1.0),
    (0.0, 1.0),
    (0.65, 1.3),
    (0.0, 1.0),
    (0.0, 1.0),
    (0.0, 1.0),
    (0.0, 1.0),
    (0.0, 1.0),
    (0.0, 1.0),
    (0.2, 0.9),
    (0.0, 1.0),
    (-1.0, 1.0),
    (0.0, 1.0),
    (0.0, 1.0),
    (0.0, 1.0),
    (0.0, 0.6),
    (0.2, 1.5),
    (0.0, 1.0),
    (0.0, 1.0),
    (-0.5, 0.6),
    (0.0, 1.0),
    (0.0, 1.0),
    (-1.0, 1.0),
    (0.0, 1.0),
    (0.85, 1.15),
    (0.0, 1.0),
    (0.7, 1.2),
    (0.0, 0.2),
)

GATE_NAMES = (
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
)

MASK_NAMES = (
    "face",
    "person",
    "highlight",
    "shadow",
    "foreground_subject",
)

TOTAL_PARAMETER_DIM = len(PARAMETER_NAMES)
TOTAL_GATE_DIM = len(GATE_NAMES)
MASK_DIM = len(MASK_NAMES)

if (
    GLOBAL_TONE_DIM
    + GLOBAL_COLOR_DIM
    + SECTOR_COLOR_DIM
    + FACE_PARAM_DIM
    + PERSON_PARAM_DIM
    + FOREGROUND_PARAM_DIM
    + TONAL_PARAM_DIM
    + OPTICS_ATMOSPHERE_DIM
    + TEXTURE_SURFACE_DIM
    + OUTPUT_FINISH_DIM
) != TOTAL_PARAMETER_DIM:
    raise ValueError("trainer head dims no longer match trainer parameter dim")


_PARAMETER_INDEX_BY_NAME = {name: index for index, name in enumerate(PARAMETER_NAMES)}
_GATE_INDEX_BY_NAME = {name: index for index, name in enumerate(GATE_NAMES)}
_MASK_INDEX_BY_NAME = {name: index for index, name in enumerate(MASK_NAMES)}


def parameter_index(name: str) -> int:
    try:
        return _PARAMETER_INDEX_BY_NAME[name]
    except KeyError as error:
        raise ValueError(f"unknown parameter name `{name}`") from error


def gate_index(name: str) -> int:
    try:
        return _GATE_INDEX_BY_NAME[name]
    except KeyError as error:
        raise ValueError(f"unknown gate name `{name}`") from error


def mask_index(name: str) -> int:
    try:
        return _MASK_INDEX_BY_NAME[name]
    except KeyError as error:
        raise ValueError(f"unknown mask name `{name}`") from error


def parameter_range(name: str) -> tuple[float, float]:
    return PARAMETER_RANGES[parameter_index(name)]


def parameter_is_bipolar(index: int) -> bool:
    low, high = PARAMETER_RANGES[index]
    return low < 0.0 < high
