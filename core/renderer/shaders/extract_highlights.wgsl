struct ExtractHighlightsUniform {
  params_a : vec4<f32>,
  params_b : vec4<f32>,
};

@group(0) @binding(0) var input_tex : texture_2d<f32>;
@group(0) @binding(1) var input_samp : sampler;
@group(0) @binding(2) var<uniform> u : ExtractHighlightsUniform;

fn luminance(color : vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  let color = max(textureSample(input_tex, input_samp, uv).rgb, vec3<f32>(0.0));
  let threshold = u.params_a.x;
  let knee = max(u.params_a.y, 1e-4);
  let gain = max(u.params_a.z, 0.0);
  let luma = luminance(color);
  let soft_weight = smoothstep(threshold - knee, threshold + knee, luma);
  let highlight_excess = max(luma - threshold, 0.0);
  let excess_ratio = highlight_excess / max(luma, 1e-4);
  let residual = color * excess_ratio;
  let shoulder = color * soft_weight * 0.25;
  let extracted = (residual + shoulder) * gain;
  return vec4<f32>(extracted, 1.0);
}
