use std::{fmt, sync::Arc};

use serde::{Deserialize, Serialize};

use crate::api::{
    contract::{decode_render_gates, decode_render_params},
    error::{RenderError, RenderResult},
};

#[derive(Clone)]
pub struct GpuImage {
    pub texture: Arc<wgpu::Texture>,
    pub view: Arc<wgpu::TextureView>,
    pub width: u32,
    pub height: u32,
    pub format: wgpu::TextureFormat,
    pub label: String,
    pub(crate) _recycle_token: Option<GpuRecycleToken>,
}

impl std::fmt::Debug for GpuImage {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("GpuImage")
            .field("width", &self.width)
            .field("height", &self.height)
            .field("format", &self.format)
            .field("label", &self.label)
            .finish()
    }
}

impl GpuImage {
    pub fn new(
        texture: wgpu::Texture,
        view: wgpu::TextureView,
        width: u32,
        height: u32,
        format: wgpu::TextureFormat,
        label: impl Into<String>,
    ) -> Self {
        Self::from_shared(
            Arc::new(texture),
            Arc::new(view),
            width,
            height,
            format,
            label,
            None,
        )
    }

    pub(crate) fn from_shared(
        texture: Arc<wgpu::Texture>,
        view: Arc<wgpu::TextureView>,
        width: u32,
        height: u32,
        format: wgpu::TextureFormat,
        label: impl Into<String>,
        recycle_token: Option<GpuRecycleToken>,
    ) -> Self {
        Self {
            texture,
            view,
            width,
            height,
            format,
            label: label.into(),
            _recycle_token: recycle_token,
        }
    }
}

pub(crate) type GpuRecycleToken = Arc<RecycleTokenInner>;

pub(crate) fn make_recycle_token(on_drop: impl Fn() + Send + Sync + 'static) -> GpuRecycleToken {
    Arc::new(RecycleTokenInner {
        on_drop: Box::new(on_drop),
    })
}

pub(crate) struct RecycleTokenInner {
    on_drop: Box<dyn Fn() + Send + Sync>,
}

impl fmt::Debug for RecycleTokenInner {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("RecycleTokenInner(..)")
    }
}

impl Drop for RecycleTokenInner {
    fn drop(&mut self) {
        (self.on_drop)();
    }
}

pub type GpuMask = GpuImage;

#[derive(Debug, Clone, Default)]
pub struct MaskBundle {
    pub face: Option<GpuMask>,
    pub person: Option<GpuMask>,
    pub highlight: Option<GpuMask>,
    pub shadow: Option<GpuMask>,
    pub foreground_subject: Option<GpuMask>,
}

#[derive(Debug, Clone)]
pub struct PreparedMasks {
    pub face: Option<GpuMask>,
    pub person: Option<GpuMask>,
    pub highlight: Option<GpuMask>,
    pub shadow: Option<GpuMask>,
    pub foreground_subject: Option<GpuMask>,
    pub width: u32,
    pub height: u32,
}

