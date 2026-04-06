#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ShaderKey {
    ExposureWbTone,
    GlobalColorSector,
    SemanticLocal,
    Bloom,
    Halation,
    VignetteLens,
    TextureFinish,
}

#[derive(Debug, Clone, Copy)]
pub struct GpuPassDescriptor {
    pub name: &'static str,
    pub shader: ShaderKey,
    pub reads_masks: bool,
    pub note: &'static str,
}

pub const GPU_PASS_ORDER: [GpuPassDescriptor; 9] = [
    GpuPassDescriptor {
        name: "pass_1_exposure_wb_tone",
        shader: ShaderKey::ExposureWbTone,
        reads_masks: false,
        note: "Fuse exposure, white balance, and global tone into one fullscreen pass.",
    },
    GpuPassDescriptor {
        name: "pass_2_global_color_sector",
        shader: ShaderKey::GlobalColorSector,
        reads_masks: false,
        note: "Apply global color mood and sector color in the fixed order.",
    },
    GpuPassDescriptor {
        name: "pass_3_semantic_local",
        shader: ShaderKey::SemanticLocal,
        reads_masks: true,
        note: "Apply face, person, foreground-subject, and tonal-local adjustments.",
    },
    GpuPassDescriptor {
        name: "pass_4_bloom",
        shader: ShaderKey::Bloom,
        reads_masks: false,
        note: "Use bright-pass extraction plus a high-resolution multi-scale blur pyramid for bloom.",
    },
    GpuPassDescriptor {
        name: "pass_5_halation",
        shader: ShaderKey::Halation,
        reads_masks: false,
        note: "Use highlight extraction, warm-biased shaping, and a high-resolution halation pyramid.",
    },
    GpuPassDescriptor {
        name: "pass_6_lens_character",
        shader: ShaderKey::VignetteLens,
        reads_masks: false,
        note: "Apply high-quality lens glow and edge softness after optical branches are merged.",
    },
    GpuPassDescriptor {
        name: "pass_7_vignette",
        shader: ShaderKey::VignetteLens,
        reads_masks: false,
        note: "Apply analytic vignette after lens character so corner darkening does not gate glow extraction.",
    },
    GpuPassDescriptor {
        name: "pass_8_texture_grain",
        shader: ShaderKey::TextureFinish,
        reads_masks: false,
        note: "Apply texture and grain shaping as a dedicated full-resolution pass.",
    },
    GpuPassDescriptor {
        name: "pass_9_output_finish",
        shader: ShaderKey::TextureFinish,
        reads_masks: false,
        note: "Apply final gamut compression, highlight rolloff, gamma bias, and shadow floor.",
    },
];
