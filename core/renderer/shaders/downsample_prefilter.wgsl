struct DownsamplePrefilterUniform {
  params : vec4<f32>,
};

@group(0) @binding(0) var input_tex : texture_2d<f32>;
@group(0) @binding(1) var input_samp : sampler;
@group(0) @binding(2) var<uniform> u : DownsamplePrefilterUniform;

fn texel_size() -> vec2<f32> {
  let dims = vec2<f32>(textureDimensions(input_tex));
  return 1.0 / max(dims, vec2<f32>(1.0, 1.0));
}

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  let texel = texel_size();
  let center = textureSample(input_tex, input_samp, uv).rgb * 0.1;
  let cross =
      (textureSample(input_tex, input_samp, uv + vec2<f32>(texel.x, 0.0)).rgb +
       textureSample(input_tex, input_samp, uv - vec2<f32>(texel.x, 0.0)).rgb +
       textureSample(input_tex, input_samp, uv + vec2<f32>(0.0, texel.y)).rgb +
       textureSample(input_tex, input_samp, uv - vec2<f32>(0.0, texel.y)).rgb) * 0.1;
  let diagonal =
      (textureSample(input_tex, input_samp, uv + texel).rgb +
       textureSample(input_tex, input_samp, uv - texel).rgb +
       textureSample(input_tex, input_samp, uv + vec2<f32>(texel.x, -texel.y)).rgb +
       textureSample(input_tex, input_samp, uv + vec2<f32>(-texel.x, texel.y)).rgb) * 0.075;
  let far =
      (textureSample(input_tex, input_samp, uv + vec2<f32>(2.0 * texel.x, 0.0)).rgb +
       textureSample(input_tex, input_samp, uv - vec2<f32>(2.0 * texel.x, 0.0)).rgb +
       textureSample(input_tex, input_samp, uv + vec2<f32>(0.0, 2.0 * texel.y)).rgb +
       textureSample(input_tex, input_samp, uv - vec2<f32>(0.0, 2.0 * texel.y)).rgb) * 0.05;

  let color = max(center + cross + diagonal + far, vec3<f32>(0.0));
  return vec4<f32>(color, 1.0);
}
