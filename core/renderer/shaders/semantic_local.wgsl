struct SemanticLocalUniform {
  face_a : vec4<f32>,
  face_b : vec4<f32>,
  person_a : vec4<f32>,
  foreground_a : vec4<f32>,
  foreground_b : vec4<f32>,
  tonal_a : vec4<f32>,
  gates : vec4<f32>,
};

@group(0) @binding(0) var input_tex : texture_2d<f32>;
@group(0) @binding(1) var input_samp : sampler;
@group(0) @binding(2) var face_mask_tex : texture_2d<f32>;
@group(0) @binding(3) var person_mask_tex : texture_2d<f32>;
@group(0) @binding(4) var highlight_mask_tex : texture_2d<f32>;
@group(0) @binding(5) var shadow_mask_tex : texture_2d<f32>;
@group(0) @binding(6) var foreground_mask_tex : texture_2d<f32>;
@group(0) @binding(7) var mask_samp : sampler;
@group(0) @binding(8) var<uniform> u : SemanticLocalUniform;

fn luminance(color : vec3<f32>) -> f32 {
  return dot(color, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn safe_color(color : vec3<f32>) -> vec3<f32> {
  return max(color, vec3<f32>(0.0));
}

fn cbrt_positive(v : f32) -> f32 {
  return pow(max(v, 0.0), 1.0 / 3.0);
}

fn rgb_to_oklab(color : vec3<f32>) -> vec3<f32> {
  let l = 0.4122214708 * color.r + 0.5363325363 * color.g + 0.0514459929 * color.b;
  let m = 0.2119034982 * color.r + 0.6806995451 * color.g + 0.1073969566 * color.b;
  let s = 0.0883024619 * color.r + 0.2817188376 * color.g + 0.6299787005 * color.b;

  let l_ = cbrt_positive(l);
  let m_ = cbrt_positive(m);
  let s_ = cbrt_positive(s);

  return vec3<f32>(
    0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
    1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
    0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
  );
}

fn oklab_to_rgb(lab : vec3<f32>) -> vec3<f32> {
  let l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
  let m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
  let s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;

  let l = l_ * l_ * l_;
  let m = m_ * m_ * m_;
  let s = s_ * s_ * s_;

  return vec3<f32>(
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
  );
}

fn rotate_ab(ab : vec2<f32>, degrees : f32) -> vec2<f32> {
  let radians = degrees * 0.017453292519943295;
  let c = cos(radians);
  let s = sin(radians);
  return vec2<f32>(ab.x * c - ab.y * s, ab.x * s + ab.y * c);
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
    let similarity = exp2(-abs(sample_luma - center_luma) * 9.0);
    let weight = base_weights[i] * similarity;
    accum = accum + sample_color * weight;
    weight_sum = weight_sum + weight;
  }
  return accum / max(weight_sum, 1e-4);
}

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  var color = textureSample(input_tex, input_samp, uv).rgb;

  let face_mask = textureSample(face_mask_tex, mask_samp, uv).r;
  let person_mask = textureSample(person_mask_tex, mask_samp, uv).r;
  let highlight_mask = textureSample(highlight_mask_tex, mask_samp, uv).r;
  let shadow_mask = textureSample(shadow_mask_tex, mask_samp, uv).r;
  let foreground_mask = textureSample(foreground_mask_tex, mask_samp, uv).r;
  let blur_small = edge_aware_blur(uv, color, 1.0 * u.tonal_a.w);
  let blur_large = edge_aware_blur(uv, color, 2.0 * u.tonal_a.w);
  let fine_detail = color - blur_small;

  var face_color = color;
  face_color = face_color * exp2(u.face_a.x);
  var face_lab = rgb_to_oklab(face_color);
  var face_ab = face_lab.yz * max(u.face_a.y, 0.0);
  face_ab = rotate_ab(face_ab, u.face_a.z);
  face_lab.y = face_ab.x;
  face_lab.z = face_ab.y;
  face_lab.y = face_lab.y + u.face_a.w * 0.010;
  face_lab.z = face_lab.z + u.face_a.w * 0.030;
  face_color = oklab_to_rgb(face_lab);
  face_color = mix(face_color, blur_small, clamp(-u.face_b.x, 0.0, 1.0));
  face_color = face_color + fine_detail * clamp(u.face_b.x, 0.0, 1.0) * 0.45;
  color = mix(color, safe_color(face_color), clamp(face_mask * u.gates.x, 0.0, 1.0));

  var person_color = color;
  person_color = person_color * exp2(u.person_a.x);
  var person_lab = rgb_to_oklab(person_color);
  var person_ab = person_lab.yz * max(u.person_a.y, 0.0);
  person_ab = rotate_ab(person_ab, u.person_a.z);
  person_lab.y = person_ab.x;
  person_lab.z = person_ab.y;
  person_color = oklab_to_rgb(person_lab);
  let person_detail = person_color - blur_small;
  person_color = person_color + person_detail * u.person_a.w * 0.42;
  color = mix(color, safe_color(person_color), clamp(person_mask * u.gates.y, 0.0, 1.0));

  var fg_color = color;
  var fg_lab = rgb_to_oklab(fg_color);
  var fg_ab = rotate_ab(fg_lab.yz, u.foreground_a.x);
  fg_ab = fg_ab * max(u.foreground_a.y, 0.0);
  fg_lab.y = fg_ab.x;
  fg_lab.z = fg_ab.y;
  fg_lab.x = max(fg_lab.x + u.foreground_a.z * 0.08, 0.0);
  fg_color = oklab_to_rgb(fg_lab) * exp2(u.foreground_a.w);
  let fg_luma = luminance(fg_color);
  fg_color = (fg_color - vec3<f32>(fg_luma)) * (1.0 + u.foreground_b.x * 0.4) + vec3<f32>(fg_luma);
  fg_color = fg_color + (fg_color - blur_large) * u.foreground_b.y * 0.45;
  color = mix(color, safe_color(fg_color), clamp(foreground_mask * u.gates.z, 0.0, 1.0));

  var tonal_color = color;
  var tonal_lab = rgb_to_oklab(tonal_color);
  tonal_lab.y = tonal_lab.y + u.tonal_a.x * highlight_mask * 0.010;
  tonal_lab.z = tonal_lab.z + u.tonal_a.x * highlight_mask * 0.032;
  tonal_lab.y = tonal_lab.y + u.tonal_a.y * shadow_mask * 0.026;
  tonal_lab.z = tonal_lab.z - u.tonal_a.y * shadow_mask * 0.018;
  var tonal_ab = mix(tonal_lab.yz, vec2<f32>(0.0, 0.0), shadow_mask * clamp(u.tonal_a.z, 0.0, 1.0) * 0.75);
  tonal_lab.y = tonal_ab.x;
  tonal_lab.z = tonal_ab.y;
  tonal_color = oklab_to_rgb(tonal_lab);
  let tonal_mix = clamp(max(highlight_mask, shadow_mask) * u.gates.w, 0.0, 1.0);
  color = mix(color, safe_color(tonal_color), tonal_mix);

  return vec4<f32>(safe_color(color), 1.0);
}
