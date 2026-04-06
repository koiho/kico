use crate::{
    api::{
        error::RenderResult,
        types::{GpuImage, MaskBundle, RenderGates, RenderOutputs, RenderParams},
    },
    effects::effect_pyramid::{additive_composite_effect, extract_effect_delta},
    pipeline::{
        shader_sources::{EXPOSURE_WB_TONE_WGSL, GLOBAL_COLOR_SECTOR_WGSL, PASSTHROUGH_COPY_WGSL},
        uniforms::RenderPassUniformPack,
    },
    runtime::{
        context::RenderContext,
        fullscreen_pass::{render_basic_pass, render_basic_pass_to_target},
    },
    stages::{
        input::mask_prep::MaskPrepStage,
        local::semantic_local::SemanticLocalStage,
        optical::{
            bloom::BloomStage, halation::HalationStage, lens_character::LensCharacterStage,
            vignette::VignetteStage,
        },
        output::{output_finish::OutputFinishStage, texture_grain::TextureGrainStage},
    },
};
use bytemuck::{Pod, Zeroable};

#[derive(Debug, Default)]
pub struct Renderer {
    pub mask_prep: MaskPrepStage,
    pub semantic_local: SemanticLocalStage,
    pub bloom: BloomStage,
    pub halation: HalationStage,
    pub vignette: VignetteStage,
    pub lens_character: LensCharacterStage,
    pub texture_grain: TextureGrainStage,
    pub output_finish: OutputFinishStage,
}

impl Renderer {
    pub fn build_uniform_pack(
        &self,
        params: &RenderParams,
        gates: &RenderGates,
        image_width: u32,
    ) -> RenderPassUniformPack {
        RenderPassUniformPack::from_params_with_size(params, gates, image_width)
    }

    pub fn render(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        neutral: &GpuImage,
        params: &RenderParams,
        gates: &RenderGates,
        masks: &MaskBundle,
    ) -> RenderResult<RenderOutputs> {
        ctx.validate_image(neutral)?;

        let prepared_masks = self.mask_prep.prepare(
            ctx,
            encoder,
            neutral,
            masks,
            &params.semantic_local.tonal_local,
        )?;

        let uniforms = self.build_uniform_pack(params, gates, neutral.width);
        let mut img = render_basic_pass(
            ctx,
            encoder,
            neutral,
            EXPOSURE_WB_TONE_WGSL,
            "pass_1_exposure_wb_tone",
            &uniforms.exposure_wb_tone,
        )?;
        img = render_basic_pass(
            ctx,
            encoder,
            &img,
            GLOBAL_COLOR_SECTOR_WGSL,
            "pass_2_global_color_sector",
            &uniforms.global_color_sector,
        )?;
        img = self.semantic_local.apply(
            ctx,
            encoder,
            &img,
            &params.semantic_local,
            gates,
            &prepared_masks,
        )?;

        let optics_base = img;
        let bloom_branch =
            self.bloom
                .apply(ctx, encoder, &optics_base, &params.bloom, gates.bloom_gate)?;
        let halation_branch = self.halation.apply(
            ctx,
            encoder,
            &optics_base,
            &params.halation,
            gates.halation_gate,
        )?;
        let bloom_delta = extract_effect_delta(
            ctx,
            encoder,
            &optics_base,
            &bloom_branch,
            "pass_4_bloom_delta",
        )?;
        let halation_delta = extract_effect_delta(
            ctx,
            encoder,
            &optics_base,
            &halation_branch,
            "pass_5_halation_delta",
        )?;
        let mut img = additive_composite_effect(
            ctx,
            encoder,
            &optics_base,
            &bloom_delta,
            "pass_4_bloom_additive_combine",
        )?;
        img = additive_composite_effect(
            ctx,
            encoder,
            &img,
            &halation_delta,
            "pass_5_halation_additive_combine",
        )?;
        img = self.lens_character.apply(
            ctx,
            encoder,
            &img,
            &params.lens_character,
            gates.lens_character_gate,
        )?;
        img = self
            .vignette
            .apply(ctx, encoder, &img, &params.vignette, gates.vignette_gate)?;
        img = self.texture_grain.apply(
            ctx,
            encoder,
            &img,
            &params.texture_surface,
            gates.grain_gate,
            gates.texture_gate,
        )?;
        img = self
            .output_finish
            .apply(ctx, encoder, &img, &params.output_finish)?;
        if img.format != neutral.format {
            img = render_basic_pass_to_target(
                ctx,
                encoder,
                &img,
                neutral.width,
                neutral.height,
                neutral.format,
                PASSTHROUGH_COPY_WGSL,
                "pass_10_output_convert",
                &CopyUniform { params: [0.0; 4] },
            )?;
        }

        Ok(RenderOutputs {
            final_image: img,
            prepared_masks,
        })
    }

