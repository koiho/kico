use bytemuck::{Pod, Zeroable};

use crate::{
    api::{
        error::RenderResult,
        types::{GpuImage, GpuMask, MaskBundle, PreparedMasks, TonalLocalParams},
    },
    pipeline::shader_sources::{
        MASK_BLUR_WGSL, MASK_MAX_WGSL, MASK_RESAMPLE_WGSL, TONAL_MASK_WGSL,
    },
    runtime::{
        context::RenderContext,
        fullscreen_pass::{render_basic_pass_to_target, render_dual_texture_pass_to_target},
    },
};

#[derive(Debug, Default)]
pub struct MaskPrepStage;

#[derive(Debug, Clone, Copy)]
pub struct MaskPrepRequirements {
    pub face: bool,
    pub person: bool,
    pub highlight: bool,
    pub shadow: bool,
    pub foreground_subject: bool,
}

impl MaskPrepRequirements {
    pub fn any(self) -> bool {
        self.face || self.person || self.highlight || self.shadow || self.foreground_subject
    }
}

impl MaskPrepStage {
    const MASK_FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;
    const SEMANTIC_EDGE_SOFTNESS: f32 = 1.15;
    const TONAL_EDGE_SOFTNESS: f32 = 1.35;

    pub fn prepare(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        neutral: &GpuImage,
        masks: &MaskBundle,
        tonal_local: &TonalLocalParams,
        working_max_dimension: Option<u32>,
        requirements: MaskPrepRequirements,
    ) -> RenderResult<PreparedMasks> {
        let (mask_width, mask_height) =
            working_dimensions(neutral.width, neutral.height, working_max_dimension);
        let shared_zero_mask = if requirements.any()
            && (!requirements.face
                || !requirements.person
                || !requirements.highlight
                || !requirements.shadow
                || !requirements.foreground_subject)
        {
            Some(self.create_zero_mask(
                ctx,
                encoder,
                mask_width,
                mask_height,
                "mask_prep_zero_shared",
            ))
        } else {
            None
        };

        let face = if requirements.face {
            self.prepare_semantic_mask(
                ctx,
                encoder,
                masks.face.as_ref(),
                mask_width,
                mask_height,
                "mask_prep_face",
            )?
        } else {
            shared_zero_mask
                .as_ref()
                .expect("shared zero mask should exist when a semantic mask is skipped")
                .clone()
        };
        let person = if requirements.person {
            self.prepare_semantic_mask(
                ctx,
                encoder,
                masks.person.as_ref(),
                mask_width,
                mask_height,
                "mask_prep_person",
            )?
        } else {
            shared_zero_mask
                .as_ref()
                .expect("shared zero mask should exist when a semantic mask is skipped")
                .clone()
        };
        let foreground_subject = if requirements.foreground_subject {
            self.prepare_semantic_mask(
                ctx,
                encoder,
                masks.foreground_subject.as_ref(),
                mask_width,
                mask_height,
                "mask_prep_foreground_subject",
            )?
        } else {
            shared_zero_mask
                .as_ref()
                .expect("shared zero mask should exist when a semantic mask is skipped")
                .clone()
        };

        let highlight = if requirements.highlight {
            let highlight_rule = self.build_highlight_mask_from_neutral(
                ctx,
                encoder,
                neutral,
                tonal_local,
                mask_width,
                mask_height,
            )?;
            self.prepare_tonal_mask(
                ctx,
                encoder,
                masks.highlight.as_ref(),
                &highlight_rule,
                mask_width,
                mask_height,
                "mask_prep_highlight",
            )?
        } else {
            shared_zero_mask
                .as_ref()
                .expect("shared zero mask should exist when a tonal mask is skipped")
                .clone()
        };
        let shadow = if requirements.shadow {
            let shadow_rule = self.build_shadow_mask_from_neutral(
                ctx,
                encoder,
                neutral,
                tonal_local,
                mask_width,
                mask_height,
            )?;
            self.prepare_tonal_mask(
                ctx,
                encoder,
                masks.shadow.as_ref(),
                &shadow_rule,
                mask_width,
                mask_height,
                "mask_prep_shadow",
            )?
        } else {
            shared_zero_mask
                .as_ref()
                .expect("shared zero mask should exist when a tonal mask is skipped")
                .clone()
        };

        Ok(PreparedMasks {
            face: Some(face),
            person: Some(person),
            highlight: Some(highlight),
            shadow: Some(shadow),
            foreground_subject: Some(foreground_subject),
            width: mask_width,
            height: mask_height,
        })
    }

    fn prepare_semantic_mask(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        mask: Option<&GpuMask>,
        width: u32,
        height: u32,
        label: &str,
    ) -> RenderResult<GpuMask> {
        let normalized = match mask {
            Some(mask) => self.normalize_mask_range(ctx, encoder, mask, width, height, label)?,
            None => self.create_zero_mask(ctx, encoder, width, height, label),
        };
        self.soften_mask_edges(
            ctx,
            encoder,
            &normalized,
            Self::SEMANTIC_EDGE_SOFTNESS,
            &format!("{label}_softened"),
        )
    }

