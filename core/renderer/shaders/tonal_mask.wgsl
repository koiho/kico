struct TonalMaskUniform {
  params : vec4<f32>,
};

@group(0) @binding(0) var input_tex : texture_2d<f32>;
@group(0) @binding(1) var input_samp : sampler;
@group(0) @binding(2) var<uniform> u : TonalMaskUniform;

fn luminance(color : vec3<f32>) -> f32 {
  return dot(max(color, vec3<f32>(0.0)), vec3<f32>(0.2126, 0.7152, 0.0722));
}

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  let color = textureSample(input_tex, input_samp, uv).rgb;
  let mode = u.params.x;
  let threshold = u.params.y;
  let feather = max(u.params.z, 1e-4);
  let strength = max(u.params.w, 0.0);
  let luma = luminance(color);

  let highlight = smoothstep(threshold - feather, threshold + feather, luma);
  let shadow = 1.0 - smoothstep(threshold - feather, threshold + feather, luma);
  let value = clamp(select(highlight, shadow, mode > 0.5) * strength, 0.0, 1.0);
  return vec4<f32>(value, value, value, 1.0);
}
