struct GlobalColorSectorUniform {
  global_a : vec4<f32>,
  global_b : vec4<f32>,
  split_shadow : vec4<f32>,
  split_midtone : vec4<f32>,
  split_highlight : vec4<f32>,
  red : vec4<f32>,
  yellow : vec4<f32>,
  green : vec4<f32>,
  cyan : vec4<f32>,
  blue : vec4<f32>,
  magenta : vec4<f32>,
  sector_shared : vec4<f32>,
};

@group(0) @binding(0) var input_tex : texture_2d<f32>;
@group(0) @binding(1) var input_samp : sampler;
@group(0) @binding(2) var<uniform> u : GlobalColorSectorUniform;

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

fn oklab_hue(ab : vec2<f32>) -> f32 {
  var hue = degrees(atan2(ab.y, ab.x));
  if hue < 0.0 {
    hue = hue + 360.0;
  }
  return hue;
}

fn hue_distance(a : f32, b : f32) -> f32 {
  let d = abs(a - b);
  return min(d, 360.0 - d);
}

fn sector_weight(hue : f32, center : f32, width_scale : f32, smoothness : f32) -> f32 {
  let outer = 30.0 * width_scale;
  let inner = outer * mix(0.2, 0.8, 1.0 - smoothness);
  let d = hue_distance(hue, center);
  return 1.0 - smoothstep(inner, outer, d);
}

@fragment
fn fs_main(@location(0) uv : vec2<f32>) -> @location(0) vec4<f32> {
  var color = textureSample(input_tex, input_samp, uv).rgb;

  let global_saturation = u.global_a.x;
  let global_vibrance = u.global_a.y;
  let global_hue_shift = u.global_a.z;
  let color_density = u.global_a.w;
  let warmth_bias = u.global_b.x;
  let green_magenta_bias = u.global_b.y;
  let split_balance = u.global_b.z;
  let sector_gate = u.global_b.w;

  var lab = rgb_to_oklab(safe_color(color));
  let base_luma = lab.x;
  let chroma = length(lab.yz);
  let vibrance_boost = (1.0 - clamp(chroma * 3.2, 0.0, 1.0)) * global_vibrance * 0.45;
  var lab_ab = lab.yz * max(global_saturation * (1.0 + vibrance_boost), 0.0);
  lab_ab = rotate_ab(lab_ab, global_hue_shift);
  lab.y = lab_ab.x;
  lab.z = lab_ab.y;
  lab.y = lab.y + warmth_bias * 0.015 + green_magenta_bias * 0.035;
  lab.z = lab.z + warmth_bias * 0.05;
  lab.x = max(lab.x + color_density * 0.018 - chroma * color_density * 0.01, 0.0);

  let width_scale = max(u.sector_shared.x, 0.01);
  let smoothness = clamp(u.sector_shared.y, 0.0, 1.0);
  let lab_hue = oklab_hue(lab.yz);

  let red_w = sector_weight(lab_hue, 0.0, width_scale, smoothness) * sector_gate;
  let yellow_w = sector_weight(lab_hue, 60.0, width_scale, smoothness) * sector_gate;
  let green_w = sector_weight(lab_hue, 120.0, width_scale, smoothness) * sector_gate;
  let cyan_w = sector_weight(lab_hue, 180.0, width_scale, smoothness) * sector_gate;
  let blue_w = sector_weight(lab_hue, 240.0, width_scale, smoothness) * sector_gate;
  let magenta_w = sector_weight(lab_hue, 300.0, width_scale, smoothness) * sector_gate;

  let sector_hue_shift =
      u.red.x * red_w +
      u.yellow.x * yellow_w +
      u.green.x * green_w +
      u.cyan.x * cyan_w +
      u.blue.x * blue_w +
      u.magenta.x * magenta_w;
  lab_ab = rotate_ab(lab.yz, sector_hue_shift);
  lab.y = lab_ab.x;
  lab.z = lab_ab.y;

  let sector_chroma_scale =
      u.red.y * red_w +
      u.yellow.y * yellow_w +
      u.green.y * green_w +
      u.cyan.y * cyan_w +
      u.blue.y * blue_w +
      u.magenta.y * magenta_w +
      max(1.0 - red_w - yellow_w - green_w - cyan_w - blue_w - magenta_w, 0.0);
  lab_ab = lab.yz * max(mix(1.0, sector_chroma_scale, sector_gate), 0.0);
  lab.y = lab_ab.x;
  lab.z = lab_ab.y;

  lab.x = max(
      lab.x +
      (u.red.z * red_w +
       u.yellow.z * yellow_w +
       u.green.z * green_w +
       u.cyan.z * cyan_w +
       u.blue.z * blue_w +
       u.magenta.z * magenta_w) * 0.045,
      0.0);

  let shadow_w = (1.0 - smoothstep(0.18, 0.45, lab.x)) * (1.0 - split_balance * 0.5);
  let mid_w = smoothstep(0.18, 0.45, lab.x) * (1.0 - smoothstep(0.55, 0.82, lab.x));
  let highlight_w = smoothstep(0.55, 0.82, lab.x) * (1.0 + split_balance * 0.5);

  let shadow_dir = vec2<f32>(cos(radians(u.split_shadow.x)), sin(radians(u.split_shadow.x)));
  let mid_dir = vec2<f32>(cos(radians(u.split_midtone.x)), sin(radians(u.split_midtone.x)));
  let highlight_dir = vec2<f32>(cos(radians(u.split_highlight.x)), sin(radians(u.split_highlight.x)));

  lab_ab = lab.yz + shadow_dir * shadow_w * u.split_shadow.y * 0.035;
  lab_ab = lab_ab + mid_dir * mid_w * u.split_midtone.y * 0.026;
  lab_ab = lab_ab + highlight_dir * highlight_w * u.split_highlight.y * 0.040;
  lab.y = lab_ab.x;
  lab.z = lab_ab.y;
  lab.x = mix(base_luma, lab.x, clamp(1.0 + color_density * 0.08, 0.0, 1.0));

  color = oklab_to_rgb(lab);
  color = safe_color(color);

  return vec4<f32>(color, 1.0);
}
