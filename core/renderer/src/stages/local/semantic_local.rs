use crate::{
    api::{
        error::RenderResult,
        types::{GpuImage, PreparedMasks, RenderGates, SemanticLocalParams},
    },
    pipeline::{shader_sources::SEMANTIC_LOCAL_WGSL, uniforms::SemanticLocalUniform},
    runtime::{context::RenderContext, fullscreen_pass::render_masked_pass},
};

#[derive(Debug, Default)]
pub struct SemanticLocalStage;

impl SemanticLocalStage {
    pub fn apply(
        &self,
        ctx: &RenderContext,
        encoder: &mut wgpu::CommandEncoder,
        input: &GpuImage,
        params: &SemanticLocalParams,
        gates: &RenderGates,
        masks: &PreparedMasks,
    ) -> RenderResult<GpuImage> {
        let texel_scale = input.width.max(1) as f32 / 256.0_f32;
        let uniform = SemanticLocalUniform {
            face_a: [
                params.face.exposure,
                params.face.saturation,
                params.face.hue_shift,
                params.face.warmth,
            ],
            face_b: [params.face.soft_clarity, 0.0, 0.0, 0.0],
            person_a: [
                params.person.exposure,
                params.person.saturation,
                params.person.hue_shift,
                params.person.clarity,
            ],
            foreground_a: [
                params.foreground_subject.hue_shift,
                params.foreground_subject.saturation,
                params.foreground_subject.luma,
                params.foreground_subject.exposure,
            ],
            foreground_b: [
                params.foreground_subject.contrast,
                params.foreground_subject.pop,
                0.0,
                0.0,
            ],
            tonal_a: [
                params.tonal_local.highlight_warmth,
                params.tonal_local.shadow_tint,
                params.tonal_local.shadow_desat,
                texel_scale,
            ],
            gates: [
                gates.face_gate,
                gates.person_gate,
                gates.foreground_subject_gate,
                gates.tonal_local_gate,
            ],
        };
        render_masked_pass(
            ctx,
            encoder,
            input,
            masks,
            SEMANTIC_LOCAL_WGSL,
            "pass_3_semantic_local",
            &uniform,
        )
    }
}
