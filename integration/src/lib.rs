uniffi::setup_scaffolding!();

mod model_inference;

use std::{
    path::Path,
    sync::{Arc, Mutex},
};

use inferencer::InferencerError;
use model_inference::{ModelInferenceEngine, ModelInferenceRequest};
use renderer::{
    render_with_model_outputs_ref, RenderBuffer, RenderBufferFormat, RenderModelOutputsError,
    RenderModelOutputsRequestRef, RenderRuntimeOptions,
};
use thiserror::Error;

#[derive(Debug, Error, uniffi::Error)]
pub enum IntegrationError {
    #[error("inferencer failed: {message}")]
    Inferencer { message: String },
    #[error("renderer failed: {message}")]
    Renderer { message: String },
    #[error("invalid buffer: {message}")]
    InvalidBuffer { message: String },
    #[error("missing model metadata")]
    MissingMetadata,
    #[error("unsupported batch output: {message}")]
    UnsupportedBatch { message: String },
    #[error("internal state failed: {message}")]
    InternalState { message: String },
}

impl From<InferencerError> for IntegrationError {
    fn from(value: InferencerError) -> Self {
        Self::Inferencer {
            message: value.to_string(),
        }
    }
}

impl From<RenderModelOutputsError> for IntegrationError {
    fn from(value: RenderModelOutputsError) -> Self {
        Self::Renderer {
            message: value.to_string(),
        }
    }
}

