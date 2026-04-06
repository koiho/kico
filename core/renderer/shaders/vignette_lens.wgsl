struct VignetteLensUniform {
  vignette : vec4<f32>,
  lens : vec4<f32>,
  scale : vec4<f32>,
};

@group(0) @binding(0) var input_tex : texture_2d<f32>;
@group(0) @binding(1) var input_samp : sampler;
@group(0) @binding(2) var<uniform> u : VignetteLensUniform;

fn texel_size() -> vec2<f32> {
  let dims = vec2<f32>(textureDimensions(input_tex));
  return 1.0 / max(dims, vec2<f32>(1.0, 1.0));
}

fn luminance(color : vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn highlight_glow_sample(uv : vec2<f32>, texel : vec2<f32>, stretch : vec2<f32>) -> vec3<f32> {
  let offsets = array<vec2<f32>, 20>(
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
    vec2<f32>(1.0, 2.0),
    vec2<f32>(-1.0, 2.0),
    vec2<f32>(1.0, -2.0),
    vec2<f32>(-1.0, -2.0),
  );
  let weights = array<f32, 20>(
    0.095, 0.095, 0.09, 0.09,
    0.072, 0.072, 0.072, 0.072,
    0.05, 0.05, 0.047, 0.047,
    0.036, 0.036, 0.036, 0.036,
    0.031, 0.031, 0.031, 0.031,
  );

  let center = textureSample(input_tex, input_samp, uv).rgb;
  var accum = center * 0.14;
  var weight_sum = 0.14;
  for (var i = 0u; i < 20u; i = i + 1u) {
    let sample_color = textureSample(input_tex, input_samp, uv + offsets[i] * texel * stretch).rgb;
    let glow_mask = smoothstep(0.45, 1.15, luminance(sample_color));
    let weight = weights[i] * glow_mask;
    accum = accum + sample_color * weight;
    weight_sum = weight_sum + weight;
  }

  return accum / max(weight_sum, 1e-5);
}

fn edge_softness_sample(uv : vec2<f32>, texel : vec2<f32>, stretch : vec2<f32>) -> vec3<f32> {
  let offsets = array<vec2<f32>, 20>(
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
    vec2<f32>(1.0, 2.0),
    vec2<f32>(-1.0, 2.0),
    vec2<f32>(1.0, -2.0),
    vec2<f32>(-1.0, -2.0),
  );
  let weights = array<f32, 20>(
    0.09, 0.09, 0.086, 0.086,
    0.07, 0.07, 0.07, 0.07,
    0.05, 0.05, 0.046, 0.046,
    0.034, 0.034, 0.034, 0.034,
    0.029, 0.029, 0.029, 0.029,
  );

  let center = textureSample(input_tex, input_samp, uv).rgb;
  let center_luma = luminance(center);
  var accum = vec3<f32>(0.0);
  var weight_sum = 0.0;
  for (var i = 0u; i < 20u; i = i + 1u) {
    let sample_color = textureSample(input_tex, input_samp, uv + offsets[i] * texel * stretch).rgb;
    let sample_luma = luminance(sample_color);
    let similarity = exp2(-abs(sample_luma - center_luma) * 4.2);
    let weight = weights[i] * similarity;
    accum = accum + sample_color * weight;
    weight_sum = weight_sum + weight;
  }

  return (center * 0.18 + accum) / max(0.18 + weight_sum, 1e-5);
}

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  var color = textureSample(input_tex, input_samp, uv).rgb;

  let amount = u.vignette.x;
  let midpoint = u.vignette.y;
  let feather = max(u.vignette.z, 0.01);
  let roundness = u.vignette.w;
  let soft_glow = u.lens.x;
  let edge_softness = u.lens.y;
  let vignette_gate = u.lens.z;
  let lens_gate = u.lens.w;
  let texel_scale = u.scale.x;

  let centered = uv * 2.0 - vec2<f32>(1.0, 1.0);
  let vignette_scale = vec2<f32>(mix(1.0, 1.4, max(roundness, 0.0)), mix(1.0, 1.4, max(-roundness, 0.0)));
  let dist = length(centered * vignette_scale);
  let vignette_w = smoothstep(midpoint, midpoint + feather, dist);
  color = color * (1.0 - amount * vignette_gate * vignette_w);

  let texel = texel_size();
  let highlight_weight = smoothstep(0.45, 1.2, luminance(color));
  let center_glow = highlight_glow_sample(uv, texel, vec2<f32>(1.0, 1.0) * texel_scale);
  let edge_blur = edge_softness_sample(uv, texel, vec2<f32>(2.0, 1.4) * texel_scale);
  color = mix(color, center_glow, soft_glow * lens_gate * highlight_weight * 0.42);

  let edge_factor = smoothstep(0.45, 1.0, dist);
  let edge_mix = edge_softness * lens_gate * edge_factor * (0.45 + 0.35 * (1.0 - highlight_weight * 0.5));
  color = mix(color, edge_blur, edge_mix);

  return vec4<f32>(max(color, vec3<f32>(0.0)), 1.0);
}
