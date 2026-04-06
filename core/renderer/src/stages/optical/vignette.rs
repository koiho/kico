use crate::{
    api::{
        error::RenderResult,
        types::{GpuImage, VignetteParams},
    },
    pipeline::{shader_sources::VIGNETTE_LENS_WGSL, uniforms::VignetteLensUniform},
    runtime::{context::RenderContext, fullscreen_pass::render_basic_pass},
};

#[derive(Debug, Default)]
pub struct VignetteStage;

impl VignetteStage {
    pub fn apply(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        input: &GpuImage,
        params: &VignetteParams,
        gate: f32,
    ) -> RenderResult<GpuImage> {
        let texel_scale = input.width.max(1) as f32 / 256.0_f32;
        let uniform = VignetteLensUniform {
            vignette: [
                params.amount,
                params.midpoint,
                params.feather,
                params.roundness,
            ],
            lens: [0.0, 0.0, gate, 0.0],
            scale: [texel_scale, 0.0, 0.0, 0.0],
        };
        render_basic_pass(
            ctx,
            encoder,
            input,
            VIGNETTE_LENS_WGSL,
            "pass_7_vignette",
            &uniform,
        )
    }
}