#[derive(Debug, Clone, Copy, uniffi::Enum)]
pub enum FfiRenderBufferFormat {
    Rgba8Unorm,
    Rgba16Float,
    R8Unorm,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiRenderBuffer {
    pub width: u32,
    pub height: u32,
    pub bytes_per_row: u32,
    pub format: FfiRenderBufferFormat,
    pub data: Vec<u8>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiRenderRuntimeOptions {
    pub mask_working_max_dimension: Option<u32>,
    pub bloom_base_max_dimension: Option<u32>,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiOnnxRenderRequest {
    pub reference_image: FfiRenderBuffer,
    pub neutral_preview_image: FfiRenderBuffer,
    pub neutral_image: FfiRenderBuffer,
    pub face_mask: Option<FfiRenderBuffer>,
    pub person_mask: Option<FfiRenderBuffer>,
    pub highlight_mask: Option<FfiRenderBuffer>,
    pub shadow_mask: Option<FfiRenderBuffer>,
    pub foreground_subject_mask: Option<FfiRenderBuffer>,
    pub render_runtime_options: FfiRenderRuntimeOptions,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct FfiOnnxRenderResponse {
    pub final_image: FfiRenderBuffer,
    pub normalized_params: Vec<f32>,
    pub gate_values: Vec<f32>,
}

#[derive(uniffi::Object)]
pub struct OnnxRenderPipeline {
    inference: Mutex<ModelInferenceEngine>,
    model_path: String,
    input_size: u32,
}

#[uniffi::export]
impl OnnxRenderPipeline {
    #[uniffi::constructor]
    pub fn new(
        model_path: String,
        metadata_path: Option<String>,
    ) -> Result<Arc<Self>, IntegrationError> {
        let inference = ModelInferenceEngine::load(
            Path::new(&model_path),
            metadata_path.as_deref().map(Path::new),
        )?;
        let input_size = inference.input_size() as u32;
        let canonical_model_path = inference.model_path().display().to_string();
        Ok(Arc::new(Self {
            inference: Mutex::new(inference),
            model_path: canonical_model_path,
            input_size,
        }))
    }

    #[uniffi::method]
    pub fn model_path(&self) -> String {
        self.model_path.clone()
    }

    #[uniffi::method]
    pub fn input_size(&self) -> u32 {
        self.input_size
    }

    #[uniffi::method]
    pub fn render(
        &self,
        request: FfiOnnxRenderRequest,
    ) -> Result<FfiOnnxRenderResponse, IntegrationError> {
        let runtime_options: RenderRuntimeOptions = request.render_runtime_options.into();
        let neutral_image: RenderBuffer = request.neutral_image.into();
        let face_mask = request.face_mask.map(Into::into);
        let person_mask = request.person_mask.map(Into::into);
        let highlight_mask = request.highlight_mask.map(Into::into);
        let shadow_mask = request.shadow_mask.map(Into::into);
        let foreground_subject_mask = request.foreground_subject_mask.map(Into::into);
        let internal_request = ModelInferenceRequest {
            reference_image: request.reference_image.into(),
            neutral_preview_image: request.neutral_preview_image.into(),
            face_mask: face_mask.clone(),
            person_mask: person_mask.clone(),
            highlight_mask: highlight_mask.clone(),
            shadow_mask: shadow_mask.clone(),
            foreground_subject_mask: foreground_subject_mask.clone(),
        };
        let inference = self
            .inference
            .lock()
            .map_err(|error| IntegrationError::InternalState {
                message: format!("pipeline mutex poisoned: {error}"),
            })?
            .infer(&internal_request)?;
        let render_response = render_with_model_outputs_ref(RenderModelOutputsRequestRef {
            neutral_image,
            face_mask,
            person_mask,
            highlight_mask,
            shadow_mask,
            foreground_subject_mask,
            normalized_params: &inference.normalized_params,
            gate_values: &inference.gate_values,
            runtime_options,
        })?;

        Ok(FfiOnnxRenderResponse {
            final_image: render_response.final_image.into(),
            normalized_params: inference.normalized_params,
            gate_values: inference.gate_values,
        })
    }
}

impl From<FfiRenderBufferFormat> for RenderBufferFormat {
    fn from(value: FfiRenderBufferFormat) -> Self {
        match value {
            FfiRenderBufferFormat::Rgba8Unorm => Self::Rgba8Unorm,
            FfiRenderBufferFormat::Rgba16Float => Self::Rgba16Float,
            FfiRenderBufferFormat::R8Unorm => Self::R8Unorm,
        }
    }
}

impl From<RenderBufferFormat> for FfiRenderBufferFormat {
    fn from(value: RenderBufferFormat) -> Self {
        match value {
            RenderBufferFormat::Rgba8Unorm => Self::Rgba8Unorm,
            RenderBufferFormat::Rgba16Float => Self::Rgba16Float,
            RenderBufferFormat::R8Unorm => Self::R8Unorm,
        }
    }
}

impl From<FfiRenderBuffer> for RenderBuffer {
    fn from(value: FfiRenderBuffer) -> Self {
        Self {
            width: value.width,
            height: value.height,
            bytes_per_row: value.bytes_per_row,
            format: value.format.into(),
            data: value.data,
        }
    }
}

impl From<FfiRenderRuntimeOptions> for RenderRuntimeOptions {
    fn from(value: FfiRenderRuntimeOptions) -> Self {
        Self {
            mask_working_max_dimension: value.mask_working_max_dimension,
            bloom_base_max_dimension: value.bloom_base_max_dimension,
        }
    }
}

impl From<RenderBuffer> for FfiRenderBuffer {
    fn from(value: RenderBuffer) -> Self {
        Self {
            width: value.width,
            height: value.height,
            bytes_per_row: value.bytes_per_row,
            format: value.format.into(),
            data: value.data,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn end_to_end_pipeline_smoke_runs_when_assets_are_present() -> Result<(), IntegrationError> {
        let model_path = "../core/trainer/runs/pytorch_cold_start/style_param_net.onnx".to_string();
        if !Path::new(&model_path).exists() {
            return Ok(());
        }

        let pipeline = OnnxRenderPipeline::new(model_path, None)?;
        let request = FfiOnnxRenderRequest {
            reference_image: solid_rgba8_buffer(16, 16, [180, 128, 96, 255]),
            neutral_preview_image: solid_rgba8_buffer(16, 16, [96, 104, 112, 255]),
            neutral_image: solid_rgba8_buffer(16, 16, [96, 104, 112, 255]),
            face_mask: Some(solid_r8_buffer(16, 16, 255)),
            person_mask: Some(solid_r8_buffer(16, 16, 200)),
            highlight_mask: None,
            shadow_mask: None,
            foreground_subject_mask: None,
            render_runtime_options: FfiRenderRuntimeOptions {
                mask_working_max_dimension: Some(1_536),
                bloom_base_max_dimension: Some(1_536),
            },
        };

        let response = match pipeline.render(request) {
            Ok(response) => response,
            Err(IntegrationError::Renderer { message })
                if message.contains("runtime init failed") =>
            {
                return Ok(())
            }
            Err(error) => return Err(error),
        };

        assert_eq!(response.final_image.width, 16);
        assert_eq!(response.final_image.height, 16);
        assert_eq!(response.normalized_params.len(), 100);
        assert_eq!(response.gate_values.len(), 11);
        Ok(())
    }

    fn solid_rgba8_buffer(width: u32, height: u32, rgba: [u8; 4]) -> FfiRenderBuffer {
        let mut data = Vec::with_capacity((width * height * 4) as usize);
        for _ in 0..(width * height) {
            data.extend_from_slice(&rgba);
        }
        FfiRenderBuffer {
            width,
            height,
            bytes_per_row: width * 4,
            format: FfiRenderBufferFormat::Rgba8Unorm,
            data,
        }
    }

    fn solid_r8_buffer(width: u32, height: u32, value: u8) -> FfiRenderBuffer {
        FfiRenderBuffer {
            width,
            height,
            bytes_per_row: width,
            format: FfiRenderBufferFormat::R8Unorm,
            data: vec![value; (width * height) as usize],
        }
    }
}
