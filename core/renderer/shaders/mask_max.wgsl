struct MaskMaxUniform {
  params : vec4<f32>,
};

@group(0) @binding(0) var base_tex : texture_2d<f32>;
@group(0) @binding(1) var base_samp : sampler;
@group(0) @binding(2) var effect_tex : texture_2d<f32>;
@group(0) @binding(3) var effect_samp : sampler;
@group(0) @binding(4) var<uniform> u : MaskMaxUniform;

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  let base_value = textureSample(base_tex, base_samp, uv).r;
  let effect_value = textureSample(effect_tex, effect_samp, uv).r;
  let value = clamp(max(base_value, effect_value) * max(u.params.x, 0.0), 0.0, 1.0);
  return vec4<f32>(value, value, value, 1.0);
}
