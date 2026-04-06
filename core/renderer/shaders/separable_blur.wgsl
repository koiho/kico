struct SeparableBlurUniform {
  direction_radius : vec4<f32>,
  weights_a : vec4<f32>,
  weights_b : vec4<f32>,
  weights_c : vec4<f32>,
};

@group(0) @binding(0) var input_tex : texture_2d<f32>;
@group(0) @binding(1) var input_samp : sampler;
@group(0) @binding(2) var<uniform> u : SeparableBlurUniform;

fn texel_size() -> vec2<f32> {
  let dims = vec2<f32>(textureDimensions(input_tex));
  return 1.0 / max(dims, vec2<f32>(1.0, 1.0));
}

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  let texel = texel_size();
  let direction = normalize(max(abs(u.direction_radius.xy), vec2<f32>(1e-5, 1e-5))) * sign(u.direction_radius.xy);
  let stride = max(u.direction_radius.z, 0.5);
  let step_uv = direction * texel * stride;

  let w0 = u.weights_a.x;
  let w1 = u.weights_a.y;
  let w2 = u.weights_a.z;
  let w3 = u.weights_a.w;
  let w4 = u.weights_b.x;
  let w5 = u.weights_b.y;
  let w6 = u.weights_b.z;
  let w7 = u.weights_b.w;
  let w8 = u.weights_c.x;
  let w9 = u.weights_c.y;
  let w10 = u.weights_c.z;

  var color = textureSample(input_tex, input_samp, uv).rgb * w0;
  color = color + (textureSample(input_tex, input_samp, uv + step_uv * 1.0).rgb + textureSample(input_tex, input_samp, uv - step_uv * 1.0).rgb) * w1;
  color = color + (textureSample(input_tex, input_samp, uv + step_uv * 2.0).rgb + textureSample(input_tex, input_samp, uv - step_uv * 2.0).rgb) * w2;
  color = color + (textureSample(input_tex, input_samp, uv + step_uv * 3.0).rgb + textureSample(input_tex, input_samp, uv - step_uv * 3.0).rgb) * w3;
  color = color + (textureSample(input_tex, input_samp, uv + step_uv * 4.0).rgb + textureSample(input_tex, input_samp, uv - step_uv * 4.0).rgb) * w4;
  color = color + (textureSample(input_tex, input_samp, uv + step_uv * 5.0).rgb + textureSample(input_tex, input_samp, uv - step_uv * 5.0).rgb) * w5;
  color = color + (textureSample(input_tex, input_samp, uv + step_uv * 6.0).rgb + textureSample(input_tex, input_samp, uv - step_uv * 6.0).rgb) * w6;
  color = color + (textureSample(input_tex, input_samp, uv + step_uv * 7.0).rgb + textureSample(input_tex, input_samp, uv - step_uv * 7.0).rgb) * w7;
  color = color + (textureSample(input_tex, input_samp, uv + step_uv * 8.0).rgb + textureSample(input_tex, input_samp, uv - step_uv * 8.0).rgb) * w8;
  color = color + (textureSample(input_tex, input_samp, uv + step_uv * 9.0).rgb + textureSample(input_tex, input_samp, uv - step_uv * 9.0).rgb) * w9;
  color = color + (textureSample(input_tex, input_samp, uv + step_uv * 10.0).rgb + textureSample(input_tex, input_samp, uv - step_uv * 10.0).rgb) * w10;

  return vec4<f32>(max(color, vec3<f32>(0.0)), 1.0);
}
