use crate::{
    api::{
        error::RenderResult,
        types::{GpuImage, TextureSurfaceParams},
    },
    pipeline::{shader_sources::TEXTURE_FINISH_WGSL, uniforms::TextureFinishUniform},
    runtime::{context::RenderContext, fullscreen_pass::render_basic_pass},
};

#[derive(Debug, Default)]
pub struct TextureGrainStage;

impl TextureGrainStage {
    pub fn apply(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        input: &GpuImage,
        params: &TextureSurfaceParams,
        grain_gate: f32,
        texture_gate: f32,
    ) -> RenderResult<GpuImage> {
        let texel_scale = input.width.max(1) as f32 / 256.0_f32;
        let uniform = TextureFinishUniform {
            grain_a: [
                params.grain_luma_amount,
                params.grain_chroma_amount,
                params.grain_size,
                grain_gate,
            ],
            grain_b: [
                params.grain_shadow_bias,
                params.grain_highlight_suppress,
                params.microcontrast_balance,
                0.0,
            ],
            texture: [
                params.texture_boost,
                params.noise_clean_bias,
                params.detail_preserve,
                texture_gate,
            ],
            finish: [0.0, 1.0, 0.0, 0.0],
            scale: [texel_scale, 0.0, 0.0, 0.0],
        };
        render_basic_pass(
            ctx,
            encoder,
            input,
            TEXTURE_FINISH_WGSL,
            "pass_8_texture_grain",
            &uniform,
        )
    }
}
