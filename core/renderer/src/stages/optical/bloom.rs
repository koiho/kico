use crate::{
    api::{
        error::RenderResult,
        types::{BloomParams, GpuImage},
    },
    effects::effect_pyramid::{
        blur_separable, composite_effect, downsample_prefilter, extract_highlights,
    },
    runtime::context::RenderContext,
};

#[derive(Debug, Default)]
pub struct BloomStage;

impl BloomStage {
    pub fn apply(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        input: &GpuImage,
        params: &BloomParams,
        gate: f32,
    ) -> RenderResult<GpuImage> {
        if gate <= 0.0001 || params.intensity <= 0.0001 || params.radius <= 0.0001 {
            return Ok(input.clone());
        }

        let (mid_share, wide_share, far_share, veil_share) = bloom_layer_shares(params.veil_mix);

        let mid_extract = extract_highlights(
            ctx,
            encoder,
            input,
            input.width,
            input.height,
            params.threshold,
            0.05 + params.softness.max(0.0) * 0.14,
            "pass_4_bloom_extract_mid",
        )?;

        let mid_vertical = blur_separable(
            ctx,
            encoder,
            &mid_extract,
            bloom_stride(params.radius, params.softness),
            "pass_4_bloom_blur_mid",
        )?;

        let wide_extract = downsample_prefilter(
            ctx,
            encoder,
            &mid_extract,
            downsample_dimension(input.width, 2),
            downsample_dimension(input.height, 2),
            "pass_4_bloom_downsample_wide",
        )?;

        let wide_vertical = blur_separable(
            ctx,
            encoder,
            &wide_extract,
            bloom_stride(params.radius, params.softness) * 1.8,
            "pass_4_bloom_blur_wide",
        )?;

        let far_extract = downsample_prefilter(
            ctx,
            encoder,
            &wide_extract,
            downsample_dimension(input.width, 4),
            downsample_dimension(input.height, 4),
            "pass_4_bloom_downsample_far",
        )?;

        let far_vertical = blur_separable(
            ctx,
            encoder,
            &far_extract,
            bloom_stride(params.radius, params.softness) * 2.6,
            "pass_4_bloom_blur_far",
        )?;

        let veil_extract = downsample_prefilter(
            ctx,
            encoder,
            &far_extract,
            downsample_dimension(input.width, 8),
            downsample_dimension(input.height, 8),
            "pass_4_bloom_downsample_veil",
        )?;

        let veil_vertical = blur_separable(
            ctx,
            encoder,
            &veil_extract,
            bloom_stride(params.radius, params.softness) * 3.6,
            "pass_4_bloom_blur_veil",
        )?;

        let with_veil = composite_effect(
            ctx,
            encoder,
            input,
            &veil_vertical,
            params.intensity * veil_share,
            gate,
            [1.0, 1.0, 1.0],
            "pass_4_bloom_composite_veil",
        )?;

        let with_far = composite_effect(
            ctx,
            encoder,
            &with_veil,
            &far_vertical,
            params.intensity * far_share,
            gate,
            [1.0, 1.0, 1.0],
            "pass_4_bloom_composite_far",
        )?;

        let with_wide = composite_effect(
            ctx,
            encoder,
            &with_far,
            &wide_vertical,
            params.intensity * wide_share,
            gate,
            [1.0, 1.0, 1.0],
            "pass_4_bloom_composite_wide",
        )?;

        composite_effect(
            ctx,
            encoder,
            &with_wide,
            &mid_vertical,
            params.intensity * mid_share,
            gate,
            [1.0, 1.0, 1.0],
            "pass_4_bloom_composite_mid",
        )
    }
}

fn downsample_dimension(size: u32, divisor: u32) -> u32 {
    (size / divisor).max(1)
}

fn bloom_stride(radius: f32, softness: f32) -> f32 {
    (0.85 + radius.max(0.0) * 4.8) * (1.0 + softness.max(0.0) * 0.65)
}

fn bloom_layer_shares(veil_mix: f32) -> (f32, f32, f32, f32) {
    let bias = (veil_mix.clamp(0.0, 1.0) - 0.5) * 2.0;
    let mut mid = (0.47 - bias * 0.07).clamp(0.30, 0.56);
    let mut wide = (0.28 - bias * 0.03).clamp(0.22, 0.34);
    let mut far = (0.15 + bias * 0.02).clamp(0.10, 0.20);
    let mut veil = (0.10 + bias * 0.08).clamp(0.02, 0.22);
    let total = mid + wide + far + veil;
    mid /= total;
    wide /= total;
    far /= total;
    veil /= total;
    (mid, wide, far, veil)
}
