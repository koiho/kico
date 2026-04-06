use std::path::Path;

use half::{
    f16,
    slice::{HalfBitsSliceExt, HalfFloatSliceExt},
};
use inferencer::{InferenceInputs, OnnxInferencer, TensorData};
use renderer::{RenderBuffer, RenderBufferFormat};

use crate::IntegrationError;

pub(crate) struct ModelInferenceRequest {
    pub reference_image: RenderBuffer,
    pub neutral_preview_image: RenderBuffer,
    pub neutral_image: RenderBuffer,
    pub face_mask: Option<RenderBuffer>,
    pub person_mask: Option<RenderBuffer>,
    pub highlight_mask: Option<RenderBuffer>,
    pub shadow_mask: Option<RenderBuffer>,
    pub foreground_subject_mask: Option<RenderBuffer>,
}

pub(crate) struct ModelInferenceResult {
    pub normalized_params: Vec<f32>,
    pub gate_values: Vec<f32>,
}

pub(crate) struct ModelInferenceEngine {
    inferencer: OnnxInferencer,
    input_size: usize,
}

impl ModelInferenceEngine {
    pub(crate) fn load(
        model_path: impl AsRef<Path>,
        metadata_path: Option<&Path>,
    ) -> Result<Self, IntegrationError> {
        let inferencer = match metadata_path {
            Some(metadata_path) => OnnxInferencer::load_with_metadata(model_path, metadata_path)?,
            None => OnnxInferencer::load(model_path)?,
        };
        let input_size = inferencer
            .metadata()
            .map(|metadata| metadata.image_size)
            .ok_or(IntegrationError::MissingMetadata)?;
        Ok(Self {
            inferencer,
            input_size,
        })
    }

    pub(crate) fn input_size(&self) -> usize {
        self.input_size
    }

    pub(crate) fn model_path(&self) -> &Path {
        self.inferencer.model_path()
    }

    pub(crate) fn infer(
        &mut self,
        request: &ModelInferenceRequest,
    ) -> Result<ModelInferenceResult, IntegrationError> {
        validate_color_buffer(&request.reference_image, "reference_image")?;
        validate_color_buffer(&request.neutral_preview_image, "neutral_preview_image")?;
        validate_color_buffer(&request.neutral_image, "neutral_image")?;
        validate_optional_mask(&request.face_mask, "face_mask")?;
        validate_optional_mask(&request.person_mask, "person_mask")?;
        validate_optional_mask(&request.highlight_mask, "highlight_mask")?;
        validate_optional_mask(&request.shadow_mask, "shadow_mask")?;
        validate_optional_mask(&request.foreground_subject_mask, "foreground_subject_mask")?;

        let mut resize_axes_cache = ResizeAxesCache::default();
        let ref_image = color_buffer_to_nchw_with_cache(
            &request.reference_image,
            self.input_size,
            &mut resize_axes_cache,
        )?;
        let neutral_preview = color_buffer_to_nchw_with_cache(
            &request.neutral_preview_image,
            self.input_size,
            &mut resize_axes_cache,
        )?;
        let mask_tensor = pack_mask_tensor(
            request.face_mask.as_ref(),
            request.person_mask.as_ref(),
            request.highlight_mask.as_ref(),
            request.shadow_mask.as_ref(),
            request.foreground_subject_mask.as_ref(),
            self.input_size,
            &mut resize_axes_cache,
        )?;

        let inference_outputs = self.inferencer.infer(InferenceInputs {
            ref_image: TensorData::new(vec![1, 3, self.input_size, self.input_size], ref_image)?,
            neutral_preview: TensorData::new(
                vec![1, 3, self.input_size, self.input_size],
                neutral_preview,
            )?,
            mask_tensor: TensorData::new(
                vec![1, 5, self.input_size, self.input_size],
                mask_tensor,
            )?,
        })?;

        Ok(ModelInferenceResult {
            normalized_params: flatten_batch_one(
                inference_outputs.renderer_params,
                "renderer_params",
            )?,
            gate_values: flatten_batch_one(inference_outputs.module_gates, "module_gates")?,
        })
    }
}

fn flatten_batch_one(tensor: TensorData, name: &str) -> Result<Vec<f32>, IntegrationError> {
    let TensorData { shape, values } = tensor;
    match shape.as_slice() {
        [1, width] => {
            let expected_len = *width;
            if values.len() != expected_len {
                return Err(IntegrationError::UnsupportedBatch {
                    message: format!(
                        "{name} shape {:?} does not match value count {}",
                        shape,
                        values.len()
                    ),
                });
            }
            Ok(values)
        }
        other => Err(IntegrationError::UnsupportedBatch {
            message: format!("{name} expected batch-one tensor [1, N], got {:?}", other),
        }),
    }
}

