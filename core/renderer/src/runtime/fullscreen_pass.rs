use crate::{
    api::{
        error::RenderResult,
        types::{GpuImage, PreparedMasks},
    },
    runtime::context::{PipelineLayoutKind, RenderContext},
};

pub fn render_basic_pass<U: bytemuck::Pod>(
    ctx: &RenderContext,
    encoder: &mut wgpu::CommandEncoder,
    input: &GpuImage,
    shader_source: &'static str,
    label: &str,
    uniform: &U,
) -> RenderResult<GpuImage> {
    render_basic_pass_to_target(
        ctx,
        encoder,
        input,
        input.width,
        input.height,
        ctx.working_format,
        shader_source,
        label,
        uniform,
    )
}

pub fn render_basic_pass_to_size<U: bytemuck::Pod>(
    ctx: &RenderContext,
    encoder: &mut wgpu::CommandEncoder,
    input: &GpuImage,
    output_width: u32,
    output_height: u32,
    shader_source: &'static str,
    label: &str,
    uniform: &U,
) -> RenderResult<GpuImage> {
    render_basic_pass_to_target(
        ctx,
        encoder,
        input,
        output_width,
        output_height,
        ctx.working_format,
        shader_source,
        label,
        uniform,
    )
}

pub fn render_basic_pass_to_target<U: bytemuck::Pod>(
    ctx: &RenderContext,
    encoder: &mut wgpu::CommandEncoder,
    input: &GpuImage,
    output_width: u32,
    output_height: u32,
    output_format: wgpu::TextureFormat,
    shader_source: &'static str,
    label: &str,
    uniform: &U,
) -> RenderResult<GpuImage> {
    let output = create_render_target(ctx, output_width, output_height, output_format, label);
    let pipeline = ctx.get_or_create_render_pipeline_with_common(
        PipelineLayoutKind::Basic,
        output.format,
        shader_source,
        label,
    );

    let uniform_bytes = bytemuck::bytes_of(uniform);
    let uniform_buffer = ctx.acquire_uniform_buffer(uniform_bytes.len(), label);
    ctx.queue
        .write_buffer(&uniform_buffer.buffer, 0, uniform_bytes);

    let bind_group = ctx.get_or_create_basic_bind_group(input, &uniform_buffer.buffer, label);

    {
        let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some(label),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &output.view,
                resolve_target: None,
                depth_slice: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            occlusion_query_set: None,
            timestamp_writes: None,
            multiview_mask: None,
        });

        render_pass.set_pipeline(&pipeline);
        render_pass.set_bind_group(0, &bind_group, &[]);
        render_pass.draw(0..3, 0..1);
    }

    Ok(output)
}

pub fn render_dual_texture_pass<U: bytemuck::Pod>(
    ctx: &RenderContext,
    encoder: &mut wgpu::CommandEncoder,
    base: &GpuImage,
    effect: &GpuImage,
    shader_source: &'static str,
    label: &str,
    uniform: &U,
) -> RenderResult<GpuImage> {
    render_dual_texture_pass_to_target(
        ctx,
        encoder,
        base,
        effect,
        base.width,
        base.height,
        ctx.working_format,
        shader_source,
        label,
        uniform,
    )
}

pub fn render_dual_texture_pass_to_target<U: bytemuck::Pod>(
    ctx: &RenderContext,
    encoder: &mut wgpu::CommandEncoder,
    base: &GpuImage,
    effect: &GpuImage,
    output_width: u32,
    output_height: u32,
    output_format: wgpu::TextureFormat,
    shader_source: &'static str,
    label: &str,
    uniform: &U,
) -> RenderResult<GpuImage> {
    let output = create_render_target(ctx, output_width, output_height, output_format, label);
    let pipeline = ctx.get_or_create_render_pipeline_with_common(
        PipelineLayoutKind::DualTexture,
        output.format,
        shader_source,
        label,
    );

    let uniform_bytes = bytemuck::bytes_of(uniform);
    let uniform_buffer = ctx.acquire_uniform_buffer(uniform_bytes.len(), label);
    ctx.queue
        .write_buffer(&uniform_buffer.buffer, 0, uniform_bytes);

    let bind_group =
        ctx.get_or_create_dual_texture_bind_group(base, effect, &uniform_buffer.buffer, label);

    {
        let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some(label),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &output.view,
                resolve_target: None,
                depth_slice: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            occlusion_query_set: None,
            timestamp_writes: None,
            multiview_mask: None,
        });

        render_pass.set_pipeline(&pipeline);
        render_pass.set_bind_group(0, &bind_group, &[]);
        render_pass.draw(0..3, 0..1);
    }

    Ok(output)
}

pub fn render_masked_pass<U: bytemuck::Pod>(
    ctx: &RenderContext,
    encoder: &mut wgpu::CommandEncoder,
    input: &GpuImage,
    masks: &PreparedMasks,
    shader_source: &'static str,
    label: &str,
    uniform: &U,
) -> RenderResult<GpuImage> {
    let output = create_render_target_like(ctx, input, label);
    let pipeline = ctx.get_or_create_render_pipeline_with_common(
        PipelineLayoutKind::Masked,
        output.format,
        shader_source,
        label,
    );

    let uniform_bytes = bytemuck::bytes_of(uniform);
    let uniform_buffer = ctx.acquire_uniform_buffer(uniform_bytes.len(), label);
    ctx.queue
        .write_buffer(&uniform_buffer.buffer, 0, uniform_bytes);

    let (face, person, highlight, shadow, foreground_subject) = masks.require_all()?;

    let bind_group = ctx.get_or_create_masked_bind_group(
        input,
        face,
        person,
        highlight,
        shadow,
        foreground_subject,
        &uniform_buffer.buffer,
        label,
    );

    {
        let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some(label),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &output.view,
                resolve_target: None,
                depth_slice: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                    store: wgpu::StoreOp::Store,
                },
            })],
            depth_stencil_attachment: None,
            occlusion_query_set: None,
            timestamp_writes: None,
            multiview_mask: None,
        });

        render_pass.set_pipeline(&pipeline);
        render_pass.set_bind_group(0, &bind_group, &[]);
        render_pass.draw(0..3, 0..1);
    }

    Ok(output)
}

fn create_render_target_like(ctx: &RenderContext, input: &GpuImage, label: &str) -> GpuImage {
    create_render_target(ctx, input.width, input.height, ctx.working_format, label)
}

fn create_render_target(
    ctx: &RenderContext,
    width: u32,
    height: u32,
    format: wgpu::TextureFormat,
    label: &str,
) -> GpuImage {
    ctx.acquire_scratch_image(width, height, format, label)
}
