use std::{
    collections::HashMap,
    hash::{Hash, Hasher},
    sync::{Arc, Mutex},
};

use crate::api::{
    error::{RenderError, RenderResult},
    types::{make_recycle_token, GpuImage},
};
use crate::pipeline::shader_sources::COMMON_WGSL;

pub struct RenderContext {
    pub device: wgpu::Device,
    pub queue: wgpu::Queue,
    pub working_format: wgpu::TextureFormat,
    pipeline_cache: Mutex<HashMap<PipelineCacheKey, wgpu::RenderPipeline>>,
    bind_group_layout_cache: Mutex<HashMap<PipelineLayoutKind, wgpu::BindGroupLayout>>,
    bind_group_cache: Mutex<HashMap<BindGroupCacheKey, wgpu::BindGroup>>,
    linear_sampler: Mutex<Option<wgpu::Sampler>>,
    scratch_pool: Arc<Mutex<ScratchTexturePool>>,
    uniform_buffer_pool: Arc<Mutex<UniformBufferPool>>,
}

impl RenderContext {
    pub fn new(
        device: wgpu::Device,
        queue: wgpu::Queue,
        working_format: wgpu::TextureFormat,
    ) -> RenderResult<Self> {
        Ok(Self {
            device,
            queue,
            working_format,
            pipeline_cache: Mutex::new(HashMap::new()),
            bind_group_layout_cache: Mutex::new(HashMap::new()),
            bind_group_cache: Mutex::new(HashMap::new()),
            linear_sampler: Mutex::new(None),
            scratch_pool: Arc::new(Mutex::new(ScratchTexturePool::default())),
            uniform_buffer_pool: Arc::new(Mutex::new(UniformBufferPool::default())),
        })
    }

    pub fn validate_image(&self, image: &GpuImage) -> RenderResult<()> {
        if image.width == 0 || image.height == 0 {
            return Err(RenderError::SizeMismatch {
                expected_width: 1,
                expected_height: 1,
                actual_width: image.width,
                actual_height: image.height,
            });
        }
        Ok(())
    }