fn validate_optional_mask(
    buffer: &Option<RenderBuffer>,
    label: &str,
) -> Result<(), IntegrationError> {
    if let Some(buffer) = buffer {
        validate_mask_buffer(buffer, label)?;
    }
    Ok(())
}

fn validate_color_buffer(buffer: &RenderBuffer, label: &str) -> Result<(), IntegrationError> {
    validate_buffer_layout(buffer, label)?;
    if !matches!(
        buffer.format,
        RenderBufferFormat::Rgba8Unorm | RenderBufferFormat::Rgba16Float
    ) {
        return Err(IntegrationError::InvalidBuffer {
            message: format!("{label} must be RGBA, got {:?}", buffer.format),
        });
    }
    Ok(())
}

fn validate_mask_buffer(buffer: &RenderBuffer, label: &str) -> Result<(), IntegrationError> {
    validate_buffer_layout(buffer, label)?;
    if !matches!(buffer.format, RenderBufferFormat::R8Unorm) {
        return Err(IntegrationError::InvalidBuffer {
            message: format!("{label} must be R8Unorm, got {:?}", buffer.format),
        });
    }
    Ok(())
}

fn validate_buffer_layout(buffer: &RenderBuffer, label: &str) -> Result<(), IntegrationError> {
    if buffer.width == 0 || buffer.height == 0 {
        return Err(IntegrationError::InvalidBuffer {
            message: format!("{label} must have non-zero width and height"),
        });
    }
    let min_bytes_per_row = buffer
        .width
        .checked_mul(bytes_per_pixel(buffer.format))
        .ok_or_else(|| IntegrationError::InvalidBuffer {
            message: format!("{label} width overflow while computing bytes_per_row"),
        })?;
    if buffer.bytes_per_row < min_bytes_per_row {
        return Err(IntegrationError::InvalidBuffer {
            message: format!(
                "{label} bytes_per_row too small, expected at least {min_bytes_per_row}, got {}",
                buffer.bytes_per_row
            ),
        });
    }
    let required_len = (buffer.bytes_per_row as usize)
        .checked_mul(buffer.height as usize)
        .ok_or_else(|| IntegrationError::InvalidBuffer {
            message: format!("{label} byte length overflow"),
        })?;
    if buffer.data.len() < required_len {
        return Err(IntegrationError::InvalidBuffer {
            message: format!(
                "{label} data too short, expected at least {required_len} bytes, got {}",
                buffer.data.len()
            ),
        });
    }
    Ok(())
}

fn bytes_per_pixel(format: RenderBufferFormat) -> u32 {
    match format {
        RenderBufferFormat::Rgba8Unorm => 4,
        RenderBufferFormat::Rgba16Float => 8,
        RenderBufferFormat::R8Unorm => 1,
    }
}

#[derive(Clone, Copy)]
struct ResizeSample {
    lower: usize,
    upper: usize,
    upper_weight: f32,
}

struct ResizeAxes {
    x_axis: Vec<ResizeSample>,
    y_axis: Vec<ResizeSample>,
}

#[derive(Default)]
struct ResizeAxesCache {
    entries: Vec<(u32, u32, ResizeAxes)>,
}

impl ResizeAxesCache {
    fn get_or_create(
        &mut self,
        width: u32,
        height: u32,
        target_size: usize,
    ) -> (&[ResizeSample], &[ResizeSample]) {
        let index = if let Some(index) =
            self.entries
                .iter()
                .position(|(cached_width, cached_height, _)| {
                    *cached_width == width && *cached_height == height
                }) {
            index
        } else {
            self.entries.push((
                width,
                height,
                ResizeAxes {
                    x_axis: build_resize_axis(target_size, width as usize),
                    y_axis: build_resize_axis(target_size, height as usize),
                },
            ));
            self.entries.len() - 1
        };

        let (_, _, axes) = &self.entries[index];
        (&axes.x_axis, &axes.y_axis)
    }
}

#[cfg(test)]
fn color_buffer_to_nchw(
    buffer: &RenderBuffer,
    target_size: usize,
) -> Result<Vec<f32>, IntegrationError> {
    let mut resize_axes_cache = ResizeAxesCache::default();
    color_buffer_to_nchw_with_cache(buffer, target_size, &mut resize_axes_cache)
}

