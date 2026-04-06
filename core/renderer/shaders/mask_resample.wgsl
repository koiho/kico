struct MaskUniform {
  params : vec4<f32>,
};

@group(0) @binding(0) var input_tex : texture_2d<f32>;
@group(0) @binding(1) var input_samp : sampler;
@group(0) @binding(2) var<uniform> u : MaskUniform;

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  let sample_value = textureSample(input_tex, input_samp, uv).r;
  let min_value = u.params.x;
  let max_value = max(u.params.y, min_value + 1e-5);
  let gamma = max(u.params.z, 1e-4);
  let invert = u.params.w;

  var value = clamp((sample_value - min_value) / (max_value - min_value), 0.0, 1.0);
  value = pow(value, gamma);
  if invert > 0.5 {
    value = 1.0 - value;
  }

  return vec4<f32>(value, value, value, 1.0);
}
