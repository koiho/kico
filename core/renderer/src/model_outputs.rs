use std::{
    collections::HashMap,
    sync::{mpsc, Arc, Mutex},
    task::{Context, Poll, Waker},
    thread,
    time::Duration,
};

use thiserror::Error;

use crate::{
    api::{
        error::RenderError,
        types::{GpuImage, MaskBundle},
    },
    RenderContext, Renderer,
};

#[derive(Debug, Clone, Copy)]
pub enum RenderBufferFormat {
    Rgba8Unorm,
    Rgba16Float,
    R8Unorm,
}

#[derive(Debug, Clone)]
pub struct RenderBuffer {
    pub width: u32,
    pub height: u32,
    pub bytes_per_row: u32,
    pub format: RenderBufferFormat,
    pub data: Vec<u8>,
}

#[derive(Debug, Clone)]
pub struct RenderModelOutputsRequest {
    pub neutral_image: RenderBuffer,
    pub face_mask: Option<RenderBuffer>,
    pub person_mask: Option<RenderBuffer>,
    pub highlight_mask: Option<RenderBuffer>,
    pub shadow_mask: Option<RenderBuffer>,
    pub foreground_subject_mask: Option<RenderBuffer>,
    pub normalized_params: Vec<f32>,
    pub gate_values: Vec<f32>,
}

pub struct RenderModelOutputsRequestRef<'a> {
    pub neutral_image: RenderBuffer,
    pub face_mask: Option<RenderBuffer>,
    pub person_mask: Option<RenderBuffer>,
    pub highlight_mask: Option<RenderBuffer>,
    pub shadow_mask: Option<RenderBuffer>,
    pub foreground_subject_mask: Option<RenderBuffer>,
    pub normalized_params: &'a [f32],
    pub gate_values: &'a [f32],
}

#[derive(Debug, Clone)]
pub struct RenderModelOutputsResponse {
    pub final_image: RenderBuffer,
}

#[derive(Debug, Error)]
pub enum RenderModelOutputsError {
    #[error("runtime init failed: {message}")]
    RuntimeInit { message: String },
    #[error("invalid render buffer: {message}")]
    InvalidBuffer { message: String },
    #[error("render failed: {message}")]
    RenderFailed { message: String },
}

struct RuntimeState {
    ctx: RenderContext,
    renderer: Renderer,
    readback_buffers: Mutex<ReadbackBufferPool>,
    zero_mask_cache: Mutex<HashMap<(u32, u32), GpuImage>>,
}

struct RuntimeCache<T> {
    state: Mutex<Option<Arc<T>>>,
}

#[derive(Default)]
struct ReadbackBufferPool {
    entries: Vec<ReadbackBufferEntry>,
}

struct ReadbackBufferEntry {
    buffer: Arc<wgpu::Buffer>,
    size: u64,
    in_use: bool,
}

struct PendingReadback {
    buffer: Arc<wgpu::Buffer>,
    pool_index: usize,
    padded_size: u64,
    tight_bytes_per_row: u32,
    padded_bytes_per_row: u32,
    width: u32,
    height: u32,
    format: RenderBufferFormat,
}

impl<T> RuntimeCache<T> {
    const fn new() -> Self {
        Self {
            state: Mutex::new(None),
        }
    }

    fn get_or_try_init<E, F>(&self, init: F) -> Result<Arc<T>, E>
    where
        F: FnOnce() -> Result<T, E>,
    {
        let mut state = self
            .state
            .lock()
            .expect("runtime cache mutex should not be poisoned");

        if let Some(existing) = state.as_ref() {
            return Ok(Arc::clone(existing));
        }

        let created = Arc::new(init()?);
        *state = Some(Arc::clone(&created));
        Ok(created)
    }
}

static RUNTIME: RuntimeCache<RuntimeState> = RuntimeCache::new();

pub fn render_with_model_outputs(
    request: RenderModelOutputsRequest,
) -> Result<RenderModelOutputsResponse, RenderModelOutputsError> {
    let RenderModelOutputsRequest {
        neutral_image,
        face_mask,
        person_mask,
        highlight_mask,
        shadow_mask,
        foreground_subject_mask,
        normalized_params,
        gate_values,
    } = request;

    render_with_model_outputs_ref(RenderModelOutputsRequestRef {
        neutral_image,
        face_mask,
        person_mask,
        highlight_mask,
        shadow_mask,
        foreground_subject_mask,
        normalized_params: &normalized_params,
        gate_values: &gate_values,
    })
}

