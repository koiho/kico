struct ExposureWbToneUniform {
  exposure_wb : vec4<f32>,
  tone_a : vec4<f32>,
  tone_b : vec4<f32>,
  tone_c : vec4<f32>,
};

@group(0) @binding(0) var input_tex : texture_2d<f32>;
@group(0) @binding(1) var input_samp : sampler;
@group(0) @binding(2) var<uniform> u : ExposureWbToneUniform;

fn luminance(color : vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn safe_color(color : vec3<f32>) -> vec3<f32> {
  return max(color, vec3<f32>(0.0));
}

fn sample_offset(uv : vec2<f32>, offset : vec2<f32>) -> vec3<f32> {
  let dims = vec2<f32>(textureDimensions(input_tex));
  let texel = 1.0 / max(dims, vec2<f32>(1.0, 1.0));
  return textureSample(input_tex, input_samp, uv + offset * texel).rgb;
}

fn edge_aware_blur(uv : vec2<f32>, center : vec3<f32>, scale : f32) -> vec3<f32> {
  let center_luma = luminance(center);
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
  let base_weights = array<f32, 8>(0.12, 0.12, 0.12, 0.12, 0.07, 0.07, 0.07, 0.07);

  var accum = center * 0.24;
  var weight_sum = 0.24;
  for (var i = 0u; i < 8u; i = i + 1u) {
    let sample_color = sample_offset(uv, offsets[i] * scale);
    let sample_luma = luminance(sample_color);
    let similarity = exp2(-abs(sample_luma - center_luma) * 10.0);
    let weight = base_weights[i] * similarity;
    accum = accum + sample_color * weight;
    weight_sum = weight_sum + weight;
  }

  return accum / max(weight_sum, 1e-4);
}

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  var color = textureSample(input_tex, input_samp, uv).rgb;

  let exposure_ev = u.exposure_wb.x;
  let wb_r_gain = u.exposure_wb.y;
  let wb_b_gain = u.exposure_wb.z;
  let contrast = u.exposure_wb.w;
  let contrast_pivot = u.tone_a.x;
  let blacks = u.tone_a.y;
  let whites = u.tone_a.z;
  let shadows = u.tone_a.w;
  let highlights = u.tone_b.x;
  let toe_strength = u.tone_b.y;
  let shoulder_strength = u.tone_b.z;
  let fade = u.tone_b.w;
  let midtone_boost = u.tone_c.x;
  let clarity_global = u.tone_c.y;
  let texel_scale = u.tone_c.z;

  color = color * exp2(exposure_ev);
  color.r = color.r * wb_r_gain;
  color.b = color.b * wb_b_gain;
  color = safe_color(color);

  color = (color - vec3<f32>(contrast_pivot)) * (1.0 + contrast) + vec3<f32>(contrast_pivot);

  let luma = luminance(color);
  let shadow_w = 1.0 - smoothstep(0.05, 0.45, luma);
  let highlight_w = smoothstep(0.55, 0.95, luma);
  let black_w = 1.0 - smoothstep(0.0, 0.25, luma);
  let white_w = smoothstep(0.75, 1.0, luma);

  color = color + vec3<f32>(shadows * shadow_w * 0.25);
  color = color + vec3<f32>(highlights * highlight_w * 0.25);
  color = color + vec3<f32>(blacks * black_w * 0.18);
  color = color + vec3<f32>(whites * white_w * 0.18);
  color = safe_color(color);

  let toe_color = pow(safe_color(color), vec3<f32>(1.0 + toe_strength * shadow_w));
  let shoulder_input = safe_color(color);
  let shoulder_excess = max(shoulder_input - vec3<f32>(1.0), vec3<f32>(0.0));
  let shoulder_color = shoulder_input / (
    vec3<f32>(1.0) + shoulder_excess * (0.5 + shoulder_strength * highlight_w * 1.5)
  );
  color = mix(color, toe_color, toe_strength * shadow_w);
  color = mix(color, shoulder_color, shoulder_strength * highlight_w);

  let mid_w = smoothstep(0.2, 0.5, luma) * (1.0 - smoothstep(0.5, 0.85, luma));
  color = color * (1.0 + midtone_boost * mid_w * 0.25);

  let floor_value = fade * 0.18;
  color = max(color, vec3<f32>(floor_value));

  let blur = edge_aware_blur(uv, color, texel_scale);
  let detail = color - blur;
  let clarity_weight = mid_w * (1.0 - highlight_w * 0.55);
  color = color + detail * clarity_global * clarity_weight * 0.85;
  color = safe_color(color);

  return vec4<f32>(color, 1.0);
}
