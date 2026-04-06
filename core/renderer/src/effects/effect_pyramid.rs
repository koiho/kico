use bytemuck::{Pod, Zeroable};

use crate::{
    api::{error::RenderResult, types::GpuImage},
    pipeline::shader_sources::{
        ADDITIVE_EFFECT_WGSL, COMPOSITE_EFFECT_WGSL, DOWNSAMPLE_PREFILTER_WGSL, EFFECT_DELTA_WGSL,
        EXTRACT_HIGHLIGHTS_WGSL, SEPARABLE_BLUR_WGSL,
    },
    runtime::{
        context::RenderContext,
        fullscreen_pass::{render_basic_pass, render_basic_pass_to_size, render_dual_texture_pass},
    },
};

#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
struct ExtractHighlightsUniform {
    params_a: [f32; 4],
    params_b: [f32; 4],
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
struct SeparableBlurUniform {
    direction_radius: [f32; 4],
    weights_a: [f32; 4],
    weights_b: [f32; 4],
    weights_c: [f32; 4],
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
struct CompositeEffectUniform {
    intensity_gate: [f32; 4],
    tint: [f32; 4],
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
struct DownsamplePrefilterUniform {
    params: [f32; 4],
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
struct DualTextureUtilityUniform {
    params: [f32; 4],
}

pub fn extract_highlights(
    ctx: &RenderContext,
    encoder: &mut wgpu::CommandEncoder,
    input: &GpuImage,
    output_width: u32,
    output_height: u32,
    threshold: f32,
    knee: f32,
    label: &str,
) -> RenderResult<GpuImage> {
    render_basic_pass_to_size(
        ctx,
        encoder,
        input,
        output_width,
        output_height,
        EXTRACT_HIGHLIGHTS_WGSL,
        label,
        &ExtractHighlightsUniform {
            params_a: [threshold, knee, 1.0, 0.0],
            params_b: [0.0; 4],
        },
    )
}

pub fn downsample_prefilter(
    ctx: &RenderContext,
    encoder: &mut wgpu::CommandEncoder,
    input: &GpuImage,
    output_width: u32,
    output_height: u32,
    label: &str,
) -> RenderResult<GpuImage> {
    render_basic_pass_to_size(
        ctx,
        encoder,
        input,
        output_width,
        output_height,
        DOWNSAMPLE_PREFILTER_WGSL,
        label,
        &DownsamplePrefilterUniform { params: [0.0; 4] },
    )
}

pub fn blur_separable(
    ctx: &RenderContext,
    encoder: &mut wgpu::CommandEncoder,
    input: &GpuImage,
    stride: f32,
    label_prefix: &str,
) -> RenderResult<GpuImage> {
    let horizontal = render_basic_pass(
        ctx,
        encoder,
        input,
        SEPARABLE_BLUR_WGSL,
        &format!("{label_prefix}_h"),
        &SeparableBlurUniform {
            direction_radius: [1.0, 0.0, stride, 0.0],
            weights_a: gaussian_weights_a(),
            weights_b: gaussian_weights_b(),
            weights_c: gaussian_weights_c(),
        },
    )?;

    render_basic_pass(
        ctx,
        encoder,
        &horizontal,
        SEPARABLE_BLUR_WGSL,
        &format!("{label_prefix}_v"),
        &SeparableBlurUniform {
            direction_radius: [0.0, 1.0, stride, 0.0],
            weights_a: gaussian_weights_a(),
            weights_b: gaussian_weights_b(),
            weights_c: gaussian_weights_c(),
        },
    )
}

pub fn composite_effect(
    ctx: &RenderContext,
    encoder: &mut wgpu::CommandEncoder,
    base: &GpuImage,
    effect: &GpuImage,
    intensity: f32,
    gate: f32,
    tint: [f32; 3],
    label: &str,
) -> RenderResult<GpuImage> {
    render_dual_texture_pass(
        ctx,
        encoder,
        base,
        effect,
        COMPOSITE_EFFECT_WGSL,
        label,
        &CompositeEffectUniform {
            intensity_gate: [intensity, gate, 0.0, 0.0],
            tint: [tint[0], tint[1], tint[2], 0.0],
        },
    )
}

pub fn extract_effect_delta(
    ctx: &RenderContext,
    encoder: &mut wgpu::CommandEncoder,
    base: &GpuImage,
    processed: &GpuImage,
    label: &str,
) -> RenderResult<GpuImage> {
    render_dual_texture_pass(
        ctx,
        encoder,
        base,
        processed,
        EFFECT_DELTA_WGSL,
        label,
        &DualTextureUtilityUniform { params: [0.0; 4] },
    )
}

pub fn additive_composite_effect(
    ctx: &RenderContext,
    encoder: &mut wgpu::CommandEncoder,
    base: &GpuImage,
    effect_delta: &GpuImage,
    label: &str,
) -> RenderResult<GpuImage> {
    render_dual_texture_pass(
        ctx,
        encoder,
        base,
        effect_delta,
        ADDITIVE_EFFECT_WGSL,
        label,
        &DualTextureUtilityUniform { params: [0.0; 4] },
    )
}

fn gaussian_weights_a() -> [f32; 4] {
    [0.196482, 0.176033, 0.121003, 0.064759]
}

fn gaussian_weights_b() -> [f32; 4] {
    [0.061010795, 0.046053364, 0.032656725, 0.021_754_07]
}

fn gaussian_weights_c() -> [f32; 4] {
    [0.013613349, 0.008002875, 0.004419607, 0.0]
}
