struct HalationUniform {
  params_a : vec4<f32>,
  params_b : vec4<f32>,
};

@group(0) @binding(0) var input_tex : texture_2d<f32>;
@group(0) @binding(1) var input_samp : sampler;
@group(0) @binding(2) var<uniform> u : HalationUniform;

fn luminance(color : vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn texel_size() -> vec2<f32> {
  let dims = vec2<f32>(textureDimensions(input_tex));
  return 1.0 / max(dims, vec2<f32>(1.0, 1.0));
}

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  let base = textureSample(input_tex, input_samp, uv).rgb;
  let threshold = u.params_a.x;
  let intensity = u.params_a.y;
  let radius = max(u.params_a.z, 0.25);
  let red_bias = u.params_a.w;
  let warmth = u.params_b.x;
  let gate = u.params_b.y;

  let texel = texel_size() * (1.0 + radius * 8.0);
  let offsets = array<vec2<f32>, 8>(
    vec2<f32>(1.5, 0.0),
    vec2<f32>(-1.5, 0.0),
    vec2<f32>(0.0, 1.5),
    vec2<f32>(0.0, -1.5),
    vec2<f32>(2.0, 1.0),
    vec2<f32>(-2.0, 1.0),
    vec2<f32>(2.0, -1.0),
    vec2<f32>(-2.0, -1.0),
  );

  var halo = vec3<f32>(0.0);
  var total = 0.0;
  for (var i = 0u; i < 8u; i = i + 1u) {
    let sample_color = textureSample(input_tex, input_samp, uv + offsets[i] * texel).rgb;
    let w = smoothstep(threshold - 0.05, threshold + 0.05, luminance(sample_color));
    halo = halo + sample_color * w;
    total = total + w;
  }
  halo = halo / max(total, 1e-4);

  let tint = vec3<f32>(0.5 + red_bias * 0.5, 0.15 + warmth * 0.25, 0.05);
  halo = halo * tint;

  let out_color = base + halo * intensity * gate * 0.65;
  return vec4<f32>(out_color, 1.0);
}