fn color_buffer_to_nchw_with_cache(
    buffer: &RenderBuffer,
    target_size: usize,
    resize_axes_cache: &mut ResizeAxesCache,
) -> Result<Vec<f32>, IntegrationError> {
    let plane = target_size * target_size;
    let mut output = vec![0.0_f32; 3 * plane];

    if buffer.width as usize == target_size && buffer.height as usize == target_size {
        match buffer.format {
            RenderBufferFormat::Rgba8Unorm => copy_rgba8_to_nchw(buffer, &mut output),
            RenderBufferFormat::Rgba16Float => copy_rgba16f_to_nchw(buffer, &mut output),
            RenderBufferFormat::R8Unorm => {
                return Err(IntegrationError::InvalidBuffer {
                    message: "RGBA read requested for R8Unorm buffer".to_string(),
                })
            }
        }
        return Ok(output);
    }

    let (x_axis, y_axis) =
        resize_axes_cache.get_or_create(buffer.width, buffer.height, target_size);

    match buffer.format {
        RenderBufferFormat::Rgba8Unorm => resize_rgba8_to_nchw(buffer, x_axis, y_axis, &mut output),
        RenderBufferFormat::Rgba16Float => {
            resize_rgba16f_to_nchw(buffer, x_axis, y_axis, &mut output)
        }
        RenderBufferFormat::R8Unorm => {
            return Err(IntegrationError::InvalidBuffer {
                message: "RGBA read requested for R8Unorm buffer".to_string(),
            })
        }
    }

    Ok(output)
}

fn pack_mask_tensor(
    face_mask: Option<&RenderBuffer>,
    person_mask: Option<&RenderBuffer>,
    highlight_mask: Option<&RenderBuffer>,
    shadow_mask: Option<&RenderBuffer>,
    foreground_subject_mask: Option<&RenderBuffer>,
    target_size: usize,
    resize_axes_cache: &mut ResizeAxesCache,
) -> Result<Vec<f32>, IntegrationError> {
    let plane = target_size * target_size;
    let mut output = vec![0.0_f32; 5 * plane];
    let masks = [
        face_mask,
        person_mask,
        highlight_mask,
        shadow_mask,
        foreground_subject_mask,
    ];

    for (channel, mask) in masks.into_iter().enumerate() {
        let Some(mask) = mask else {
            continue;
        };

        let channel_output = &mut output[channel * plane..(channel + 1) * plane];
        if mask.width as usize == target_size && mask.height as usize == target_size {
            copy_mask_to_plane(mask, channel_output);
            continue;
        }

        let (x_axis, y_axis) =
            resize_axes_cache.get_or_create(mask.width, mask.height, target_size);
        resize_mask_to_plane(mask, x_axis, y_axis, channel_output);
    }

    Ok(output)
}

fn build_resize_axis(target_size: usize, source_size: usize) -> Vec<ResizeSample> {
    let mut axis = Vec::with_capacity(target_size);
    for index in 0..target_size {
        if target_size <= 1 || source_size <= 1 {
            axis.push(ResizeSample {
                lower: 0,
                upper: 0,
                upper_weight: 0.0,
            });
            continue;
        }

        let source_coord = ((index as f32) + 0.5) * (source_size as f32 / target_size as f32) - 0.5;
        let lower = source_coord.floor().clamp(0.0, (source_size - 1) as f32) as usize;
        let upper = (lower + 1).min(source_size - 1);
        let upper_weight = (source_coord - lower as f32).clamp(0.0, 1.0);
        axis.push(ResizeSample {
            lower,
            upper,
            upper_weight,
        });
    }
    axis
}

fn copy_rgba8_to_nchw(buffer: &RenderBuffer, output: &mut [f32]) {
    const INV_255: f32 = 1.0 / 255.0;
    let width = buffer.width as usize;
    let height = buffer.height as usize;
    let plane = width * height;
    let bytes_per_row = buffer.bytes_per_row as usize;
    let data = &buffer.data;

    for y in 0..height {
        let row_start = y * bytes_per_row;
        let row_index = y * width;
        for x in 0..width {
            let source_offset = row_start + x * 4;
            let index = row_index + x;
            output[index] = data[source_offset] as f32 * INV_255;
            output[plane + index] = data[source_offset + 1] as f32 * INV_255;
            output[(plane * 2) + index] = data[source_offset + 2] as f32 * INV_255;
        }
    }
}

fn copy_rgba16f_to_nchw(buffer: &RenderBuffer, output: &mut [f32]) {
    let width = buffer.width as usize;
    let height = buffer.height as usize;
    let plane = width * height;
    let bytes_per_row = buffer.bytes_per_row as usize;
    let data = &buffer.data;
    let mut decoded_row = vec![0.0_f32; width * 4];

    for y in 0..height {
        let row_start = y * bytes_per_row;
        let row_end = row_start + width * 8;
        decode_rgba16f_row_to_f32(&data[row_start..row_end], &mut decoded_row);
        let row_index = y * width;
        for x in 0..width {
            let source_offset = x * 4;
            let index = row_index + x;
            output[index] = decoded_row[source_offset];
            output[plane + index] = decoded_row[source_offset + 1];
            output[(plane * 2) + index] = decoded_row[source_offset + 2];
        }
    }
}

