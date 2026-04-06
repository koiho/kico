use crate::{
    api::{
        error::RenderResult,
        types::{GpuImage, OutputFinishParams},
    },
    pipeline::{shader_sources::TEXTURE_FINISH_WGSL, uniforms::TextureFinishUniform},
    runtime::{context::RenderContext, fullscreen_pass::render_basic_pass},
};

#[derive(Debug, Default)]
pub struct OutputFinishStage;

impl OutputFinishStage {
    pub fn apply(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        input: &GpuImage,
        params: &OutputFinishParams,
    ) -> RenderResult<GpuImage> {
        let texel_scale = input.width.max(1) as f32 / 256.0_f32;
        let uniform = TextureFinishUniform {
            grain_a: [0.0, 0.0, 0.0, 0.0],
            grain_b: [0.0, 0.0, 0.0, params.shadow_floor],
            texture: [0.0, 0.0, 1.0, 0.0],
            finish: [
                params.gamut_compress,
                params.final_gamma_bias,
                params.highlight_clip_softness,
                params.highlight_rolloff_pivot,
            ],
            scale: [texel_scale, 0.0, 0.0, 0.0],
        };
        render_basic_pass(
            ctx,
            encoder,
            input,
            TEXTURE_FINISH_WGSL,
            "pass_9_output_finish",
            &uniform,
        )
    }
}
