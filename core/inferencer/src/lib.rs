use std::{
    fs,
    path::{Path, PathBuf},
};

use ort::{ep, session::Session, value::Tensor};
use serde::Deserialize;
use thiserror::Error;

const REF_IMAGE_INPUT_NAME: &str = "ref_image";
const NEUTRAL_PREVIEW_INPUT_NAME: &str = "neutral_preview";
const MASK_TENSOR_INPUT_NAME: &str = "mask_tensor";
const RENDERER_PARAMS_OUTPUT_NAME: &str = "renderer_params";
const MODULE_GATES_OUTPUT_NAME: &str = "module_gates";
const REF_IMAGE_CHANNELS: usize = 3;
const NEUTRAL_PREVIEW_CHANNELS: usize = 3;
const MASK_CHANNELS: usize = 5;

#[derive(Debug, Error)]
pub enum InferencerError {
    #[error("I/O failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("metadata parse failed: {0}")]
    MetadataParse(#[from] serde_json::Error),
    #[error("onnx runtime failed: {0}")]
    Ort(#[from] ort::Error),
    #[error("invalid metadata: {message}")]
    InvalidMetadata { message: String },
    #[error("invalid input: {message}")]
    InvalidInput { message: String },
    #[error("invalid output: {message}")]
    InvalidOutput { message: String },
}

#[derive(Debug, Clone, PartialEq)]
pub struct TensorData {
    pub shape: Vec<usize>,
    pub values: Vec<f32>,
}

impl TensorData {
    pub fn new(shape: Vec<usize>, values: Vec<f32>) -> Result<Self, InferencerError> {
        let tensor = Self { shape, values };
        tensor.validate()?;
        Ok(tensor)
    }

    fn element_count(&self) -> usize {
        self.shape
            .iter()
            .copied()
            .try_fold(1usize, |acc, dim| acc.checked_mul(dim))
            .unwrap_or(usize::MAX)
    }

    pub fn validate(&self) -> Result<(), InferencerError> {
        if self.shape.is_empty() {
            return Err(InferencerError::InvalidInput {
                message: "tensor shape must not be empty".to_string(),
            });
        }
        if self.shape.contains(&0) {
            return Err(InferencerError::InvalidInput {
                message: format!("tensor shape contains zero dimension: {:?}", self.shape),
            });
        }
        let expected_len = self.element_count();
        if expected_len != self.values.len() {
            return Err(InferencerError::InvalidInput {
                message: format!(
                    "tensor shape {:?} expects {} values, got {}",
                    self.shape,
                    expected_len,
                    self.values.len()
                ),
            });
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct InferenceInputs {
    pub ref_image: TensorData,
    pub neutral_preview: TensorData,
    pub mask_tensor: TensorData,
}

impl InferenceInputs {
    pub fn validate(&self, metadata: Option<&ModelMetadata>) -> Result<(), InferencerError> {
        self.ref_image.validate()?;
        self.neutral_preview.validate()?;
        self.mask_tensor.validate()?;

        validate_image_tensor(&self.ref_image, REF_IMAGE_INPUT_NAME, REF_IMAGE_CHANNELS)?;
        validate_image_tensor(
            &self.neutral_preview,
            NEUTRAL_PREVIEW_INPUT_NAME,
            NEUTRAL_PREVIEW_CHANNELS,
        )?;
        validate_image_tensor(&self.mask_tensor, MASK_TENSOR_INPUT_NAME, MASK_CHANNELS)?;

        let ref_shape = &self.ref_image.shape;
        let neutral_shape = &self.neutral_preview.shape;
        let mask_shape = &self.mask_tensor.shape;

        ensure_same_dimension(
            ref_shape[0],
            neutral_shape[0],
            "ref_image batch",
            "neutral_preview batch",
        )?;
        ensure_same_dimension(
            ref_shape[0],
            mask_shape[0],
            "ref_image batch",
            "mask_tensor batch",
        )?;
        ensure_same_dimension(
            ref_shape[2],
            neutral_shape[2],
            "ref_image height",
            "neutral_preview height",
        )?;
        ensure_same_dimension(
            ref_shape[2],
            mask_shape[2],
            "ref_image height",
            "mask_tensor height",
        )?;
        ensure_same_dimension(
            ref_shape[3],
            neutral_shape[3],
            "ref_image width",
            "neutral_preview width",
        )?;
        ensure_same_dimension(
            ref_shape[3],
            mask_shape[3],
            "ref_image width",
            "mask_tensor width",
        )?;

        if let Some(metadata) = metadata {
            let image_size = metadata.image_size;
            if ref_shape[2] != image_size || ref_shape[3] != image_size {
                return Err(InferencerError::InvalidInput {
                    message: format!(
                        "model expects image_size={} from metadata, got ref_image shape {:?}",
                        image_size, ref_shape
                    ),
                });
            }
        }

        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct InferenceOutputs {
    pub renderer_params: TensorData,
    pub module_gates: TensorData,
}

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
pub struct ModelMetadata {
    pub schema_version: u32,
    pub image_size: usize,
    pub parameter_dim: usize,
    pub gate_dim: usize,
    pub parameter_names: Vec<String>,
    pub gate_names: Vec<String>,
    pub backbone_name: String,
    pub checkpoint: String,
    #[serde(default)]
    pub format: Option<String>,
    #[serde(default)]
    pub opset_version: Option<u32>,
    #[serde(default)]
    pub dynamic_batch: Option<bool>,
}

impl ModelMetadata {
    pub fn from_json_str(json: &str) -> Result<Self, InferencerError> {
        let metadata: Self = serde_json::from_str(json)?;
        metadata.validate()?;
        Ok(metadata)
    }

    pub fn from_file(path: impl AsRef<Path>) -> Result<Self, InferencerError> {
        let raw = fs::read_to_string(path)?;
        Self::from_json_str(&raw)
    }

    pub fn validate(&self) -> Result<(), InferencerError> {
        if self.image_size == 0 {
            return Err(InferencerError::InvalidMetadata {
                message: "image_size must be greater than zero".to_string(),
            });
        }
        if self.parameter_dim == 0 || self.gate_dim == 0 {
            return Err(InferencerError::InvalidMetadata {
                message: "parameter_dim and gate_dim must be greater than zero".to_string(),
            });
        }
        if self.parameter_names.len() != self.parameter_dim {
            return Err(InferencerError::InvalidMetadata {
                message: format!(
                    "parameter_names count {} does not match parameter_dim {}",
                    self.parameter_names.len(),
                    self.parameter_dim
                ),
            });
        }
        if self.gate_names.len() != self.gate_dim {
            return Err(InferencerError::InvalidMetadata {
                message: format!(
                    "gate_names count {} does not match gate_dim {}",
                    self.gate_names.len(),
                    self.gate_dim
                ),
            });
        }
        if let Some(format) = &self.format {
            if format != "onnx" {
                return Err(InferencerError::InvalidMetadata {
                    message: format!("expected ONNX metadata, got format={format}"),
                });
            }
        }
        Ok(())
    }
}

pub struct OnnxInferencer {
    session: Session,
    metadata: Option<ModelMetadata>,
    model_path: PathBuf,
}

impl OnnxInferencer {
    pub fn load(model_path: impl AsRef<Path>) -> Result<Self, InferencerError> {
        let model_path = model_path.as_ref().to_path_buf();
        let metadata = adjacent_metadata_path(&model_path)
            .filter(|path| path.exists())
            .map(ModelMetadata::from_file)
            .transpose()?;
        Self::load_inner(model_path, metadata)
    }

    pub fn load_with_metadata(
        model_path: impl AsRef<Path>,
        metadata_path: impl AsRef<Path>,
    ) -> Result<Self, InferencerError> {
        let model_path = model_path.as_ref().to_path_buf();
        let metadata = ModelMetadata::from_file(metadata_path)?;
        Self::load_inner(model_path, Some(metadata))
    }

    pub fn model_path(&self) -> &Path {
        &self.model_path
    }

    pub fn metadata(&self) -> Option<&ModelMetadata> {
        self.metadata.as_ref()
    }

    pub fn infer(&mut self, inputs: InferenceInputs) -> Result<InferenceOutputs, InferencerError> {
        inputs.validate(self.metadata.as_ref())?;
        let InferenceInputs {
            ref_image,
            neutral_preview,
            mask_tensor,
        } = inputs;

        let outputs = self.session.run(ort::inputs! {
            REF_IMAGE_INPUT_NAME => Tensor::from_array((
                ref_image.shape,
                ref_image.values,
            ))?,
            NEUTRAL_PREVIEW_INPUT_NAME => Tensor::from_array((
                neutral_preview.shape,
                neutral_preview.values,
            ))?,
            MASK_TENSOR_INPUT_NAME => Tensor::from_array((
                mask_tensor.shape,
                mask_tensor.values,
            ))?,
        })?;

        let renderer_params = extract_output_tensor(
            &outputs,
            RENDERER_PARAMS_OUTPUT_NAME,
            self.metadata
                .as_ref()
                .map(|metadata| metadata.parameter_dim),
        )?;
        let module_gates = extract_output_tensor(
            &outputs,
            MODULE_GATES_OUTPUT_NAME,
            self.metadata.as_ref().map(|metadata| metadata.gate_dim),
        )?;

        Ok(InferenceOutputs {
            renderer_params,
            module_gates,
        })
    }

    fn load_inner(
        model_path: PathBuf,
        metadata: Option<ModelMetadata>,
    ) -> Result<Self, InferencerError> {
        let session_builder = Session::builder()?;
        let mut session_builder = session_builder
            .with_execution_providers(default_execution_providers())
            .unwrap_or_else(|error| error.recover());
        let session = session_builder.commit_from_file(&model_path)?;
        Ok(Self {
            session,
            metadata,
            model_path,
        })
    }
}

fn extract_output_tensor(
    outputs: &ort::session::SessionOutputs<'_>,
    name: &str,
    expected_last_dim: Option<usize>,
) -> Result<TensorData, InferencerError> {
    let value = outputs
        .get(name)
        .ok_or_else(|| InferencerError::InvalidOutput {
            message: format!("model output `{name}` was not returned"),
        })?;
    let (shape, data) = value.try_extract_tensor::<f32>()?;
    let mut shape_vec = Vec::with_capacity(shape.len());
    let mut expected_len = 1usize;
    for dim in shape.iter() {
        let dim = usize::try_from(*dim).map_err(|_| InferencerError::InvalidOutput {
            message: format!("output `{name}` contains invalid dimension {}", dim),
        })?;
        if dim == 0 {
            return Err(InferencerError::InvalidOutput {
                message: format!("output `{name}` contains invalid zero dimension"),
            });
        }
        expected_len =
            expected_len
                .checked_mul(dim)
                .ok_or_else(|| InferencerError::InvalidOutput {
                    message: format!("output `{name}` shape overflowed element count"),
                })?;
        shape_vec.push(dim);
    }

    if shape_vec.is_empty() {
        return Err(InferencerError::InvalidOutput {
            message: format!("output `{name}` has empty shape"),
        });
    }

    if let Some(expected_last_dim) = expected_last_dim {
        let actual_last_dim = *shape_vec
            .last()
            .ok_or_else(|| InferencerError::InvalidOutput {
                message: format!("output `{name}` has empty shape"),
            })?;
        if actual_last_dim != expected_last_dim {
            return Err(InferencerError::InvalidOutput {
                message: format!(
                    "output `{name}` expected last dimension {}, got shape {:?}",
                    expected_last_dim, shape_vec
                ),
            });
        }
    }

    if expected_len != data.len() {
        return Err(InferencerError::InvalidOutput {
            message: format!(
                "output `{name}` shape {:?} expects {} values, got {}",
                shape_vec,
                expected_len,
                data.len()
            ),
        });
    }

    Ok(TensorData {
        shape: shape_vec,
        values: data.to_vec(),
    })
}

fn validate_image_tensor(
    tensor: &TensorData,
    name: &str,
    expected_channels: usize,
) -> Result<(), InferencerError> {
    if tensor.shape.len() != 4 {
        return Err(InferencerError::InvalidInput {
            message: format!("{name} must be NCHW 4D tensor, got {:?}", tensor.shape),
        });
    }
    if tensor.shape[1] != expected_channels {
        return Err(InferencerError::InvalidInput {
            message: format!(
                "{name} expected {} channels, got shape {:?}",
                expected_channels, tensor.shape
            ),
        });
    }
    Ok(())
}

fn ensure_same_dimension(
    left: usize,
    right: usize,
    left_name: &str,
    right_name: &str,
) -> Result<(), InferencerError> {
    if left != right {
        return Err(InferencerError::InvalidInput {
            message: format!("{left_name} ({left}) does not match {right_name} ({right})"),
        });
    }
    Ok(())
}

fn adjacent_metadata_path(model_path: &Path) -> Option<PathBuf> {
    let stem = model_path.file_stem()?;
    let mut file_name = stem.to_os_string();
    file_name.push(".json");
    Some(model_path.with_file_name(file_name))
}

fn default_execution_providers() -> Vec<ep::ExecutionProviderDispatch> {
    let mut providers = Vec::new();

    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        providers.push(
            ep::CoreML::default()
                .with_static_input_shapes(true)
                .with_model_format(ep::coreml::ModelFormat::MLProgram)
                .build(),
        );
    }

    #[cfg(target_os = "android")]
    {
        providers.push(ep::NNAPI::default().with_nchw(true).build());
    }

    providers.push(ep::CPU::default().build());
    providers
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn tensor_data_rejects_shape_mismatch() {
        let error =
            TensorData::new(vec![1, 3, 2, 2], vec![0.0; 11]).expect_err("should reject bad len");
        assert!(matches!(error, InferencerError::InvalidInput { .. }));
    }

    #[test]
    fn metadata_validates_expected_lengths() {
        let error = ModelMetadata::from_json_str(
            r#"{
                "schema_version": 1,
                "image_size": 256,
                "parameter_dim": 2,
                "gate_dim": 1,
                "parameter_names": ["a"],
                "gate_names": ["b"],
                "backbone_name": "fastvit_sa24",
                "checkpoint": "last.pt",
                "format": "onnx"
            }"#,
        )
        .expect_err("metadata should reject mismatched parameter names");

        assert!(matches!(error, InferencerError::InvalidMetadata { .. }));
    }

    #[test]
    fn inference_inputs_validate_channel_and_size_constraints() {
        let metadata = ModelMetadata {
            schema_version: 1,
            image_size: 256,
            parameter_dim: 100,
            gate_dim: 11,
            parameter_names: vec!["p".to_string(); 100],
            gate_names: vec!["g".to_string(); 11],
            backbone_name: "fastvit_sa24".to_string(),
            checkpoint: "last.pt".to_string(),
            format: Some("onnx".to_string()),
            opset_version: Some(17),
            dynamic_batch: Some(true),
        };

        let inputs = InferenceInputs {
            ref_image: TensorData::new(vec![1, 3, 256, 256], vec![0.0; 3 * 256 * 256]).unwrap(),
            neutral_preview: TensorData::new(vec![1, 3, 256, 256], vec![0.0; 3 * 256 * 256])
                .unwrap(),
            mask_tensor: TensorData::new(vec![1, 5, 128, 256], vec![0.0; 5 * 128 * 256]).unwrap(),
        };

        let error = inputs
            .validate(Some(&metadata))
            .expect_err("mask height should mismatch");
        assert!(matches!(error, InferencerError::InvalidInput { .. }));
    }

    #[test]
    fn end_to_end_inference_with_exported_model() -> Result<(), InferencerError> {
        let model_path = PathBuf::from("../trainer/runs/pytorch_cold_start/style_param_net.onnx");
        if !model_path.exists() {
            return Ok(());
        }

        let mut inferencer = OnnxInferencer::load(&model_path)?;
        let image_size = inferencer
            .metadata()
            .map(|metadata| metadata.image_size)
            .unwrap_or(256);
        let inputs = InferenceInputs {
            ref_image: TensorData::new(
                vec![1, 3, image_size, image_size],
                vec![0.0; 3 * image_size * image_size],
            )?,
            neutral_preview: TensorData::new(
                vec![1, 3, image_size, image_size],
                vec![0.0; 3 * image_size * image_size],
            )?,
            mask_tensor: TensorData::new(
                vec![1, 5, image_size, image_size],
                vec![0.0; 5 * image_size * image_size],
            )?,
        };

        let outputs = inferencer.infer(inputs)?;
        assert_eq!(outputs.renderer_params.shape, vec![1, 100]);
        assert_eq!(outputs.module_gates.shape, vec![1, 11]);
        assert_eq!(outputs.renderer_params.values.len(), 100);
        assert_eq!(outputs.module_gates.values.len(), 11);
        Ok(())
    }
}