pub fn render_with_model_outputs_ref(
    request: RenderModelOutputsRequestRef<'_>,
) -> Result<RenderModelOutputsResponse, RenderModelOutputsError> {
    validate_render_buffers(
        &request.neutral_image,
        request.face_mask.as_ref(),
        request.person_mask.as_ref(),
        request.highlight_mask.as_ref(),
        request.shadow_mask.as_ref(),
        request.foreground_subject_mask.as_ref(),
    )?;
    let runtime = runtime_state()?;
    let neutral = upload_render_buffer_validated(
        &runtime.ctx,
        &request.neutral_image,
        "model_outputs_neutral_image",
    )?;

    let zero_mask = if request.face_mask.is_none()
        || request.person_mask.is_none()
        || request.highlight_mask.is_none()
        || request.shadow_mask.is_none()
        || request.foreground_subject_mask.is_none()
    {
        Some(create_zero_mask(
            &runtime,
            neutral.width,
            neutral.height,
            "model_outputs_zero_mask",
        )?)
    } else {
        None
    };

    let masks = MaskBundle {
        face: Some(resolve_optional_mask(
            &runtime,
            request.face_mask.as_ref(),
            zero_mask.as_ref(),
            "model_outputs_face_mask",
        )?),
        person: Some(resolve_optional_mask(
            &runtime,
            request.person_mask.as_ref(),
            zero_mask.as_ref(),
            "model_outputs_person_mask",
        )?),
        highlight: Some(resolve_optional_mask(
            &runtime,
            request.highlight_mask.as_ref(),
            zero_mask.as_ref(),
            "model_outputs_highlight_mask",
        )?),
        shadow: Some(resolve_optional_mask(
            &runtime,
            request.shadow_mask.as_ref(),
            zero_mask.as_ref(),
            "model_outputs_shadow_mask",
        )?),
        foreground_subject: Some(resolve_optional_mask(
            &runtime,
            request.foreground_subject_mask.as_ref(),
            zero_mask.as_ref(),
            "model_outputs_foreground_subject_mask",
        )?),
    };

    let mut encoder = runtime.ctx.create_encoder("render_model_outputs");
    let outputs = runtime
        .renderer
        .render_from_model_outputs(
            &runtime.ctx,
            &mut encoder,
            &neutral,
            &request.normalized_params,
            &request.gate_values,
            &masks,
        )
        .map_err(RenderModelOutputsError::from)?;
    let pending_readback = enqueue_readback(&runtime, &mut encoder, &outputs.final_image)?;
    runtime
        .ctx
        .submit_and_wait(encoder)
        .map_err(RenderModelOutputsError::from)?;

    let final_image = finish_readback(&runtime, pending_readback)?;
    Ok(RenderModelOutputsResponse { final_image })
}

fn validate_render_buffers(
    neutral_image: &RenderBuffer,
    face_mask: Option<&RenderBuffer>,
    person_mask: Option<&RenderBuffer>,
    highlight_mask: Option<&RenderBuffer>,
    shadow_mask: Option<&RenderBuffer>,
    foreground_subject_mask: Option<&RenderBuffer>,
) -> Result<(), RenderModelOutputsError> {
    ensure_color_buffer(neutral_image, "neutral_image")?;
    validate_optional_mask_buffer(face_mask, "face_mask")?;
    validate_optional_mask_buffer(person_mask, "person_mask")?;
    validate_optional_mask_buffer(highlight_mask, "highlight_mask")?;
    validate_optional_mask_buffer(shadow_mask, "shadow_mask")?;
    validate_optional_mask_buffer(foreground_subject_mask, "foreground_subject_mask")?;
    Ok(())
}

fn validate_optional_mask_buffer(
    buffer: Option<&RenderBuffer>,
    label: &str,
) -> Result<(), RenderModelOutputsError> {
    if let Some(buffer) = buffer {
        ensure_mask_buffer(buffer, label)?;
    }

    Ok(())
}

fn runtime_state() -> Result<Arc<RuntimeState>, RenderModelOutputsError> {
    RUNTIME.get_or_try_init(|| {
        init_runtime().map_err(|error| RenderModelOutputsError::RuntimeInit {
            message: format!("failed to create wgpu runtime: {error}"),
        })
    })
}