#[derive(Debug, Clone)]
pub struct RenderOutputs {
    pub final_image: GpuImage,
    pub prepared_masks: PreparedMasks,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RenderParams {
    pub exposure_wb: ExposureWbParams,
    pub global_tone: GlobalToneParams,
    pub global_color: GlobalColorParams,
    pub sector_color: SectorColorParams,
    pub semantic_local: SemanticLocalParams,
    pub bloom: BloomParams,
    pub halation: HalationParams,
    pub vignette: VignetteParams,
    pub lens_character: LensCharacterParams,
    pub texture_surface: TextureSurfaceParams,
    pub output_finish: OutputFinishParams,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExposureWbParams {
    pub exposure_ev: f32,
    pub wb_r_gain: f32,
    pub wb_b_gain: f32,
}

impl Default for ExposureWbParams {
    fn default() -> Self {
        Self {
            exposure_ev: 0.0,
            wb_r_gain: 1.0,
            wb_b_gain: 1.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GlobalToneParams {
    pub contrast: f32,
    pub contrast_pivot: f32,
    pub blacks: f32,
    pub whites: f32,
    pub shadows: f32,
    pub highlights: f32,
    pub toe_strength: f32,
    pub shoulder_strength: f32,
    pub fade: f32,
    pub midtone_boost: f32,
    pub clarity_global: f32,
}

impl Default for GlobalToneParams {
    fn default() -> Self {
        Self {
            contrast: 0.0,
            contrast_pivot: 0.35,
            blacks: 0.0,
            whites: 0.0,
            shadows: 0.0,
            highlights: 0.0,
            toe_strength: 0.0,
            shoulder_strength: 0.0,
            fade: 0.0,
            midtone_boost: 0.0,
            clarity_global: 0.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GlobalColorParams {
    pub global_saturation: f32,
    pub global_vibrance: f32,
    pub global_hue_shift: f32,
    pub color_density: f32,
    pub warmth_bias: f32,
    pub green_magenta_bias: f32,
    pub shadow_hue: f32,
    pub shadow_sat: f32,
    pub midtone_hue: f32,
    pub midtone_sat: f32,
    pub highlight_hue: f32,
    pub highlight_sat: f32,
    pub split_balance: f32,
}

impl Default for GlobalColorParams {
    fn default() -> Self {
        Self {
            global_saturation: 1.0,
            global_vibrance: 0.0,
            global_hue_shift: 0.0,
            color_density: 0.0,
            warmth_bias: 0.0,
            green_magenta_bias: 0.0,
            shadow_hue: 220.0,
            shadow_sat: 0.0,
            midtone_hue: 35.0,
            midtone_sat: 0.0,
            highlight_hue: 45.0,
            highlight_sat: 0.0,
            split_balance: 0.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HueSectorAdjustment {
    pub hue_shift: f32,
    pub sat_scale: f32,
    pub luma_shift: f32,
}

impl Default for HueSectorAdjustment {
    fn default() -> Self {
        Self {
            hue_shift: 0.0,
            sat_scale: 1.0,
            luma_shift: 0.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SectorColorParams {
    pub red: HueSectorAdjustment,
    pub yellow: HueSectorAdjustment,
    pub green: HueSectorAdjustment,
    pub cyan: HueSectorAdjustment,
    pub blue: HueSectorAdjustment,
    pub magenta: HueSectorAdjustment,
    pub sector_width_scale: f32,
    pub sector_smoothness: f32,
}

impl Default for SectorColorParams {
    fn default() -> Self {
        Self {
            red: HueSectorAdjustment::default(),
            yellow: HueSectorAdjustment::default(),
            green: HueSectorAdjustment::default(),
            cyan: HueSectorAdjustment::default(),
            blue: HueSectorAdjustment::default(),
            magenta: HueSectorAdjustment::default(),
            sector_width_scale: 1.0,
            sector_smoothness: 0.5,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FaceLocalParams {
    pub exposure: f32,
    pub saturation: f32,
    pub hue_shift: f32,
    pub warmth: f32,
    pub soft_clarity: f32,
}

impl Default for FaceLocalParams {
    fn default() -> Self {
        Self {
            exposure: 0.0,
            saturation: 1.0,
            hue_shift: 0.0,
            warmth: 0.0,
            soft_clarity: 0.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PersonLocalParams {
    pub exposure: f32,
    pub saturation: f32,
    pub hue_shift: f32,
    pub clarity: f32,
}

impl Default for PersonLocalParams {
    fn default() -> Self {
        Self {
            exposure: 0.0,
            saturation: 1.0,
            hue_shift: 0.0,
            clarity: 0.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ForegroundSubjectLocalParams {
    pub hue_shift: f32,
    pub saturation: f32,
    pub luma: f32,
    pub exposure: f32,
    pub contrast: f32,
    pub pop: f32,
}

impl Default for ForegroundSubjectLocalParams {
    fn default() -> Self {
        Self {
            hue_shift: 0.0,
            saturation: 1.0,
            luma: 0.0,
            exposure: 0.0,
            contrast: 0.0,
            pop: 0.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TonalLocalParams {
    pub highlight_warmth: f32,
    pub shadow_tint: f32,
    pub shadow_desat: f32,
    pub highlight_mask_threshold: f32,
    pub highlight_mask_feather: f32,
    pub shadow_mask_threshold: f32,
    pub shadow_mask_feather: f32,
}

impl Default for TonalLocalParams {
    fn default() -> Self {
        Self {
            highlight_warmth: 0.0,
            shadow_tint: 0.0,
            shadow_desat: 0.0,
            highlight_mask_threshold: 0.72,
            highlight_mask_feather: 0.10,
            shadow_mask_threshold: 0.28,
            shadow_mask_feather: 0.10,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct SemanticLocalParams {
    pub face: FaceLocalParams,
    pub person: PersonLocalParams,
    pub foreground_subject: ForegroundSubjectLocalParams,
    pub tonal_local: TonalLocalParams,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BloomParams {
    pub threshold: f32,
    pub intensity: f32,
    pub radius: f32,
    pub softness: f32,
    pub veil_mix: f32,
}

impl Default for BloomParams {
    fn default() -> Self {
        Self {
            threshold: 0.9,
            intensity: 0.0,
            radius: 0.0,
            softness: 0.5,
            veil_mix: 0.5,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HalationParams {
    pub threshold: f32,
    pub intensity: f32,
    pub radius: f32,
    pub red_bias: f32,
    pub warmth: f32,
    pub core_balance: f32,
}

impl Default for HalationParams {
    fn default() -> Self {
        Self {
            threshold: 1.0,
            intensity: 0.0,
            radius: 0.0,
            red_bias: 0.7,
            warmth: 0.5,
            core_balance: 0.5,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VignetteParams {
    pub amount: f32,
    pub midpoint: f32,
    pub feather: f32,
    pub roundness: f32,
}

impl Default for VignetteParams {
    fn default() -> Self {
        Self {
            amount: 0.0,
            midpoint: 0.6,
            feather: 0.7,
            roundness: 0.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LensCharacterParams {
    pub soft_glow: f32,
    pub edge_softness: f32,
}

impl Default for LensCharacterParams {
    fn default() -> Self {
        Self {
            soft_glow: 0.0,
            edge_softness: 0.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TextureSurfaceParams {
    pub grain_luma_amount: f32,
    pub grain_chroma_amount: f32,
    pub grain_size: f32,
    pub grain_shadow_bias: f32,
    pub grain_highlight_suppress: f32,
    pub texture_boost: f32,
    pub noise_clean_bias: f32,
    pub detail_preserve: f32,
    pub microcontrast_balance: f32,
}

impl Default for TextureSurfaceParams {
    fn default() -> Self {
        Self {
            grain_luma_amount: 0.0,
            grain_chroma_amount: 0.0,
            grain_size: 0.7,
            grain_shadow_bias: 0.5,
            grain_highlight_suppress: 0.5,
            texture_boost: 0.0,
            noise_clean_bias: 0.5,
            detail_preserve: 0.5,
            microcontrast_balance: 0.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutputFinishParams {
    pub gamut_compress: f32,
    pub final_gamma_bias: f32,
    pub highlight_clip_softness: f32,
    pub highlight_rolloff_pivot: f32,
    pub shadow_floor: f32,
}

impl Default for OutputFinishParams {
    fn default() -> Self {
        Self {
            gamut_compress: 0.5,
            final_gamma_bias: 1.0,
            highlight_clip_softness: 0.5,
            highlight_rolloff_pivot: 1.0,
            shadow_floor: 0.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RenderGates {
    pub sector_color_gate: f32,
    pub face_gate: f32,
    pub person_gate: f32,
    pub foreground_subject_gate: f32,
    pub tonal_local_gate: f32,
    pub bloom_gate: f32,
    pub halation_gate: f32,
    pub vignette_gate: f32,
    pub lens_character_gate: f32,
    pub grain_gate: f32,
    pub texture_gate: f32,
}

impl Default for RenderGates {
    fn default() -> Self {
        Self {
            sector_color_gate: 1.0,
            face_gate: 1.0,
            person_gate: 1.0,
            foreground_subject_gate: 1.0,
            tonal_local_gate: 1.0,
            bloom_gate: 1.0,
            halation_gate: 1.0,
            vignette_gate: 1.0,
            lens_character_gate: 1.0,
            grain_gate: 1.0,
            texture_gate: 1.0,
        }
    }
}

impl RenderParams {
    pub fn from_normalized_slice(values: &[f32]) -> RenderResult<Self> {
        decode_render_params(values)
    }
}

impl RenderGates {
    pub fn from_slice(values: &[f32]) -> RenderResult<Self> {
        decode_render_gates(values)
    }
}

impl PreparedMasks {
    pub fn require_all(&self) -> RenderResult<(&GpuMask, &GpuMask, &GpuMask, &GpuMask, &GpuMask)> {
        let face = self.face.as_ref().ok_or(RenderError::MissingMask("face"))?;
        let person = self
            .person
            .as_ref()
            .ok_or(RenderError::MissingMask("person"))?;
        let highlight = self
            .highlight
            .as_ref()
            .ok_or(RenderError::MissingMask("highlight"))?;
        let shadow = self
            .shadow
            .as_ref()
            .ok_or(RenderError::MissingMask("shadow"))?;
        let foreground_subject = self
            .foreground_subject
            .as_ref()
            .ok_or(RenderError::MissingMask("foreground_subject"))?;
        Ok((face, person, highlight, shadow, foreground_subject))
    }
}
