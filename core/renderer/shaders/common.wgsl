struct FullscreenVertexOut {
  @builtin(position) position : vec4<f32>,
  @location(0) uv : vec2<f32>,
};

@vertex
fn vs_fullscreen(@builtin(vertex_index) vertex_index : u32) -> FullscreenVertexOut {
  var positions = array<vec2<f32>, 3>(
    vec2<f32>(-1.0, -3.0),
    vec2<f32>(-1.0, 1.0),
    vec2<f32>(3.0, 1.0),
  );

  var out : FullscreenVertexOut;
  let pos = positions[vertex_index];
  out.position = vec4<f32>(pos, 0.0, 1.0);
  out.uv = pos * 0.5 + vec2<f32>(0.5, 0.5);
  return out;
}

fn sample_linear(
  tex : texture_2d<f32>,
  samp : sampler,
  uv : vec2<f32>,
) -> vec4<f32> {
  return textureSample(tex, samp, uv);
}

fn apply_exposure(color : vec3<f32>, exposure_ev : f32) -> vec3<f32> {
  return color * exp2(exposure_ev);
}

fn blend_masked(
  base : vec3<f32>,
  styled : vec3<f32>,
  mask_value : f32,
  gate : f32,
) -> vec3<f32> {
  let weight = clamp(mask_value * gate, 0.0, 1.0);
  return mix(base, styled, weight);
}
