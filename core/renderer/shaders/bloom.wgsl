struct BloomUniform {
  params : vec4<f32>,
  gate : vec4<f32>,
};

@group(0) @binding(0) var input_tex : texture_2d<f32>;
@group(0) @binding(1) var input_samp : sampler;
@group(0) @binding(2) var<uniform> u : BloomUniform;

fn luminance(color : vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn texel_size() -> vec2<f32> {
  let dims = vec2<f32>(textureDimensions(input_tex));
  return 1.0 / max(dims, vec2<f32>(1.0, 1.0));
}

fn bright_weight(color : vec3<f32>, threshold : f32, softness : f32) -> f32 {
  let luma = luminance(color);
  let edge0 = max(threshold - softness * 0.25, 0.0);
  let edge1 = threshold + softness * 0.25 + 1e-5;
  return smoothstep(edge0, edge1, luma);
}

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  let base = textureSample(input_tex, input_samp, uv).rgb;
  let threshold = u.params.x;
  let intensity = u.params.y;
  let radius = max(u.params.z, 0.25);
  let softness = max(u.params.w, 0.05);
  let gate = u.gate.x;

  let texel = texel_size() * (1.0 + radius * 6.0);
  let offsets = array<vec2<f32>, 9>(
    vec2<f32>(0.0, 0.0),
    vec2<f32>(1.0, 0.0),
    vec2<f32>(-1.0, 0.0),
    vec2<f32>(0.0, 1.0),
    vec2<f32>(0.0, -1.0),
    vec2<f32>(1.0, 1.0),
    vec2<f32>(-1.0, 1.0),
    vec2<f32>(1.0, -1.0),
    vec2<f32>(-1.0, -1.0),
  );
  let weights = array<f32, 9>(0.20, 0.12, 0.12, 0.12, 0.12, 0.08, 0.08, 0.08, 0.08);

  var bloom = vec3<f32>(0.0);
  var total = 0.0;
  for (var i = 0u; i < 9u; i = i + 1u) {
    let sample_color = textureSample(input_tex, input_samp, uv + offsets[i] * texel).rgb;
    let w = weights[i] * bright_weight(sample_color, threshold, softness);
    bloom = bloom + sample_color * w;
    total = total + w;
  }
  bloom = bloom / max(total, 1e-4);

  let out_color = base + bloom * intensity * gate;
  return vec4<f32>(out_color, 1.0);
}
