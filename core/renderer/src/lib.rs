pub mod api;
pub mod effects;
pub mod pipeline;
pub mod runtime;
pub mod stages;

mod model_outputs;

pub use model_outputs::{
    render_with_model_outputs, render_with_model_outputs_ref, RenderBuffer, RenderBufferFormat,
    RenderModelOutputsError, RenderModelOutputsRequest, RenderModelOutputsRequestRef,
    RenderModelOutputsResponse,
};

pub use api::contract::{
    decode_render_gates, decode_render_params, GATE_NAMES, MASK_NAMES, PARAMETER_SPECS,
    RENDER_STAGE_ORDER,
};
pub use api::error::{RenderError, RenderResult};
pub use api::renderer::{RenderRuntimeOptions, Renderer};
pub use api::types::{
    BloomParams, ExposureWbParams, FaceLocalParams, ForegroundSubjectLocalParams,
    GlobalColorParams, GlobalToneParams, GpuImage, GpuMask, HalationParams, HueSectorAdjustment,
    LensCharacterParams, MaskBundle, OutputFinishParams, PersonLocalParams, PreparedMasks,
    RenderGates, RenderOutputs, RenderParams, SectorColorParams, SemanticLocalParams,
    TextureSurfaceParams, TonalLocalParams, VignetteParams,
};
pub use runtime::context::RenderContext;

#[cfg(test)]
pub(crate) mod test_support {
    use std::sync::{Mutex, MutexGuard, OnceLock};

    static GPU_TEST_MUTEX: OnceLock<Mutex<()>> = OnceLock::new();

    pub(crate) fn gpu_test_guard() -> MutexGuard<'static, ()> {
        GPU_TEST_MUTEX
            .get_or_init(|| Mutex::new(()))
            .lock()
            .expect("gpu test mutex should not be poisoned")
    }
}
