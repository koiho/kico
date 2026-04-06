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
        base_max_dimension: Option<u32>,
    ) -> RenderResult<GpuImage> {
        if gate <= 0.0001 || params.intensity <= 0.0001 || params.radius <= 0.0001 {
            return Ok(input.clone());
        }

        let (mid_share, wide_share, far_share, veil_share) = bloom_layer_shares(params.veil_mix);
        let (base_width, base_height) =
            working_dimensions(input.width, input.height, base_max_dimension);

        let mid_extract = extract_highlights(
            ctx,
            encoder,
            input,
            base_width,
            base_height,
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
            downsample_dimension(mid_extract.width, 2),
            downsample_dimension(mid_extract.height, 2),
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
            downsample_dimension(wide_extract.width, 2),
            downsample_dimension(wide_extract.height, 2),
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
            downsample_dimension(far_extract.width, 2),
            downsample_dimension(far_extract.height, 2),
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

fn working_dimensions(width: u32, height: u32, max_dimension: Option<u32>) -> (u32, u32) {
    let Some(max_dimension) = max_dimension.filter(|value| *value > 0) else {
        return (width.max(1), height.max(1));
    };

    let longest_edge = width.max(height);
    if longest_edge <= max_dimension || longest_edge == 0 {
        return (width.max(1), height.max(1));
    }

    let scale = max_dimension as f32 / longest_edge as f32;
    let working_width = ((width as f32) * scale).round().max(1.0) as u32;
    let working_height = ((height as f32) * scale).round().max(1.0) as u32;
    (working_width, working_height)
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