fn resize_rgba8_to_nchw(
    buffer: &RenderBuffer,
    x_axis: &[ResizeSample],
    y_axis: &[ResizeSample],
    output: &mut [f32],
) {
    const INV_255: f32 = 1.0 / 255.0;
    let plane = x_axis.len() * y_axis.len();
    let bytes_per_row = buffer.bytes_per_row as usize;
    let data = &buffer.data;

    for (y, y_sample) in y_axis.iter().enumerate() {
        let y0_row = y_sample.lower * bytes_per_row;
        let y1_row = y_sample.upper * bytes_per_row;
        let wy1 = y_sample.upper_weight;
        let wy0 = 1.0 - wy1;
        let row_index = y * x_axis.len();

        for (x, x_sample) in x_axis.iter().enumerate() {
            let x0 = x_sample.lower * 4;
            let x1 = x_sample.upper * 4;
            let wx1 = x_sample.upper_weight;
            let wx0 = 1.0 - wx1;
            let w00 = wy0 * wx0;
            let w10 = wy0 * wx1;
            let w01 = wy1 * wx0;
            let w11 = wy1 * wx1;

            let p00 = y0_row + x0;
            let p10 = y0_row + x1;
            let p01 = y1_row + x0;
            let p11 = y1_row + x1;
            let index = row_index + x;

            output[index] = (data[p00] as f32 * w00
                + data[p10] as f32 * w10
                + data[p01] as f32 * w01
                + data[p11] as f32 * w11)
                * INV_255;
            output[plane + index] = (data[p00 + 1] as f32 * w00
                + data[p10 + 1] as f32 * w10
                + data[p01 + 1] as f32 * w01
                + data[p11 + 1] as f32 * w11)
                * INV_255;
            output[(plane * 2) + index] = (data[p00 + 2] as f32 * w00
                + data[p10 + 2] as f32 * w10
                + data[p01 + 2] as f32 * w01
                + data[p11 + 2] as f32 * w11)
                * INV_255;
        }
    }
}

fn resize_rgba16f_to_nchw(
    buffer: &RenderBuffer,
    x_axis: &[ResizeSample],
    y_axis: &[ResizeSample],
    output: &mut [f32],
) {
    let source_width = buffer.width as usize;
    let plane = x_axis.len() * y_axis.len();
    let decoded = decode_rgba16f_rgb_interleaved(buffer);
    let decoded_row_stride = source_width * 3;

    for (y, y_sample) in y_axis.iter().enumerate() {
        let y0_row = y_sample.lower * decoded_row_stride;
        let y1_row = y_sample.upper * decoded_row_stride;
        let wy1 = y_sample.upper_weight;
        let wy0 = 1.0 - wy1;
        let row_index = y * x_axis.len();

        for (x, x_sample) in x_axis.iter().enumerate() {
            let x0 = x_sample.lower * 3;
            let x1 = x_sample.upper * 3;
            let wx1 = x_sample.upper_weight;
            let wx0 = 1.0 - wx1;
            let w00 = wy0 * wx0;
            let w10 = wy0 * wx1;
            let w01 = wy1 * wx0;
            let w11 = wy1 * wx1;

            let p00 = y0_row + x0;
            let p10 = y0_row + x1;
            let p01 = y1_row + x0;
            let p11 = y1_row + x1;
            let index = row_index + x;

            output[index] =
                decoded[p00] * w00 + decoded[p10] * w10 + decoded[p01] * w01 + decoded[p11] * w11;
            output[plane + index] = decoded[p00 + 1] * w00
                + decoded[p10 + 1] * w10
                + decoded[p01 + 1] * w01
                + decoded[p11 + 1] * w11;
            output[(plane * 2) + index] = decoded[p00 + 2] * w00
                + decoded[p10 + 2] * w10
                + decoded[p01 + 2] * w01
                + decoded[p11 + 2] * w11;
        }
    }
}

