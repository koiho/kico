struct TextureFinishUniform {
  grain_a : vec4<f32>,
  grain_b : vec4<f32>,
  texture : vec4<f32>,
  finish : vec4<f32>,
  scale : vec4<f32>,
};

@group(0) @binding(0) var input_tex : texture_2d<f32>;
@group(0) @binding(1) var input_samp : sampler;
@group(0) @binding(2) var<uniform> u : TextureFinishUniform;

fn luminance(color : vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn texel_size() -> vec2<f32> {
  let dims = vec2<f32>(textureDimensions(input_tex));
  return 1.0 / max(dims, vec2<f32>(1.0, 1.0));
}

fn texture_dims() -> vec2<f32> {
  return max(vec2<f32>(textureDimensions(input_tex)), vec2<f32>(1.0, 1.0));
}

fn hash21(p : vec2<f32>) -> f32 {
  let h = dot(p, vec2<f32>(127.1, 311.7));
  return fract(sin(h) * 43758.5453123);
}

fn hash31(p : vec2<f32>, seed : f32) -> f32 {
  let h = dot(p, vec2<f32>(269.5 + seed * 13.0, 183.3 + seed * 7.0));
  return fract(sin(h) * (43758.5453123 + seed * 97.0));
}

fn soft_clip(color : vec3<f32>, pivot : f32, softness : f32) -> vec3<f32> {
  if softness <= 1e-5 {
    return color;
  }
  let safe_pivot = max(pivot, 1e-4);
  let above = max(color - vec3<f32>(safe_pivot), vec3<f32>(0.0));
  let clipped = vec3<f32>(safe_pivot) + above / (1.0 + above * (0.5 + softness));
  let below = min(color, vec3<f32>(safe_pivot));
  return below + max(clipped - vec3<f32>(safe_pivot), vec3<f32>(0.0));
}

fn sample_color(uv : vec2<f32>, offset : vec2<f32>, scale : f32) -> vec3<f32> {
  let texel = texel_size();
  return textureSample(input_tex, input_samp, uv + offset * texel * scale).rgb;
}

fn edge_aware_blur(uv : vec2<f32>, center : vec3<f32>, scale : f32) -> vec3<f32> {
  let center_luma = luminance(center);
  let offsets = array<vec2<f32>, 16>(
    vec2<f32>(1.0, 0.0),
    vec2<f32>(-1.0, 0.0),
    vec2<f32>(0.0, 1.0),
    vec2<f32>(0.0, -1.0),
    vec2<f32>(1.0, 1.0),
    vec2<f32>(-1.0, 1.0),
    vec2<f32>(1.0, -1.0),
    vec2<f32>(-1.0, -1.0),
    vec2<f32>(2.0, 0.0),
    vec2<f32>(-2.0, 0.0),
    vec2<f32>(0.0, 2.0),
    vec2<f32>(0.0, -2.0),
    vec2<f32>(2.0, 1.0),
    vec2<f32>(-2.0, 1.0),
    vec2<f32>(2.0, -1.0),
    vec2<f32>(-2.0, -1.0),
  );
  let base_weights = array<f32, 16>(
    0.095, 0.095, 0.095, 0.095,
    0.068, 0.068, 0.068, 0.068,
    0.045, 0.045, 0.045, 0.045,
    0.032, 0.032, 0.032, 0.032,
  );

  var accum = center * 0.22;
  var weight_sum = 0.22;
  for (var i = 0u; i < 16u; i = i + 1u) {
    let sample = sample_color(uv, offsets[i], scale);
    let sample_luma = luminance(sample);
    let similarity = exp2(-abs(sample_luma - center_luma) * 6.8);
    let weight = base_weights[i] * similarity;
    accum = accum + sample * weight;
    weight_sum = weight_sum + weight;
  }
  return accum / max(weight_sum, 1e-5);
}

fn grain_cell(uv : vec2<f32>, grain_size : f32, scale : f32, angle : f32) -> vec2<f32> {
  let dims = texture_dims();
  let centered = uv * dims;
  let c = cos(angle);
  let s = sin(angle);
  let rotated = vec2<f32>(
    centered.x * c - centered.y * s,
    centered.x * s + centered.y * c,
  );
  return floor(rotated / max(grain_size * scale, 0.1));
}

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  var color = textureSample(input_tex, input_samp, uv).rgb;

  let grain_luma_amount = u.grain_a.x;
  let grain_chroma_amount = u.grain_a.y;
  let grain_size = max(u.grain_a.z, 0.1);
  let grain_gate = u.grain_a.w;
  let grain_shadow_bias = u.grain_b.x;
  let grain_highlight_suppress = u.grain_b.y;
  let microcontrast_balance = u.grain_b.z;
  let shadow_floor = u.grain_b.w;

  let texture_boost = u.texture.x;
  let noise_clean_bias = u.texture.y;
  let detail_preserve = u.texture.z;
  let texture_gate = u.texture.w;

  let gamut_compress = u.finish.x;
  let final_gamma_bias = max(u.finish.y, 0.05);
  let highlight_clip_softness = u.finish.z;
  let highlight_rolloff_pivot = max(u.finish.w, 0.05);
  let texel_scale = u.scale.x;

  let blur_small = edge_aware_blur(uv, color, 1.0 * texel_scale);
  let blur_large = edge_aware_blur(uv, color, 2.8 * texel_scale);
  let fine_detail = color - blur_small;
  let structure_detail = blur_small - blur_large;
  let fine_micro_weight = 1.0 + max(microcontrast_balance, 0.0) * 0.65;
  let structure_micro_weight = 1.0 + max(-microcontrast_balance, 0.0) * 0.65;

  color = mix(color, blur_small, noise_clean_bias * texture_gate * 0.32);
  color = color + fine_detail * texture_boost * texture_gate * 0.55 * fine_micro_weight;
  color = color + structure_detail * texture_boost * texture_gate * 0.30 * structure_micro_weight;
  color = mix(
    color,
    color + fine_detail * 0.75 * fine_micro_weight + structure_detail * 0.35 * structure_micro_weight,
    detail_preserve * texture_gate * 0.30,
  );

  let grain_uv_fine = grain_cell(uv, grain_size, 1.0, 0.18);
  let grain_uv_mid = grain_cell(uv, grain_size, 1.9, -0.43);
  let grain_uv_coarse = grain_cell(uv, grain_size, 3.2, 0.73);
  let fine_noise = hash21(grain_uv_fine) * 2.0 - 1.0;
  let mid_noise = hash31(grain_uv_mid, 1.7) * 2.0 - 1.0;
  let coarse_noise = hash31(grain_uv_coarse, 3.4) * 2.0 - 1.0;
  let chroma_noise_r = hash31(grain_uv_fine + vec2<f32>(17.0, 3.0), 2.1) * 2.0 - 1.0;
  let chroma_noise_b = hash31(grain_uv_mid + vec2<f32>(5.0, 29.0), 4.2) * 2.0 - 1.0;
  let noise = fine_noise * 0.58 + mid_noise * 0.27 + coarse_noise * 0.15;
  let luma = luminance(color);
  let shadow_weight = mix(1.0, 1.0 + grain_shadow_bias, 1.0 - smoothstep(0.0, 0.5, luma));
  let highlight_weight = 1.0 - grain_highlight_suppress * smoothstep(0.6, 1.0, luma);
  let detail_weight = 1.0 - smoothstep(0.18, 0.9, abs(luminance(fine_detail) + luminance(structure_detail)));
  let grain_weight = grain_gate * shadow_weight * highlight_weight * (0.72 + detail_weight * 0.28);

  color = color + vec3<f32>(noise * grain_luma_amount * 0.08 * grain_weight);
  color.r = color.r + chroma_noise_r * grain_chroma_amount * 0.035 * grain_weight;
  color.b = color.b - chroma_noise_b * grain_chroma_amount * 0.035 * grain_weight;

  color = max(color, vec3<f32>(0.0));
  let finish_luma = luminance(color);
  let chroma = color - vec3<f32>(finish_luma);
  let chroma_extent = max(abs(chroma.r), max(abs(chroma.g), abs(chroma.b)));
  let chroma_scale = 1.0 / (1.0 + gamut_compress * chroma_extent * 1.8);
  color = vec3<f32>(finish_luma) + chroma * chroma_scale;

  color = soft_clip(max(color, vec3<f32>(0.0)), highlight_rolloff_pivot, highlight_clip_softness);

  let luma_after = luminance(max(color, vec3<f32>(0.0)));
  let gamma_luma = pow(max(luma_after, 1e-5), 1.0 / final_gamma_bias);
  let gamma_scale = gamma_luma / max(luma_after, 1e-5);
  color = max(color * gamma_scale, vec3<f32>(shadow_floor));

  return vec4<f32>(max(color, vec3<f32>(0.0)), 1.0);
}
