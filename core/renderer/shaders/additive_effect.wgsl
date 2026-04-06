struct DualTextureUtilityUniform {
  params : vec4<f32>,
};

@group(0) @binding(0) var base_tex : texture_2d<f32>;
@group(0) @binding(1) var base_samp : sampler;
@group(0) @binding(2) var effect_tex : texture_2d<f32>;
@group(0) @binding(3) var effect_samp : sampler;
@group(0) @binding(4) var<uniform> u : DualTextureUtilityUniform;

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  let base = max(textureSample(base_tex, base_samp, uv).rgb, vec3<f32>(0.0));
  let effect = max(textureSample(effect_tex, effect_samp, uv).rgb, vec3<f32>(0.0));
  return vec4<f32>(base + effect, 1.0);
}