fn decode_rgba16f_rgb_interleaved(buffer: &RenderBuffer) -> Vec<f32> {
    let width = buffer.width as usize;
    let height = buffer.height as usize;
    let bytes_per_row = buffer.bytes_per_row as usize;
    let mut output = vec![0.0_f32; width * height * 3];
    let mut decoded_row = vec![0.0_f32; width * 4];

    for y in 0..height {
        let row_start = y * bytes_per_row;
        let row_end = row_start + width * 8;
        decode_rgba16f_row_to_f32(&buffer.data[row_start..row_end], &mut decoded_row);

        let output_row = &mut output[y * width * 3..(y + 1) * width * 3];
        for x in 0..width {
            let source_offset = x * 4;
            let target_offset = x * 3;
            output_row[target_offset] = decoded_row[source_offset];
            output_row[target_offset + 1] = decoded_row[source_offset + 1];
            output_row[target_offset + 2] = decoded_row[source_offset + 2];
        }
    }

    output
}

fn decode_rgba16f_row_to_f32(row_bytes: &[u8], output: &mut [f32]) {
    if row_bytes.len() == output.len() * 2 {
        // RGBA16F rows are naturally 2-byte aligned on our hot path, so we can use the half
        // crate's vectorized conversion when alignment cooperates.
        let (prefix, words, suffix) = unsafe { row_bytes.align_to::<u16>() };
        if prefix.is_empty() && suffix.is_empty() && words.len() == output.len() {
            let half_values: &[f16] = words.reinterpret_cast();
            half_values.convert_to_f32_slice(output);
            return;
        }
    }

    for (source, destination) in row_bytes.chunks_exact(2).zip(output.iter_mut()) {
        let bits = u16::from_le_bytes([source[0], source[1]]);
        *destination = f16::from_bits(bits).to_f32();
    }
}

fn copy_mask_to_plane(buffer: &RenderBuffer, output: &mut [f32]) {
    const INV_255: f32 = 1.0 / 255.0;
    let width = buffer.width as usize;
    let height = buffer.height as usize;
    let bytes_per_row = buffer.bytes_per_row as usize;
    let data = &buffer.data;

    for y in 0..height {
        let row_start = y * bytes_per_row;
        let row_index = y * width;
        for x in 0..width {
            output[row_index + x] = data[row_start + x] as f32 * INV_255;
        }
    }
}

fn resize_mask_to_plane(
    buffer: &RenderBuffer,
    x_axis: &[ResizeSample],
    y_axis: &[ResizeSample],
    output: &mut [f32],
) {
    const INV_255: f32 = 1.0 / 255.0;
    let bytes_per_row = buffer.bytes_per_row as usize;
    let data = &buffer.data;

    for (y, y_sample) in y_axis.iter().enumerate() {
        let y0_row = y_sample.lower * bytes_per_row;
        let y1_row = y_sample.upper * bytes_per_row;
        let wy1 = y_sample.upper_weight;
        let wy0 = 1.0 - wy1;
        let row_index = y * x_axis.len();

        for (x, x_sample) in x_axis.iter().enumerate() {
            let wx1 = x_sample.upper_weight;
            let wx0 = 1.0 - wx1;
            let w00 = wy0 * wx0;
            let w10 = wy0 * wx1;
            let w01 = wy1 * wx0;
            let w11 = wy1 * wx1;

            let p00 = y0_row + x_sample.lower;
            let p10 = y0_row + x_sample.upper;
            let p01 = y1_row + x_sample.lower;
            let p11 = y1_row + x_sample.upper;
            output[row_index + x] = (data[p00] as f32 * w00
                + data[p10] as f32 * w10
                + data[p01] as f32 * w01
                + data[p11] as f32 * w11)
                * INV_255;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn color_resize_produces_nchw_tensor() {
        let buffer = solid_rgba8_buffer(2, 2, [64, 128, 192, 255]);
        let tensor = color_buffer_to_nchw(&buffer, 4).expect("resize should succeed");
        assert_eq!(tensor.len(), 3 * 4 * 4);
        assert!(tensor.iter().all(|value| *value >= 0.0 && *value <= 1.0));
    }

    #[test]
    fn mask_pack_defaults_missing_masks_to_zero() {
        let tensor = pack_mask_tensor(
            None,
            None,
            None,
            None,
            None,
            4,
            &mut ResizeAxesCache::default(),
        )
        .expect("mask pack should work");
        assert_eq!(tensor.len(), 5 * 4 * 4);
        assert!(tensor.iter().all(|value| *value == 0.0));
    }

    fn solid_rgba8_buffer(width: u32, height: u32, rgba: [u8; 4]) -> RenderBuffer {
        let mut data = Vec::with_capacity((width * height * 4) as usize);
        for _ in 0..(width * height) {
            data.extend_from_slice(&rgba);
        }
        RenderBuffer {
            width,
            height,
            bytes_per_row: width * 4,
            format: RenderBufferFormat::Rgba8Unorm,
            data,
        }
    }
}