fn init_runtime() -> Result<RuntimeState, RenderError> {
    let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor::default());
    let adapter = block_on(instance.request_adapter(&wgpu::RequestAdapterOptions::default()))
        .map_err(|error| RenderError::GpuExecution(error.to_string()))?;
    let (device, queue) = block_on(adapter.request_device(&wgpu::DeviceDescriptor::default()))
        .map_err(|error| RenderError::GpuExecution(error.to_string()))?;
    let ctx = RenderContext::new(device, queue, wgpu::TextureFormat::Rgba16Float)?;
    Ok(RuntimeState {
        ctx,
        renderer: Renderer::default(),
        readback_buffers: Mutex::new(ReadbackBufferPool::default()),
        zero_mask_cache: Mutex::new(HashMap::new()),
    })
}

fn ensure_color_buffer(buffer: &RenderBuffer, label: &str) -> Result<(), RenderModelOutputsError> {
    ensure_buffer_layout(buffer, label)?;
    match buffer.format {
        RenderBufferFormat::Rgba8Unorm | RenderBufferFormat::Rgba16Float => Ok(()),
        RenderBufferFormat::R8Unorm => Err(RenderModelOutputsError::InvalidBuffer {
            message: format!("{label} must be RGBA, but got R8Unorm"),
        }),
    }
}

fn resolve_optional_mask(
    runtime: &RuntimeState,
    buffer: Option<&RenderBuffer>,
    zero_mask: Option<&GpuImage>,
    label: &str,
) -> Result<GpuImage, RenderModelOutputsError> {
    match buffer {
        Some(buffer) => upload_render_buffer_validated(&runtime.ctx, buffer, label),
        None => zero_mask
            .cloned()
            .ok_or_else(|| RenderModelOutputsError::RenderFailed {
                message: "missing shared zero mask for optional mask resolution".to_string(),
            }),
    }
}

fn ensure_mask_buffer(buffer: &RenderBuffer, label: &str) -> Result<(), RenderModelOutputsError> {
    ensure_buffer_layout(buffer, label)?;
    if !matches!(buffer.format, RenderBufferFormat::R8Unorm) {
        return Err(RenderModelOutputsError::InvalidBuffer {
            message: format!("{label} must use R8Unorm format"),
        });
    }
    Ok(())
}

fn ensure_buffer_layout(buffer: &RenderBuffer, label: &str) -> Result<(), RenderModelOutputsError> {
    if buffer.width == 0 || buffer.height == 0 {
        return Err(RenderModelOutputsError::InvalidBuffer {
            message: format!("{label} must have non-zero width and height"),
        });
    }

    let bytes_per_pixel = bytes_per_pixel(buffer.format);
    let min_bytes_per_row = buffer.width.checked_mul(bytes_per_pixel).ok_or_else(|| {
        RenderModelOutputsError::InvalidBuffer {
            message: format!("{label} width overflow while computing bytes_per_row"),
        }
    })?;

    if buffer.bytes_per_row < min_bytes_per_row {
        return Err(RenderModelOutputsError::InvalidBuffer {
            message: format!(
                "{label} bytes_per_row too small, expected at least {min_bytes_per_row}, got {}",
                buffer.bytes_per_row
            ),
        });
    }

    let required_len = (buffer.bytes_per_row as usize)
        .checked_mul(buffer.height as usize)
        .ok_or_else(|| RenderModelOutputsError::InvalidBuffer {
            message: format!("{label} buffer length overflow"),
        })?;
    if buffer.data.len() != required_len {
        return Err(RenderModelOutputsError::InvalidBuffer {
            message: format!(
                "{label} data length mismatch, expected {required_len} bytes, got {}",
                buffer.data.len()
            ),
        });
    }

    Ok(())
}