    pub fn render_from_model_outputs(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        neutral: &GpuImage,
        normalized_params: &[f32],
        gate_values: &[f32],
        masks: &MaskBundle,
    ) -> RenderResult<RenderOutputs> {
        let params = RenderParams::from_normalized_slice(normalized_params)?;
        let gates = RenderGates::from_slice(gate_values)?;
        self.render(ctx, encoder, neutral, &params, &gates, masks)
    }

    pub fn render_and_submit(
        &self,
        ctx: &RenderContext,
        neutral: &GpuImage,
        params: &RenderParams,
        gates: &RenderGates,
        masks: &MaskBundle,
    ) -> RenderResult<RenderOutputs> {
        let mut encoder = ctx.create_encoder("renderer_render_and_submit");
        let outputs = self.render(ctx, &mut encoder, neutral, params, gates, masks)?;
        ctx.submit_and_wait(encoder)?;
        Ok(outputs)
    }

    pub fn render_from_model_outputs_and_submit(
        &self,
        ctx: &RenderContext,
        neutral: &GpuImage,
        normalized_params: &[f32],
        gate_values: &[f32],
        masks: &MaskBundle,
    ) -> RenderResult<RenderOutputs> {
        let params = RenderParams::from_normalized_slice(normalized_params)?;
        let gates = RenderGates::from_slice(gate_values)?;
        self.render_and_submit(ctx, neutral, &params, &gates, masks)
    }
}

#[repr(C)]
#[derive(Debug, Clone, Copy, Pod, Zeroable)]
struct CopyUniform {
    params: [f32; 4],
}

#[cfg(test)]
mod tests {
    use std::{
        future::Future,
        sync::Arc,
        task::{Context, Poll, Waker},
        thread,
        time::Duration,
    };

    use super::Renderer;
    use crate::{
        api::types::{
            BloomParams, GpuImage, HalationParams, MaskBundle, RenderGates, RenderParams,
        },
        runtime::context::RenderContext,
    };

    #[test]
    fn renderer_smoke_runs_full_gpu_pipeline_when_device_is_available() {
        let _guard = crate::test_support::gpu_test_guard();
        let Some(ctx) = create_test_context() else {
            return;
        };

        let renderer = Renderer::default();
        let neutral = create_test_image(
            &ctx,
            4,
            4,
            wgpu::TextureFormat::Rgba8Unorm,
            "neutral",
            [96, 104, 112, 255],
        );

        let masks = MaskBundle {
            face: Some(create_test_image(
                &ctx,
                4,
                4,
                wgpu::TextureFormat::Rgba8Unorm,
                "face_mask",
                [255, 255, 255, 255],
            )),
            person: Some(create_test_image(
                &ctx,
                4,
                4,
                wgpu::TextureFormat::Rgba8Unorm,
                "person_mask",
                [192, 192, 192, 255],
            )),
            highlight: Some(create_test_image(
                &ctx,
                4,
                4,
                wgpu::TextureFormat::Rgba8Unorm,
                "highlight_mask",
                [128, 128, 128, 255],
            )),
            shadow: Some(create_test_image(
                &ctx,
                4,
                4,
                wgpu::TextureFormat::Rgba8Unorm,
                "shadow_mask",
                [96, 96, 96, 255],
            )),
            foreground_subject: Some(create_test_image(
                &ctx,
                4,
                4,
                wgpu::TextureFormat::Rgba8Unorm,
                "foreground_mask",
                [224, 224, 224, 255],
            )),
        };

        let mut params = RenderParams::default();
        params.bloom = BloomParams {
            threshold: 0.4,
            intensity: 0.35,
            radius: 0.6,
            softness: 0.55,
            ..BloomParams::default()
        };
        params.halation = HalationParams {
            threshold: 0.55,
            intensity: 0.22,
            radius: 0.7,
            red_bias: 0.8,
            warmth: 0.6,
            ..HalationParams::default()
        };
        params.vignette.amount = 0.12;
        params.lens_character.soft_glow = 0.1;
        params.texture_surface.grain_luma_amount = 0.05;
        params.texture_surface.texture_boost = 0.1;

        let outputs = renderer
            .render_and_submit(&ctx, &neutral, &params, &RenderGates::default(), &masks)
            .expect("renderer should encode and submit all passes without validation errors");

        assert_eq!(outputs.final_image.width, 4);
        assert_eq!(outputs.final_image.height, 4);
        assert_eq!(outputs.final_image.format, neutral.format);
    }

