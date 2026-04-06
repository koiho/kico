struct DualTextureUtilityUniform {
  params : vec4<f32>,
};

@group(0) @binding(0) var base_tex : texture_2d<f32>;
@group(0) @binding(1) var base_samp : sampler;
@group(0) @binding(2) var processed_tex : texture_2d<f32>;
@group(0) @binding(3) var processed_samp : sampler;
@group(0) @binding(4) var<uniform> u : DualTextureUtilityUniform;

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  let base = textureSample(base_tex, base_samp, uv).rgb;
  let processed = textureSample(processed_tex, processed_samp, uv).rgb;
  let delta = max(processed - base, vec3<f32>(0.0));
  return vec4<f32>(delta, 1.0);
}