fn upload_render_buffer_validated(
    ctx: &RenderContext,
    buffer: &RenderBuffer,
    label: &str,
) -> Result<GpuImage, RenderModelOutputsError> {
    let format = texture_format(buffer.format);
    let image = ctx.acquire_scratch_image(buffer.width, buffer.height, format, label);

    ctx.queue.write_texture(
        wgpu::TexelCopyTextureInfo {
            texture: &image.texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        &buffer.data,
        wgpu::TexelCopyBufferLayout {
            offset: 0,
            bytes_per_row: Some(buffer.bytes_per_row),
            rows_per_image: Some(buffer.height),
        },
        wgpu::Extent3d {
            width: buffer.width,
            height: buffer.height,
            depth_or_array_layers: 1,
        },
    );
    Ok(image)
}

fn create_zero_mask(
    runtime: &RuntimeState,
    width: u32,
    height: u32,
    label: &str,
) -> Result<GpuImage, RenderModelOutputsError> {
    let mut cache = runtime
        .zero_mask_cache
        .lock()
        .expect("zero mask cache mutex should not be poisoned");
    if let Some(existing) = cache.get(&(width, height)) {
        return Ok(existing.clone());
    }

    let bytes_per_row = width as usize;
    let data = vec![0_u8; bytes_per_row * height as usize];
    let texture = runtime.ctx.device.create_texture(&wgpu::TextureDescriptor {
        label: Some(label),
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::R8Unorm,
        usage: wgpu::TextureUsages::TEXTURE_BINDING
            | wgpu::TextureUsages::RENDER_ATTACHMENT
            | wgpu::TextureUsages::COPY_DST
            | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    runtime.ctx.queue.write_texture(
        wgpu::TexelCopyTextureInfo {
            texture: &texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        &data,
        wgpu::TexelCopyBufferLayout {
            offset: 0,
            bytes_per_row: Some(width),
            rows_per_image: Some(height),
        },
        wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
    );
    let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
    let image = GpuImage::new(
        texture,
        view,
        width,
        height,
        wgpu::TextureFormat::R8Unorm,
        label,
    );
    cache.insert((width, height), image.clone());
    Ok(image)
}

fn enqueue_readback(
    runtime: &RuntimeState,
    encoder: &mut wgpu::CommandEncoder,
    image: &GpuImage,
) -> Result<PendingReadback, RenderModelOutputsError> {
    let format = buffer_format(image.format)?;
    let bytes_per_pixel = bytes_per_pixel(format);
    let tight_bytes_per_row = image.width.checked_mul(bytes_per_pixel).ok_or_else(|| {
        RenderModelOutputsError::RenderFailed {
            message: "final image width overflow while computing bytes_per_row".to_string(),
        }
    })?;
    let padded_bytes_per_row = align_to(tight_bytes_per_row, wgpu::COPY_BYTES_PER_ROW_ALIGNMENT);
    let padded_size = (padded_bytes_per_row as u64)
        .checked_mul(image.height as u64)
        .ok_or_else(|| RenderModelOutputsError::RenderFailed {
            message: "final image readback buffer size overflow".to_string(),
        })?;

    let (readback, pool_index) = acquire_readback_buffer(runtime, padded_size);
    encoder.copy_texture_to_buffer(
        wgpu::TexelCopyTextureInfo {
            texture: &image.texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::TexelCopyBufferInfo {
            buffer: &readback,
            layout: wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(padded_bytes_per_row),
                rows_per_image: Some(image.height),
            },
        },
        wgpu::Extent3d {
            width: image.width,
            height: image.height,
            depth_or_array_layers: 1,
        },
    );

    Ok(PendingReadback {
        buffer: readback,
        pool_index,
        padded_size,
        tight_bytes_per_row,
        padded_bytes_per_row,
        width: image.width,
        height: image.height,
        format,
    })
}

fn finish_readback(
    runtime: &RuntimeState,
    pending: PendingReadback,
) -> Result<RenderBuffer, RenderModelOutputsError> {
    let slice = pending.buffer.slice(..pending.padded_size);
    let (sender, receiver) = mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |result| {
        let _ = sender.send(result);
    });
    runtime
        .ctx
        .device
        .poll(wgpu::PollType::wait_indefinitely())
        .map_err(|error| RenderModelOutputsError::RenderFailed {
            message: format!("failed while waiting for GPU readback: {error}"),
        })?;
    receiver
        .recv()
        .map_err(|error| RenderModelOutputsError::RenderFailed {
            message: format!("failed to receive GPU readback status: {error}"),
        })?
        .map_err(|error| RenderModelOutputsError::RenderFailed {
            message: format!("GPU readback map_async failed: {error}"),
        })?;

    let mapped = slice.get_mapped_range();
    let tight = if pending.padded_bytes_per_row == pending.tight_bytes_per_row {
        mapped.to_vec()
    } else {
        let mut tight =
            vec![0_u8; (pending.tight_bytes_per_row as usize) * pending.height as usize];
        for row in 0..pending.height as usize {
            let src_start = row * pending.padded_bytes_per_row as usize;
            let src_end = src_start + pending.tight_bytes_per_row as usize;
            let dst_start = row * pending.tight_bytes_per_row as usize;
            let dst_end = dst_start + pending.tight_bytes_per_row as usize;
            tight[dst_start..dst_end].copy_from_slice(&mapped[src_start..src_end]);
        }
        tight
    };
    drop(mapped);
    pending.buffer.unmap();
    recycle_readback_buffer(runtime, pending.pool_index);

    Ok(RenderBuffer {
        width: pending.width,
        height: pending.height,
        bytes_per_row: pending.tight_bytes_per_row,
        format: pending.format,
        data: tight,
    })
}

fn acquire_readback_buffer(
    runtime: &RuntimeState,
    required_size: u64,
) -> (Arc<wgpu::Buffer>, usize) {
    let mut pool = runtime
        .readback_buffers
        .lock()
        .expect("readback buffer pool mutex should not be poisoned");

    let index = if let Some((index, entry)) = pool
        .entries
        .iter_mut()
        .enumerate()
        .find(|(_, entry)| !entry.in_use && entry.size >= required_size)
    {
        entry.in_use = true;
        index
    } else {
        let buffer = runtime.ctx.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("render_readback_buffer"),
            size: required_size,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        pool.entries.push(ReadbackBufferEntry {
            buffer: Arc::new(buffer),
            size: required_size,
            in_use: true,
        });
        pool.entries.len() - 1
    };

    let buffer = Arc::clone(&pool.entries[index].buffer);
    (buffer, index)
}

fn recycle_readback_buffer(runtime: &RuntimeState, pool_index: usize) {
    let mut pool = runtime
        .readback_buffers
        .lock()
        .expect("readback buffer pool mutex should not be poisoned");
    if let Some(entry) = pool.entries.get_mut(pool_index) {
        entry.in_use = false;
    }
}

fn texture_format(format: RenderBufferFormat) -> wgpu::TextureFormat {
    match format {
        RenderBufferFormat::Rgba8Unorm => wgpu::TextureFormat::Rgba8Unorm,
        RenderBufferFormat::Rgba16Float => wgpu::TextureFormat::Rgba16Float,
        RenderBufferFormat::R8Unorm => wgpu::TextureFormat::R8Unorm,
    }
}

fn buffer_format(
    format: wgpu::TextureFormat,
) -> Result<RenderBufferFormat, RenderModelOutputsError> {
    match format {
        wgpu::TextureFormat::Rgba8Unorm => Ok(RenderBufferFormat::Rgba8Unorm),
        wgpu::TextureFormat::Rgba16Float => Ok(RenderBufferFormat::Rgba16Float),
        wgpu::TextureFormat::R8Unorm => Ok(RenderBufferFormat::R8Unorm),
        other => Err(RenderModelOutputsError::RenderFailed {
            message: format!("unsupported texture format for readback: {other:?}"),
        }),
    }
}

fn bytes_per_pixel(format: RenderBufferFormat) -> u32 {
    match format {
        RenderBufferFormat::Rgba8Unorm => 4,
        RenderBufferFormat::Rgba16Float => 8,
        RenderBufferFormat::R8Unorm => 1,
    }
}

fn align_to(value: u32, alignment: u32) -> u32 {
    let remainder = value % alignment;
    if remainder == 0 {
        value
    } else {
        value + (alignment - remainder)
    }
}

fn block_on<F: std::future::Future>(future: F) -> F::Output {
    let mut future = std::pin::pin!(future);
    let mut context = Context::from_waker(Waker::noop());

    loop {
        match future.as_mut().poll(&mut context) {
            Poll::Ready(value) => return value,
            Poll::Pending => thread::sleep(Duration::from_millis(1)),
        }
    }
}

impl From<RenderError> for RenderModelOutputsError {
    fn from(value: RenderError) -> Self {
        Self::RenderFailed {
            message: value.to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;

    #[test]
    fn render_with_model_outputs_smoke_runs_when_gpu_is_available() {
        let _guard = crate::test_support::gpu_test_guard();
        let request = RenderModelOutputsRequest {
            neutral_image: solid_rgba8_buffer(4, 4, [96, 104, 112, 255]),
            face_mask: None,
            person_mask: None,
            highlight_mask: None,
            shadow_mask: None,
            foreground_subject_mask: None,
            normalized_params: vec![0.5; crate::PARAMETER_SPECS.len()],
            gate_values: vec![0.0; crate::GATE_NAMES.len()],
        };

        let response = match render_with_model_outputs(request) {
            Ok(response) => response,
            Err(RenderModelOutputsError::RuntimeInit { .. }) => return,
            Err(error) => panic!("render smoke test failed: {error}"),
        };

        assert_eq!(response.final_image.width, 4);
        assert_eq!(response.final_image.height, 4);
        assert!(matches!(
            response.final_image.format,
            RenderBufferFormat::Rgba8Unorm
        ));
    }

    #[test]
    fn accepts_masks_with_different_sizes_when_gpu_is_available() {
        let _guard = crate::test_support::gpu_test_guard();
        let request = RenderModelOutputsRequest {
            neutral_image: solid_rgba8_buffer(4, 4, [96, 104, 112, 255]),
            face_mask: Some(solid_r8_buffer(2, 2, 255)),
            person_mask: Some(solid_r8_buffer(1, 1, 0)),
            highlight_mask: Some(solid_r8_buffer(2, 4, 128)),
            shadow_mask: None,
            foreground_subject_mask: Some(solid_r8_buffer(4, 2, 200)),
            normalized_params: vec![0.5; crate::PARAMETER_SPECS.len()],
            gate_values: vec![0.0; crate::GATE_NAMES.len()],
        };

        let response = match render_with_model_outputs(request) {
            Ok(response) => response,
            Err(RenderModelOutputsError::RuntimeInit { .. }) => return,
            Err(error) => panic!("render with resized masks failed: {error}"),
        };

        assert_eq!(response.final_image.width, 4);
        assert_eq!(response.final_image.height, 4);
    }

    #[test]
    fn rejects_zero_sized_neutral_before_runtime_init() {
        let request = RenderModelOutputsRequest {
            neutral_image: RenderBuffer {
                width: 0,
                height: 4,
                bytes_per_row: 0,
                format: RenderBufferFormat::Rgba8Unorm,
                data: vec![],
            },
            face_mask: None,
            person_mask: None,
            highlight_mask: None,
            shadow_mask: None,
            foreground_subject_mask: None,
            normalized_params: vec![0.5; crate::PARAMETER_SPECS.len()],
            gate_values: vec![0.0; crate::GATE_NAMES.len()],
        };

        let error = render_with_model_outputs(request).unwrap_err();
        assert!(matches!(
            error,
            RenderModelOutputsError::InvalidBuffer { .. }
        ));
        assert!(error
            .to_string()
            .contains("neutral_image must have non-zero width and height"));
    }

    #[test]
    fn runtime_cache_retries_after_failed_init() {
        let cache = RuntimeCache::new();
        let attempts = AtomicUsize::new(0);

        let first = cache.get_or_try_init(|| -> Result<u32, &'static str> {
            let attempt = attempts.fetch_add(1, Ordering::SeqCst);
            if attempt == 0 {
                Err("boom")
            } else {
                Ok(7)
            }
        });
        assert_eq!(first.unwrap_err(), "boom");

        let second = cache
            .get_or_try_init(|| -> Result<u32, &'static str> {
                attempts.fetch_add(1, Ordering::SeqCst);
                Ok(7)
            })
            .unwrap();
        assert_eq!(*second, 7);

        let third = cache
            .get_or_try_init(|| -> Result<u32, &'static str> {
                attempts.fetch_add(1, Ordering::SeqCst);
                Ok(99)
            })
            .unwrap();
        assert_eq!(*third, 7);
        assert_eq!(attempts.load(Ordering::SeqCst), 2);
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

    fn solid_r8_buffer(width: u32, height: u32, value: u8) -> RenderBuffer {
        RenderBuffer {
            width,
            height,
            bytes_per_row: width,
            format: RenderBufferFormat::R8Unorm,
            data: vec![value; (width * height) as usize],
        }
    }
}
