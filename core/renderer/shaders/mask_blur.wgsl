struct MaskBlurUniform {
  params : vec4<f32>,
};

@group(0) @binding(0) var input_tex : texture_2d<f32>;
@group(0) @binding(1) var input_samp : sampler;
@group(0) @binding(2) var<uniform> u : MaskBlurUniform;

fn sample_mask(uv : vec2<f32>, offset : vec2<f32>, texel : vec2<f32>) -> f32 {
  return textureSample(input_tex, input_samp, uv + offset * texel).r;
}

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  let dims = max(vec2<f32>(textureDimensions(input_tex)), vec2<f32>(1.0, 1.0));
  let texel = 1.0 / dims;
  let radius = max(u.params.x, 0.0);

  if radius < 0.01 {
    let passthrough = textureSample(input_tex, input_samp, uv).r;
    return vec4<f32>(passthrough, passthrough, passthrough, 1.0);
  }

  let offsets = array<vec2<f32>, 8>(
    vec2<f32>(1.0, 0.0),
    vec2<f32>(-1.0, 0.0),
    vec2<f32>(0.0, 1.0),
    vec2<f32>(0.0, -1.0),
    vec2<f32>(1.0, 1.0),
    vec2<f32>(-1.0, 1.0),
    vec2<f32>(1.0, -1.0),
    vec2<f32>(-1.0, -1.0),
  );
  let weights = array<f32, 8>(0.14, 0.14, 0.14, 0.14, 0.075, 0.075, 0.075, 0.075);

  var accum = textureSample(input_tex, input_samp, uv).r * 0.14;
  var weight_sum = 0.14;
  for (var i = 0u; i < 8u; i = i + 1u) {
    let value = sample_mask(uv, offsets[i] * radius, texel);
    accum = accum + value * weights[i];
    weight_sum = weight_sum + weights[i];
  }

  let blurred = clamp(accum / max(weight_sum, 1e-5), 0.0, 1.0);
  return vec4<f32>(blurred, blurred, blurred, 1.0);
}
