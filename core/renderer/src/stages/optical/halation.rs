use crate::{
    api::{
        error::RenderResult,
        types::{GpuImage, HalationParams},
    },
    effects::effect_pyramid::{
        blur_separable, composite_effect, downsample_prefilter, extract_highlights,
    },
    pipeline::shader_sources::HALATION_SOURCE_WGSL,
    runtime::{context::RenderContext, fullscreen_pass::render_basic_pass},
};

use bytemuck::{Pod, Zeroable};

#[derive(Debug, Default)]
pub struct HalationStage;

impl HalationStage {
    pub fn apply(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        input: &GpuImage,
        params: &HalationParams,
        gate: f32,
    ) -> RenderResult<GpuImage> {
        if gate <= 0.0001 || params.intensity <= 0.0001 || params.radius <= 0.0001 {
            return Ok(input.clone());
        }

        let (core_share, wide_share, far_share, veil_share) =
            halation_layer_shares(params.core_balance);

        let core_extract = extract_highlights(
            ctx,
            encoder,
            input,
            downsample_dimension(input.width, 2),
            downsample_dimension(input.height, 2),
            params.threshold,
            0.05 + params.warmth.max(0.0) * 0.05,
            "pass_5_halation_extract_core",
        )?;

        let core_source = self.shape_halation_source(ctx, encoder, &core_extract, params)?;

        let core_vertical = blur_separable(
            ctx,
            encoder,
            &core_source,
            halation_stride(params.radius),
            "pass_5_halation_blur_core",
        )?;

        let wide_extract = downsample_prefilter(
            ctx,
            encoder,
            &core_source,
            downsample_dimension(input.width, 4),
            downsample_dimension(input.height, 4),
            "pass_5_halation_downsample_wide",
        )?;

        let wide_vertical = blur_separable(
            ctx,
            encoder,
            &wide_extract,
            halation_stride(params.radius) * 1.8,
            "pass_5_halation_blur_wide",
        )?;

        let far_extract = downsample_prefilter(
            ctx,
            encoder,
            &wide_extract,
            downsample_dimension(input.width, 8),
            downsample_dimension(input.height, 8),
            "pass_5_halation_downsample_far",
        )?;

        let far_vertical = blur_separable(
            ctx,
            encoder,
            &far_extract,
            halation_stride(params.radius) * 2.5,
            "pass_5_halation_blur_far",
        )?;

        let veil_extract = downsample_prefilter(
            ctx,
            encoder,
            &far_extract,
            downsample_dimension(input.width, 16),
            downsample_dimension(input.height, 16),
            "pass_5_halation_downsample_veil",
        )?;

        let veil_vertical = blur_separable(
            ctx,
            encoder,
            &veil_extract,
            halation_stride(params.radius) * 3.2,
            "pass_5_halation_blur_veil",
        )?;

        let tint = [
            0.92 + params.red_bias.max(0.0) * 0.22,
            0.22 + params.warmth.max(0.0) * 0.18,
            0.04,
        ];

        let with_veil = composite_effect(
            ctx,
            encoder,
            input,
            &veil_vertical,
            params.intensity * veil_share,
            gate,
            tint,
            "pass_5_halation_composite_veil",
        )?;

        let with_far = composite_effect(
            ctx,
            encoder,
            &with_veil,
            &far_vertical,
            params.intensity * far_share,
            gate,
            tint,
            "pass_5_halation_composite_far",
        )?;

        let with_wide = composite_effect(
            ctx,
            encoder,
            &with_far,
            &wide_vertical,
            params.intensity * wide_share,
            gate,
            tint,
            "pass_5_halation_composite_wide",
        )?;

        composite_effect(
            ctx,
            encoder,
            &with_wide,
            &core_vertical,
            params.intensity * core_share,
            gate,
            tint,
            "pass_5_halation_composite_core",
        )
    }

    fn shape_halation_source(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        input: &GpuImage,
        params: &HalationParams,
    ) -> RenderResult<GpuImage> {
        let uniform = HalationSourceUniform {
            params: [params.red_bias, params.warmth, 0.0, 0.0],
        };
        render_basic_pass(
            ctx,
            encoder,
            input,
            HALATION_SOURCE_WGSL,
            "pass_5_halation_shape_source",
            &uniform,
        )
    }
}

fn downsample_dimension(size: u32, divisor: u32) -> u32 {
    (size / divisor).max(1)
}

fn halation_stride(radius: f32) -> f32 {
    1.1 + radius.max(0.0) * 7.5
}

fn halation_layer_shares(core_balance: f32) -> (f32, f32, f32, f32) {
    let bias = (core_balance.clamp(0.0, 1.0) - 0.5) * 2.0;
    let mut core = (0.28 + bias * 0.08).clamp(0.20, 0.36);
    let mut wide = (0.17 - bias * 0.01).clamp(0.14, 0.19);
    let mut far = (0.10 - bias * 0.03).clamp(0.07, 0.13);
    let mut veil = (0.07 - bias * 0.04).clamp(0.03, 0.11);
    let total = core + wide + far + veil;
    let target_total = 0.62;
    let scale = target_total / total.max(1e-6);
    core *= scale;
    wide *= scale;
    far *= scale;
    veil *= scale;
    (core, wide, far, veil)
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
struct HalationSourceUniform {
    params: [f32; 4],
}