    fn prepare_tonal_mask(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        provided_mask: Option<&GpuMask>,
        rule_mask: &GpuMask,
        width: u32,
        height: u32,
        label: &str,
    ) -> RenderResult<GpuMask> {
        let provided = match provided_mask {
            Some(mask) => Some(self.normalize_mask_range(
                ctx,
                encoder,
                mask,
                width,
                height,
                &format!("{label}_provided"),
            )?),
            None => None,
        };

        let merged =
            self.merge_vision_and_rule_masks(ctx, encoder, provided.as_ref(), rule_mask, label)?;

        self.soften_mask_edges(
            ctx,
            encoder,
            &merged,
            Self::TONAL_EDGE_SOFTNESS,
            &format!("{label}_softened"),
        )
    }

    fn normalize_mask_range(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        mask: &GpuMask,
        width: u32,
        height: u32,
        label: &str,
    ) -> RenderResult<GpuMask> {
        ctx.validate_image(mask)?;

        let uniform = MaskScalarUniform {
            params: [0.0, 1.0, 1.0, 0.0],
        };
        render_basic_pass_to_target(
            ctx,
            encoder,
            mask,
            width,
            height,
            Self::MASK_FORMAT,
            MASK_RESAMPLE_WGSL,
            label,
            &uniform,
        )
    }

    fn soften_mask_edges(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        mask: &GpuMask,
        radius: f32,
        label: &str,
    ) -> RenderResult<GpuMask> {
        let uniform = MaskScalarUniform {
            params: [radius, 0.0, 0.0, 0.0],
        };
        render_basic_pass_to_target(
            ctx,
            encoder,
            mask,
            mask.width,
            mask.height,
            Self::MASK_FORMAT,
            MASK_BLUR_WGSL,
            label,
            &uniform,
        )
    }

    fn build_highlight_mask_from_neutral(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        neutral: &GpuImage,
        tonal_local: &TonalLocalParams,
        width: u32,
        height: u32,
    ) -> RenderResult<GpuMask> {
        let threshold = tonal_local.highlight_mask_threshold.clamp(0.0, 1.5);
        let feather = tonal_local.highlight_mask_feather.clamp(0.001, 1.0);
        let uniform = TonalMaskUniform {
            params: [0.0, threshold, feather, 1.0],
        };
        let tonal = render_basic_pass_to_target(
            ctx,
            encoder,
            neutral,
            width,
            height,
            Self::MASK_FORMAT,
            TONAL_MASK_WGSL,
            "mask_prep_highlight_rule",
            &uniform,
        )?;
        self.soften_mask_edges(
            ctx,
            encoder,
            &tonal,
            Self::TONAL_EDGE_SOFTNESS,
            "mask_prep_highlight_rule_softened",
        )
    }

    fn build_shadow_mask_from_neutral(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        neutral: &GpuImage,
        tonal_local: &TonalLocalParams,
        width: u32,
        height: u32,
    ) -> RenderResult<GpuMask> {
        let threshold = tonal_local.shadow_mask_threshold.clamp(0.0, 1.5);
        let feather = tonal_local.shadow_mask_feather.clamp(0.001, 1.0);
        let uniform = TonalMaskUniform {
            params: [1.0, threshold, feather, 1.0],
        };
        let tonal = render_basic_pass_to_target(
            ctx,
            encoder,
            neutral,
            width,
            height,
            Self::MASK_FORMAT,
            TONAL_MASK_WGSL,
            "mask_prep_shadow_rule",
            &uniform,
        )?;
        self.soften_mask_edges(
            ctx,
            encoder,
            &tonal,
            Self::TONAL_EDGE_SOFTNESS,
            "mask_prep_shadow_rule_softened",
        )
    }

    fn merge_vision_and_rule_masks(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        provided_mask: Option<&GpuMask>,
        rule_mask: &GpuMask,
        label: &str,
    ) -> RenderResult<GpuMask> {
        let Some(provided_mask) = provided_mask else {
            return Ok(rule_mask.clone());
        };

        let uniform = MaskScalarUniform {
            params: [1.0, 0.0, 0.0, 0.0],
        };
        render_dual_texture_pass_to_target(
            ctx,
            encoder,
            provided_mask,
            rule_mask,
            rule_mask.width,
            rule_mask.height,
            Self::MASK_FORMAT,
            MASK_MAX_WGSL,
            label,
            &uniform,
        )
    }

    fn create_zero_mask(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        width: u32,
        height: u32,
        label: &str,
    ) -> GpuMask {
        let mask = ctx.acquire_scratch_image(width, height, Self::MASK_FORMAT, label);
        let pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: Some(label),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: &mask.view,
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
        drop(pass);
        mask
    }
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable)]
struct MaskScalarUniform {
    params: [f32; 4],
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Pod, Zeroable)]
struct TonalMaskUniform {
    params: [f32; 4],
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
