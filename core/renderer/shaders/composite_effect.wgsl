struct CompositeEffectUniform {
  intensity_gate : vec4<f32>,
  tint : vec4<f32>,
};

@group(0) @binding(0) var base_tex : texture_2d<f32>;
@group(0) @binding(1) var base_samp : sampler;
@group(0) @binding(2) var effect_tex : texture_2d<f32>;
@group(0) @binding(3) var effect_samp : sampler;
@group(0) @binding(4) var<uniform> u : CompositeEffectUniform;

fn luminance(color : vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
}

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  let base = textureSample(base_tex, base_samp, uv).rgb;
  let effect = max(textureSample(effect_tex, effect_samp, uv).rgb, vec3<f32>(0.0)) * u.tint.rgb;
  let base_luma = luminance(max(base, vec3<f32>(0.0)));
  let effect_luma = luminance(effect);
  let intensity = max(u.intensity_gate.x, 0.0);
  let gate = clamp(u.intensity_gate.y, 0.0, 1.0);
  let effect_response = smoothstep(0.0, 0.12, effect_luma);
  let base_acceptance = 0.55 + 0.45 * smoothstep(0.02, 0.35, base_luma);
  let rolloff = 1.0 / (1.0 + max(base, vec3<f32>(0.0)) * 0.35);
  let addition = effect * intensity * gate * effect_response * base_acceptance;
  let out_color = base + addition * rolloff;
  return vec4<f32>(max(out_color, vec3<f32>(0.0)), 1.0);
}
