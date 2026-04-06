struct HalationSourceUniform {
  params : vec4<f32>,
};

@group(0) @binding(0) var input_tex : texture_2d<f32>;
@group(0) @binding(1) var input_samp : sampler;
@group(0) @binding(2) var<uniform> u : HalationSourceUniform;

fn luminance(color : vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  let source = max(textureSample(input_tex, input_samp, uv).rgb, vec3<f32>(0.0));
  let red_bias = max(u.params.x, 0.0);
  let warmth = max(u.params.y, 0.0);
  let luma = luminance(source);
  let source_mask = smoothstep(0.01, 0.16, luma);

  let red_focus = max(source.r - max(source.g, source.b) * 0.35, 0.0);
  let warm_focus = max((source.r + source.g) * 0.5 - source.b * 0.2, 0.0);

  let shaped_r = source.r * (0.85 + red_bias * 0.55) + red_focus * (0.35 + red_bias * 0.45);
  let shaped_g = source.g * (0.08 + warmth * 0.22) + warm_focus * (0.05 + warmth * 0.10);
  let shaped_b = source.b * 0.02;

  let shaped = vec3<f32>(shaped_r, shaped_g, shaped_b) * source_mask;
  return vec4<f32>(shaped, 1.0);
}
