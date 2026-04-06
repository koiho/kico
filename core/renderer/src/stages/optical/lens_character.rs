use crate::{
    api::{
        error::RenderResult,
        types::{GpuImage, LensCharacterParams},
    },
    effects::effect_pyramid::{
        blur_separable, composite_effect, downsample_prefilter, extract_highlights,
    },
    pipeline::{shader_sources::VIGNETTE_LENS_WGSL, uniforms::VignetteLensUniform},
    runtime::{context::RenderContext, fullscreen_pass::render_basic_pass},
};

#[derive(Debug, Default)]
pub struct LensCharacterStage;

impl LensCharacterStage {
    pub fn apply(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        input: &GpuImage,
        params: &LensCharacterParams,
        gate: f32,
    ) -> RenderResult<GpuImage> {
        if gate <= 0.0001 || (params.soft_glow <= 0.0001 && params.edge_softness <= 0.0001) {
            return Ok(input.clone());
        }

        let with_glow = self.apply_high_quality_soft_glow(ctx, encoder, input, params, gate)?;
        let texel_scale = input.width.max(1) as f32 / 256.0_f32;
        let uniform = VignetteLensUniform {
            vignette: [0.0, 0.0, 0.0, 0.0],
            lens: [0.0, params.edge_softness, 0.0, gate],
            scale: [texel_scale, 0.0, 0.0, 0.0],
        };
        render_basic_pass(
            ctx,
            encoder,
            &with_glow,
            VIGNETTE_LENS_WGSL,
            "pass_6_lens_character_edge_softness",
            &uniform,
        )
    }

    fn apply_high_quality_soft_glow(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        input: &GpuImage,
        params: &LensCharacterParams,
        gate: f32,
    ) -> RenderResult<GpuImage> {
        if params.soft_glow <= 0.0001 {
            return Ok(input.clone());
        }

        let highlight_extract = extract_highlights(
            ctx,
            encoder,
            input,
            input.width,
            input.height,
            glow_threshold(params.soft_glow),
            glow_knee(params.soft_glow),
            "pass_6_lens_character_extract",
        )?;

        let mid_glow = blur_separable(
            ctx,
            encoder,
            &highlight_extract,
            glow_mid_stride(params.soft_glow),
            "pass_6_lens_character_blur_mid",
        )?;

        let wide_prefilter = downsample_prefilter(
            ctx,
            encoder,
            &highlight_extract,
            downsample_dimension(input.width, 2),
            downsample_dimension(input.height, 2),
            "pass_6_lens_character_downsample_wide",
        )?;

        let wide_glow = blur_separable(
            ctx,
            encoder,
            &wide_prefilter,
            glow_wide_stride(params.soft_glow),
            "pass_6_lens_character_blur_wide",
        )?;

        let far_prefilter = downsample_prefilter(
            ctx,
            encoder,
            &wide_prefilter,
            downsample_dimension(input.width, 4),
            downsample_dimension(input.height, 4),
            "pass_6_lens_character_downsample_far",
        )?;

        let far_glow = blur_separable(
            ctx,
            encoder,
            &far_prefilter,
            glow_far_stride(params.soft_glow),
            "pass_6_lens_character_blur_far",
        )?;

        let with_far = composite_effect(
            ctx,
            encoder,
            input,
            &far_glow,
            params.soft_glow * 0.12,
            gate,
            [1.0, 0.965, 0.94],
            "pass_6_lens_character_composite_far",
        )?;

        let with_wide = composite_effect(
            ctx,
            encoder,
            &with_far,
            &wide_glow,
            params.soft_glow * 0.16,
            gate,
            [1.0, 0.97, 0.94],
            "pass_6_lens_character_composite_wide",
        )?;

        composite_effect(
            ctx,
            encoder,
            &with_wide,
            &mid_glow,
            params.soft_glow * 0.22,
            gate,
            [1.0, 0.99, 0.96],
            "pass_6_lens_character_composite_mid",
        )
    }
}

fn downsample_dimension(size: u32, divisor: u32) -> u32 {
    (size / divisor).max(1)
}

fn glow_threshold(soft_glow: f32) -> f32 {
    (0.72 - soft_glow.max(0.0) * 0.18).clamp(0.35, 0.72)
}

fn glow_knee(soft_glow: f32) -> f32 {
    0.10 + soft_glow.max(0.0) * 0.12
}

fn glow_mid_stride(soft_glow: f32) -> f32 {
    1.0 + soft_glow.max(0.0) * 4.0
}

fn glow_wide_stride(soft_glow: f32) -> f32 {
    1.9 + soft_glow.max(0.0) * 5.5
}

fn glow_far_stride(soft_glow: f32) -> f32 {
    3.1 + soft_glow.max(0.0) * 7.0
}