    pub fn create_encoder(&self, label: &str) -> wgpu::CommandEncoder {
        self.device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) })
    }

    pub fn submit_and_wait(&self, encoder: wgpu::CommandEncoder) -> RenderResult<()> {
        self.queue.submit(Some(encoder.finish()));
        self.device
            .poll(wgpu::PollType::wait_indefinitely())
            .map_err(|err| RenderError::GpuExecution(err.to_string()))?;
        self.reset_transient_pools();
        Ok(())
    }

    pub fn get_or_create_bind_group_layout(
        &self,
        kind: PipelineLayoutKind,
        label: &str,
    ) -> wgpu::BindGroupLayout {
        let mut cache = self
            .bind_group_layout_cache
            .lock()
            .expect("bind group layout cache mutex should not be poisoned");

        if let Some(layout) = cache.get(&kind) {
            return layout.clone();
        }

        let layout = self
            .device
            .create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some(&format!("{label}_bgl")),
                entries: kind.bind_group_entries(),
            });
        cache.insert(kind, layout.clone());
        layout
    }

    pub fn get_or_create_render_pipeline(
        &self,
        kind: PipelineLayoutKind,
        format: wgpu::TextureFormat,
        shader_source: &str,
        label: &str,
    ) -> wgpu::RenderPipeline {
        let key = PipelineCacheKey::new(kind, format, shader_source);
        let mut cache = self
            .pipeline_cache
            .lock()
            .expect("pipeline cache mutex should not be poisoned");

        if let Some(pipeline) = cache.get(&key) {
            return pipeline.clone();
        }

        let shader = self
            .device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some(label),
                source: wgpu::ShaderSource::Wgsl(shader_source.into()),
            });
        let bind_group_layout = self.get_or_create_bind_group_layout(kind, label);
        let pipeline_layout = self
            .device
            .create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some(&format!("{label}_pipeline_layout")),
                bind_group_layouts: &[&bind_group_layout],
                immediate_size: 0,
            });
        let pipeline = self
            .device
            .create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some(label),
                layout: Some(&pipeline_layout),
                vertex: wgpu::VertexState {
                    module: &shader,
                    entry_point: Some("vs_fullscreen"),
                    buffers: &[],
                    compilation_options: Default::default(),
                },
                fragment: Some(wgpu::FragmentState {
                    module: &shader,
                    entry_point: Some("fs_main"),
                    targets: &[Some(wgpu::ColorTargetState {
                        format,
                        blend: Some(wgpu::BlendState::REPLACE),
                        write_mask: wgpu::ColorWrites::ALL,
                    })],
                    compilation_options: Default::default(),
                }),
                primitive: wgpu::PrimitiveState::default(),
                depth_stencil: None,
                multisample: wgpu::MultisampleState::default(),
                multiview_mask: None,
                cache: None,
            });

        cache.insert(key, pipeline.clone());
        pipeline
    }

    pub fn get_or_create_render_pipeline_with_common(
        &self,
        kind: PipelineLayoutKind,
        format: wgpu::TextureFormat,
        shader_source: &'static str,
        label: &str,
    ) -> wgpu::RenderPipeline {
        let key = PipelineCacheKey::new_static(kind, format, shader_source, true);
        let mut cache = self
            .pipeline_cache
            .lock()
            .expect("pipeline cache mutex should not be poisoned");

        if let Some(pipeline) = cache.get(&key) {
            return pipeline.clone();
        }

        let combined_shader = format!("{COMMON_WGSL}\n{shader_source}");
        let shader = self
            .device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some(label),
                source: wgpu::ShaderSource::Wgsl(combined_shader.into()),
            });
        let bind_group_layout = self.get_or_create_bind_group_layout(kind, label);
        let pipeline_layout = self
            .device
            .create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some(&format!("{label}_pipeline_layout")),
                bind_group_layouts: &[&bind_group_layout],
                immediate_size: 0,
            });
        let pipeline = self
            .device
            .create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some(label),
                layout: Some(&pipeline_layout),
                vertex: wgpu::VertexState {
                    module: &shader,
                    entry_point: Some("vs_fullscreen"),
                    buffers: &[],
                    compilation_options: Default::default(),
                },
                fragment: Some(wgpu::FragmentState {
                    module: &shader,
                    entry_point: Some("fs_main"),
                    targets: &[Some(wgpu::ColorTargetState {
                        format,
                        blend: Some(wgpu::BlendState::REPLACE),
                        write_mask: wgpu::ColorWrites::ALL,
                    })],
                    compilation_options: Default::default(),
                }),
                primitive: wgpu::PrimitiveState::default(),
                depth_stencil: None,
                multisample: wgpu::MultisampleState::default(),
                multiview_mask: None,
                cache: None,
            });

        cache.insert(key, pipeline.clone());
        pipeline
    }

    pub fn get_or_create_linear_sampler(&self, label: &str) -> wgpu::Sampler {
        let mut sampler = self
            .linear_sampler
            .lock()
            .expect("sampler cache mutex should not be poisoned");

        if let Some(existing) = sampler.as_ref() {
            return existing.clone();
        }

        let created = self.device.create_sampler(&wgpu::SamplerDescriptor {
            label: Some(&format!("{label}_sampler")),
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            mipmap_filter: wgpu::MipmapFilterMode::Linear,
            ..Default::default()
        });
        *sampler = Some(created.clone());
        created
    }

    pub(crate) fn get_or_create_basic_bind_group(
        &self,
        input: &GpuImage,
        uniform_buffer: &Arc<wgpu::Buffer>,
        label: &str,
    ) -> wgpu::BindGroup {
        let key = BindGroupCacheKey::Basic {
            input_view: texture_view_id(input),
            uniform_buffer: buffer_id(uniform_buffer),
        };
        let mut cache = self
            .bind_group_cache
            .lock()
            .expect("bind group cache mutex should not be poisoned");

        if let Some(bind_group) = cache.get(&key) {
            return bind_group.clone();
        }

        let bind_group_layout =
            self.get_or_create_bind_group_layout(PipelineLayoutKind::Basic, label);
        let sampler = self.get_or_create_linear_sampler(label);
        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some(&format!("{label}_bg")),
            layout: &bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&input.view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&sampler),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: uniform_buffer.as_entire_binding(),
                },
            ],
        });
        cache.insert(key, bind_group.clone());
        bind_group
    }

    pub(crate) fn get_or_create_dual_texture_bind_group(
        &self,
        base: &GpuImage,
        effect: &GpuImage,
        uniform_buffer: &Arc<wgpu::Buffer>,
        label: &str,
    ) -> wgpu::BindGroup {
        let key = BindGroupCacheKey::DualTexture {
            base_view: texture_view_id(base),
            effect_view: texture_view_id(effect),
            uniform_buffer: buffer_id(uniform_buffer),
        };
        let mut cache = self
            .bind_group_cache
            .lock()
            .expect("bind group cache mutex should not be poisoned");

        if let Some(bind_group) = cache.get(&key) {
            return bind_group.clone();
        }

        let bind_group_layout =
            self.get_or_create_bind_group_layout(PipelineLayoutKind::DualTexture, label);
        let sampler = self.get_or_create_linear_sampler(label);
        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some(&format!("{label}_bg")),
            layout: &bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&base.view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&sampler),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: wgpu::BindingResource::TextureView(&effect.view),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: wgpu::BindingResource::Sampler(&sampler),
                },
                wgpu::BindGroupEntry {
                    binding: 4,
                    resource: uniform_buffer.as_entire_binding(),
                },
            ],
        });
        cache.insert(key, bind_group.clone());
        bind_group
    }

    pub(crate) fn get_or_create_masked_bind_group(
        &self,
        input: &GpuImage,
        face: &GpuImage,
        person: &GpuImage,
        highlight: &GpuImage,
        shadow: &GpuImage,
        foreground_subject: &GpuImage,
        uniform_buffer: &Arc<wgpu::Buffer>,
        label: &str,
    ) -> wgpu::BindGroup {
        let key = BindGroupCacheKey::Masked {
            input_view: texture_view_id(input),
            face_view: texture_view_id(face),
            person_view: texture_view_id(person),
            highlight_view: texture_view_id(highlight),
            shadow_view: texture_view_id(shadow),
            foreground_subject_view: texture_view_id(foreground_subject),
            uniform_buffer: buffer_id(uniform_buffer),
        };
        let mut cache = self
            .bind_group_cache
            .lock()
            .expect("bind group cache mutex should not be poisoned");

        if let Some(bind_group) = cache.get(&key) {
            return bind_group.clone();
        }

        let bind_group_layout =
            self.get_or_create_bind_group_layout(PipelineLayoutKind::Masked, label);
        let sampler = self.get_or_create_linear_sampler(label);
        let bind_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some(&format!("{label}_bg")),
            layout: &bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(&input.view),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: wgpu::BindingResource::Sampler(&sampler),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: wgpu::BindingResource::TextureView(&face.view),
                },
                wgpu::BindGroupEntry {
                    binding: 3,
                    resource: wgpu::BindingResource::TextureView(&person.view),
                },
                wgpu::BindGroupEntry {
                    binding: 4,
                    resource: wgpu::BindingResource::TextureView(&highlight.view),
                },
                wgpu::BindGroupEntry {
                    binding: 5,
                    resource: wgpu::BindingResource::TextureView(&shadow.view),
                },
                wgpu::BindGroupEntry {
                    binding: 6,
                    resource: wgpu::BindingResource::TextureView(&foreground_subject.view),
                },
                wgpu::BindGroupEntry {
                    binding: 7,
                    resource: wgpu::BindingResource::Sampler(&sampler),
                },
                wgpu::BindGroupEntry {
                    binding: 8,
                    resource: uniform_buffer.as_entire_binding(),
                },
            ],
        });
        cache.insert(key, bind_group.clone());
        bind_group
    }

    pub(crate) fn acquire_scratch_image(
        &self,
        width: u32,
        height: u32,
        format: wgpu::TextureFormat,
        label: &str,
    ) -> GpuImage {
        let mut pool = self
            .scratch_pool
            .lock()
            .expect("scratch pool mutex should not be poisoned");

        let index = if let Some((index, entry)) =
            pool.entries.iter_mut().enumerate().find(|(_, entry)| {
                !entry.in_use
                    && entry.width == width
                    && entry.height == height
                    && entry.format == format
            }) {
            entry.in_use = true;
            index
        } else {
            let texture = self.device.create_texture(&wgpu::TextureDescriptor {
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
                    | wgpu::TextureUsages::COPY_SRC
                    | wgpu::TextureUsages::COPY_DST,
                view_formats: &[],
            });
            let view = texture.create_view(&wgpu::TextureViewDescriptor::default());
            pool.entries.push(ScratchTextureEntry {
                texture: Arc::new(texture),
                view: Arc::new(view),
                width,
                height,
                format,
                in_use: true,
            });
            pool.entries.len() - 1
        };

        let entry = &pool.entries[index];
        let texture = entry.texture.clone();
        let view = entry.view.clone();
        drop(pool);

        let scratch_pool = Arc::clone(&self.scratch_pool);
        let recycle_token = make_recycle_token(move || {
            let mut pool = scratch_pool
                .lock()
                .expect("scratch pool mutex should not be poisoned");
            if let Some(entry) = pool.entries.get_mut(index) {
                entry.in_use = false;
            }
        });

        GpuImage::from_shared(
            texture,
            view,
            width,
            height,
            format,
            label,
            Some(recycle_token),
        )
    }

    pub(crate) fn acquire_uniform_buffer(&self, size: usize, label: &str) -> PooledUniformBuffer {
        let mut pool = self
            .uniform_buffer_pool
            .lock()
            .expect("uniform buffer pool mutex should not be poisoned");

        let index = if let Some((index, entry)) = pool
            .entries
            .iter_mut()
            .enumerate()
            .find(|(_, entry)| !entry.in_use && entry.size >= size)
        {
            entry.in_use = true;
            index
        } else {
            let buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(&format!("{label}_uniforms")),
                size: size as u64,
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
            pool.entries.push(UniformBufferEntry {
                buffer: Arc::new(buffer),
                size,
                in_use: true,
            });
            pool.entries.len() - 1
        };

        let entry = &pool.entries[index];
        let buffer = entry.buffer.clone();
        drop(pool);

        PooledUniformBuffer { buffer }
    }

    fn reset_transient_pools(&self) {
        self.bind_group_cache
            .lock()
            .expect("bind group cache mutex should not be poisoned")
            .clear();

        let mut pool = self
            .uniform_buffer_pool
            .lock()
            .expect("uniform buffer pool mutex should not be poisoned");
        for entry in &mut pool.entries {
            entry.in_use = false;
        }
    }

    pub fn trim_unused_scratch_images(&self) {
        let mut pool = self
            .scratch_pool
            .lock()
            .expect("scratch pool mutex should not be poisoned");
        if pool.entries.len() <= 1 {
            return;
        }

        let mut retained = Vec::with_capacity(pool.entries.len());
        let mut seen = HashMap::<(u32, u32, wgpu::TextureFormat), ()>::new();

        for entry in pool.entries.drain(..).rev() {
            if entry.in_use {
                retained.push(entry);
                continue;
            }

            let key = (entry.width, entry.height, entry.format);
            if seen.insert(key, ()).is_none() {
                retained.push(entry);
            }
        }

        retained.reverse();
        pool.entries = retained;
    }

    #[cfg(test)]
    pub(crate) fn scratch_pool_size(&self) -> usize {
        self.scratch_pool
            .lock()
            .expect("scratch pool mutex should not be poisoned")
            .entries
            .len()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum PipelineLayoutKind {
    Basic,
    DualTexture,
    Masked,
}

impl PipelineLayoutKind {
    fn bind_group_entries(&self) -> &'static [wgpu::BindGroupLayoutEntry] {
        match self {
            Self::Basic => &BASIC_BIND_GROUP_ENTRIES,
            Self::DualTexture => &DUAL_TEXTURE_BIND_GROUP_ENTRIES,
            Self::Masked => &MASKED_BIND_GROUP_ENTRIES,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct PipelineCacheKey {
    kind: PipelineLayoutKind,
    format: wgpu::TextureFormat,
    shader_hash: u64,
}

impl PipelineCacheKey {
    fn new(kind: PipelineLayoutKind, format: wgpu::TextureFormat, shader_source: &str) -> Self {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        shader_source.hash(&mut hasher);
        Self {
            kind,
            format,
            shader_hash: hasher.finish(),
        }
    }

    fn new_static(
        kind: PipelineLayoutKind,
        format: wgpu::TextureFormat,
        shader_source: &'static str,
        includes_common: bool,
    ) -> Self {
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        shader_source.as_ptr().hash(&mut hasher);
        shader_source.len().hash(&mut hasher);
        includes_common.hash(&mut hasher);
        Self {
            kind,
            format,
            shader_hash: hasher.finish(),
        }
    }
}

impl Hash for PipelineCacheKey {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.kind.hash(state);
        self.format.hash(state);
        self.shader_hash.hash(state);
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
enum BindGroupCacheKey {
    Basic {
        input_view: usize,
        uniform_buffer: usize,
    },
    DualTexture {
        base_view: usize,
        effect_view: usize,
        uniform_buffer: usize,
    },
    Masked {
        input_view: usize,
        face_view: usize,
        person_view: usize,
        highlight_view: usize,
        shadow_view: usize,
        foreground_subject_view: usize,
        uniform_buffer: usize,
    },
}

fn texture_view_id(image: &GpuImage) -> usize {
    Arc::as_ptr(&image.view) as usize
}

fn buffer_id(buffer: &Arc<wgpu::Buffer>) -> usize {
    Arc::as_ptr(buffer) as usize
}

#[derive(Debug, Default)]
struct ScratchTexturePool {
    entries: Vec<ScratchTextureEntry>,
}

#[derive(Default)]
struct UniformBufferPool {
    entries: Vec<UniformBufferEntry>,
}

struct UniformBufferEntry {
    buffer: Arc<wgpu::Buffer>,
    size: usize,
    in_use: bool,
}

pub(crate) struct PooledUniformBuffer {
    pub buffer: Arc<wgpu::Buffer>,
}

#[derive(Debug)]
struct ScratchTextureEntry {
    texture: Arc<wgpu::Texture>,
    view: Arc<wgpu::TextureView>,
    width: u32,
    height: u32,
    format: wgpu::TextureFormat,
    in_use: bool,
}

const fn texture_binding_layout(binding: u32) -> wgpu::BindGroupLayoutEntry {
    wgpu::BindGroupLayoutEntry {
        binding,
        visibility: wgpu::ShaderStages::FRAGMENT,
        ty: wgpu::BindingType::Texture {
            sample_type: wgpu::TextureSampleType::Float { filterable: true },
            view_dimension: wgpu::TextureViewDimension::D2,
            multisampled: false,
        },
        count: None,
    }
}

const fn sampler_binding_layout(binding: u32) -> wgpu::BindGroupLayoutEntry {
    wgpu::BindGroupLayoutEntry {
        binding,
        visibility: wgpu::ShaderStages::FRAGMENT,
        ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
        count: None,
    }
}

const fn uniform_binding_layout(binding: u32) -> wgpu::BindGroupLayoutEntry {
    wgpu::BindGroupLayoutEntry {
        binding,
        visibility: wgpu::ShaderStages::FRAGMENT,
        ty: wgpu::BindingType::Buffer {
            ty: wgpu::BufferBindingType::Uniform,
            has_dynamic_offset: false,
            min_binding_size: None,
        },
        count: None,
    }
}

const BASIC_BIND_GROUP_ENTRIES: [wgpu::BindGroupLayoutEntry; 3] = [
    texture_binding_layout(0),
    sampler_binding_layout(1),
    uniform_binding_layout(2),
];

const DUAL_TEXTURE_BIND_GROUP_ENTRIES: [wgpu::BindGroupLayoutEntry; 5] = [
    texture_binding_layout(0),
    sampler_binding_layout(1),
    texture_binding_layout(2),
    sampler_binding_layout(3),
    uniform_binding_layout(4),
];

const MASKED_BIND_GROUP_ENTRIES: [wgpu::BindGroupLayoutEntry; 9] = [
    texture_binding_layout(0),
    sampler_binding_layout(1),
    texture_binding_layout(2),
    texture_binding_layout(3),
    texture_binding_layout(4),
    texture_binding_layout(5),
    texture_binding_layout(6),
    sampler_binding_layout(7),
    uniform_binding_layout(8),
];