    #[test]
    fn renderer_builds_missing_masks_from_neutral_when_none_are_provided() {
        let _guard = crate::test_support::gpu_test_guard();
        let Some(ctx) = create_test_context() else {
            return;
        };

        let renderer = Renderer::default();
        let neutral = create_test_image(
            &ctx,
            4,
            4,
            wgpu::TextureFormat::Rgba8Unorm,
            "neutral_without_masks",
            [96, 104, 112, 255],
        );

        let outputs = renderer
            .render_and_submit(
                &ctx,
                &neutral,
                &RenderParams::default(),
                &RenderGates::default(),
                &MaskBundle::default(),
            )
            .expect("renderer should synthesize missing masks and still complete");

        assert!(outputs.prepared_masks.face.is_some());
        assert!(outputs.prepared_masks.person.is_some());
        assert!(outputs.prepared_masks.highlight.is_some());
        assert!(outputs.prepared_masks.shadow.is_some());
        assert!(outputs.prepared_masks.foreground_subject.is_some());
        assert_eq!(outputs.final_image.format, neutral.format);
    }

    #[test]
    fn scratch_render_targets_are_reused_after_release() {
        let _guard = crate::test_support::gpu_test_guard();
        let Some(ctx) = create_test_context() else {
            return;
        };

        let first = ctx.acquire_scratch_image(8, 8, wgpu::TextureFormat::Rgba8Unorm, "scratch_a");
        let first_texture = Arc::clone(&first.texture);
        assert_eq!(ctx.scratch_pool_size(), 1);
        drop(first);

        let second = ctx.acquire_scratch_image(8, 8, wgpu::TextureFormat::Rgba8Unorm, "scratch_b");
        assert_eq!(ctx.scratch_pool_size(), 1);
        assert!(Arc::ptr_eq(&first_texture, &second.texture));
    }

    #[test]
    fn uniform_buffers_are_not_reused_before_submit() {
        let _guard = crate::test_support::gpu_test_guard();
        let Some(ctx) = create_test_context() else {
            return;
        };

        let first = ctx.acquire_uniform_buffer(64, "uniform_a");
        let second = ctx.acquire_uniform_buffer(64, "uniform_b");
        assert!(
            !Arc::ptr_eq(&first.buffer, &second.buffer),
            "uniform buffers must stay distinct until queued GPU work is submitted"
        );

        let encoder = ctx.create_encoder("uniform_reuse_reset");
        ctx.submit_and_wait(encoder)
            .expect("empty submission should still recycle transient uniform buffers");

        let third = ctx.acquire_uniform_buffer(64, "uniform_c");
        assert!(
            Arc::ptr_eq(&first.buffer, &third.buffer),
            "uniform buffers should become reusable after submission completes"
        );
    }

    fn create_test_context() -> Option<RenderContext> {
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor::default());
        let adapter =
            block_on(instance.request_adapter(&wgpu::RequestAdapterOptions::default())).ok()?;
        let (device, queue) =
            block_on(adapter.request_device(&wgpu::DeviceDescriptor::default())).ok()?;

        RenderContext::new(device, queue, wgpu::TextureFormat::Rgba16Float).ok()
    }

    fn create_test_image(
        ctx: &RenderContext,
        width: u32,
        height: u32,
        format: wgpu::TextureFormat,
        label: &str,
        rgba: [u8; 4],
    ) -> GpuImage {
        let texture = ctx.device.create_texture(&wgpu::TextureDescriptor {
            label: Some(label),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format,
            usage: wgpu::TextureUsages::TEXTURE_BINDING
                | wgpu::TextureUsages::RENDER_ATTACHMENT
                | wgpu::TextureUsages::COPY_DST
                | wgpu::TextureUsages::COPY_SRC,
            view_formats: &[],
        });

        let mut data = Vec::with_capacity((width * height * 4) as usize);
        for _ in 0..(width * height) {
            data.extend_from_slice(&rgba);
        }

        ctx.queue.write_texture(
            wgpu::TexelCopyTextureInfo {
                texture: &texture,
                mip_level: 0,
                origin: wgpu::Origin3d::ZERO,
                aspect: wgpu::TextureAspect::All,
            },
            &data,
            wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(width * 4),
                rows_per_image: Some(height),
            },
            wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
        );

        let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
        GpuImage::new(texture, view, width, height, format, label)
    }

    fn block_on<F: Future>(future: F) -> F::Output {
        let mut future = std::pin::pin!(future);
        let mut context = Context::from_waker(Waker::noop());

        loop {
            match future.as_mut().poll(&mut context) {
                Poll::Ready(value) => return value,
                Poll::Pending => thread::sleep(Duration::from_millis(1)),
            }
        }
    }
}
