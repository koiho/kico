from __future__ import annotations

import math
from dataclasses import dataclass
from functools import lru_cache

import torch
from torch import Tensor
from torch.nn import functional as F

try:
    from .contract import gate_index, mask_index, parameter_index, parameter_range
except ImportError:  # pragma: no cover
    from contract import gate_index, mask_index, parameter_index, parameter_range


LN_2 = math.log(2.0)
DEG_TO_RAD = math.pi / 180.0


@dataclass(frozen=True, slots=True)
class RenderApproxConfig:
    enable_global_color: bool = True
    enable_local: bool = True
    enable_optics: bool = True
    enable_texture: bool = True
    enable_finish: bool = True


def soft_render_approx(
    neutral: Tensor,
    params: Tensor,
    gates: Tensor,
    mask_tensor: Tensor,
    config: RenderApproxConfig | None = None,
) -> Tensor:
    if config is None:
        config = RenderApproxConfig()
    batch, _, height, width = neutral.shape
    color = neutral

    if config.enable_global_color:
        ev = decode_param(params, "exposure_ev")
        wb_r = decode_param(params, "wb_r_gain")
        wb_b = decode_param(params, "wb_b_gain")
        contrast = decode_param(params, "contrast")
        pivot = decode_param(params, "contrast_pivot")
        blacks = decode_param(params, "blacks")
        whites = decode_param(params, "whites")
        shadows = decode_param(params, "shadows")
        highlights = decode_param(params, "highlights")
        toe_strength = decode_param(params, "toe_strength")
        shoulder_strength = decode_param(params, "shoulder_strength")
        fade = decode_param(params, "fade")
        midtone_boost = decode_param(params, "midtone_boost")
        clarity_global = decode_param(params, "clarity_global")
        saturation = decode_param(params, "global_saturation")
        vibrance = decode_param(params, "global_vibrance")
        global_hue_shift = decode_param(params, "global_hue_shift")
        color_density = decode_param(params, "color_density")
        warmth = decode_param(params, "warmth_bias")
        magenta = decode_param(params, "green_magenta_bias")
        shadow_hue = decode_param(params, "shadow_hue")
        shadow_sat = decode_param(params, "shadow_sat")
        midtone_hue = decode_param(params, "midtone_hue")
        midtone_sat = decode_param(params, "midtone_sat")
        highlight_hue = decode_param(params, "highlight_hue")
        highlight_sat = decode_param(params, "highlight_sat")
        split_balance = decode_param(params, "split_balance")
        sector_color_gate = decode_gate(gates, "sector_color_gate")
        red_hue_shift = decode_param(params, "red_hue_shift")
        red_sat_scale = decode_param(params, "red_sat_scale")
        red_luma_shift = decode_param(params, "red_luma_shift")
        yellow_hue_shift = decode_param(params, "yellow_hue_shift")
        yellow_sat_scale = decode_param(params, "yellow_sat_scale")
        yellow_luma_shift = decode_param(params, "yellow_luma_shift")
        green_hue_shift = decode_param(params, "green_hue_shift")
        green_sat_scale = decode_param(params, "green_sat_scale")
        green_luma_shift = decode_param(params, "green_luma_shift")
        cyan_hue_shift = decode_param(params, "cyan_hue_shift")
        cyan_sat_scale = decode_param(params, "cyan_sat_scale")
        cyan_luma_shift = decode_param(params, "cyan_luma_shift")
        blue_hue_shift = decode_param(params, "blue_hue_shift")
        blue_sat_scale = decode_param(params, "blue_sat_scale")
        blue_luma_shift = decode_param(params, "blue_luma_shift")
        magenta_hue_shift = decode_param(params, "magenta_hue_shift")
        magenta_sat_scale = decode_param(params, "magenta_sat_scale")
        magenta_luma_shift = decode_param(params, "magenta_luma_shift")
        sector_width_scale = decode_param(params, "sector_width_scale")
        sector_smoothness = decode_param(params, "sector_smoothness")

        exposure_scale = torch.exp(ev * LN_2)
        color = clamp01(color * exposure_scale)

        r = channel(color, 0) * wb_r
        g = channel(color, 1)
        b = channel(color, 2) * wb_b
        color = clamp01(stack_rgb(r, g, b))

        color = (color - pivot) * (contrast + 1.0) + pivot

        luma = luminance(color)
        shadow_w = torch.ones_like(luma) - smoothstep_scalar(0.05, 0.45, luma)
        highlight_w = smoothstep_scalar(0.55, 0.95, luma)
        black_w = torch.ones_like(luma) - smoothstep_scalar(0.0, 0.25, luma)
        white_w = smoothstep_scalar(0.75, 1.0, luma)
        toned_color = (
            color
            + shadows * shadow_w * 0.25
            + highlights * highlight_w * 0.25
            + blacks * black_w * 0.18
            + whites * white_w * 0.18
        )
        shoulder_excess = (toned_color - torch.ones_like(toned_color)).clamp(0.0, 4.0)
        color = clamp01(toned_color)

        toe_color = clamp01(
            color.pow(1.0) * (torch.ones_like(color) - shadow_w * toe_strength)
            + color.pow(1.55) * shadow_w * toe_strength
        )
        shoulder_color = clamp01(
            toned_color
            / (
                torch.ones_like(color)
                + shoulder_excess
                * (torch.ones_like(color) * 0.5 + shoulder_strength * highlight_w * 1.5)
            )
        )
        color = mix_tensors(color, toe_color, toe_strength * shadow_w)
        color = mix_tensors(color, shoulder_color, shoulder_strength * highlight_w)

        mid_w = smoothstep_scalar(0.2, 0.5, luma) * (
            torch.ones_like(luma) - smoothstep_scalar(0.5, 0.85, luma)
        )
        color = color * (torch.ones_like(color) + midtone_boost * mid_w * 0.25)
        color = torch.maximum(color, torch.ones_like(color) * fade * 0.18)

        blur_small = edge_aware_blur_small(color, 1.0, 10.0)
        detail_small = color - blur_small
        clarity_weight = mid_w * (torch.ones_like(mid_w) - highlight_w * 0.55)
        color = clamp01(color + detail_small * clarity_global * clarity_weight * 0.85)

        lab = rgb_to_oklab(safe_color(color))
        base_luma = channel(lab, 0)
        lab_ab = lab[:, 1:3, :, :]
        chroma = torch.sqrt((lab_ab * lab_ab).sum(dim=1, keepdim=True).clamp_min(1e-8))
        vibrance_boost = (torch.ones_like(chroma) - (chroma * 3.2).clamp(0.0, 1.0)) * vibrance * 0.45
        lab_ab = lab_ab * (saturation * (torch.ones_like(vibrance_boost) + vibrance_boost)).clamp_min(0.0)
        lab_ab = rotate_ab(lab_ab, global_hue_shift)
        lab_l = (base_luma + color_density * 0.018 - chroma * color_density * 0.01).clamp_min(0.0)
        lab_a = channel(lab_ab, 0) + warmth * 0.015 + magenta * 0.035
        lab_b = channel(lab_ab, 1) + warmth * 0.05
        lab_ab = stack_ab(lab_a, lab_b)

        width_scale = sector_width_scale.clamp_min(0.01)
        smoothness = sector_smoothness.clamp(0.0, 1.0)
        lab_hue = oklab_hue(lab_ab)
        red_w = sector_weight(lab_hue, 0.0, width_scale, smoothness) * sector_color_gate
        yellow_w = sector_weight(lab_hue, 60.0, width_scale, smoothness) * sector_color_gate
        green_w = sector_weight(lab_hue, 120.0, width_scale, smoothness) * sector_color_gate
        cyan_w = sector_weight(lab_hue, 180.0, width_scale, smoothness) * sector_color_gate
        blue_w = sector_weight(lab_hue, 240.0, width_scale, smoothness) * sector_color_gate
        magenta_w = sector_weight(lab_hue, 300.0, width_scale, smoothness) * sector_color_gate

        sector_hue_shift = (
            red_hue_shift * red_w
            + yellow_hue_shift * yellow_w
            + green_hue_shift * green_w
            + cyan_hue_shift * cyan_w
            + blue_hue_shift * blue_w
            + magenta_hue_shift * magenta_w
        )
        lab_ab = rotate_ab(lab_ab, sector_hue_shift)
        sector_chroma_scale = (
            red_sat_scale * red_w
            + yellow_sat_scale * yellow_w
            + green_sat_scale * green_w
            + cyan_sat_scale * cyan_w
            + blue_sat_scale * blue_w
            + magenta_sat_scale * magenta_w
            + (
                torch.ones_like(red_w)
                - red_w
                - yellow_w
                - green_w
                - cyan_w
                - blue_w
                - magenta_w
            ).clamp_min(0.0)
        )
        lab_ab = lab_ab * (
            torch.ones_like(sector_color_gate)
            + (sector_chroma_scale - torch.ones_like(sector_chroma_scale)) * sector_color_gate
        ).clamp_min(0.0)
        lab_l = (
            lab_l
            + (
                red_luma_shift * red_w
                + yellow_luma_shift * yellow_w
                + green_luma_shift * green_w
                + cyan_luma_shift * cyan_w
                + blue_luma_shift * blue_w
                + magenta_luma_shift * magenta_w
            )
            * 0.045
        ).clamp_min(0.0)

        shadow_split_w = (torch.ones_like(lab_l) - smoothstep_scalar(0.18, 0.45, lab_l)) * (
            torch.ones_like(split_balance) - split_balance * 0.5
        )
        mid_split_w = smoothstep_scalar(0.18, 0.45, lab_l) * (
            torch.ones_like(lab_l) - smoothstep_scalar(0.55, 0.82, lab_l)
        )
        highlight_split_w = smoothstep_scalar(0.55, 0.82, lab_l) * (
            torch.ones_like(split_balance) + split_balance * 0.5
        )
        lab_ab = (
            lab_ab
            + hue_direction(shadow_hue) * shadow_split_w * shadow_sat * 0.035
            + hue_direction(midtone_hue) * mid_split_w * midtone_sat * 0.026
            + hue_direction(highlight_hue) * highlight_split_w * highlight_sat * 0.040
        )
        lab_l = mix_tensors(
            base_luma,
            lab_l,
            (torch.ones_like(color_density) + color_density * 0.08).clamp(0.0, 1.0),
        )
        color = safe_color(oklab_to_rgb(stack_lab(lab_l, lab_ab)))

    if config.enable_local:
        highlight_mask_threshold = decode_param(params, "highlight_mask_threshold")
        highlight_mask_feather = decode_param(params, "highlight_mask_feather")
        shadow_mask_threshold = decode_param(params, "shadow_mask_threshold")
        shadow_mask_feather = decode_param(params, "shadow_mask_feather")

        face_mask = prepare_semantic_mask(mask(mask_tensor, "face"))
        person_mask = prepare_semantic_mask(mask(mask_tensor, "person"))
        foreground_mask = prepare_semantic_mask(mask(mask_tensor, "foreground_subject"))
        tonal_gate = decode_gate(gates, "tonal_local_gate")
        highlight_mask = prepare_tonal_mask(
            neutral,
            mask(mask_tensor, "highlight"),
            highlight_mask_threshold,
            highlight_mask_feather,
            True,
        )
        shadow_mask = prepare_tonal_mask(
            neutral,
            mask(mask_tensor, "shadow"),
            shadow_mask_threshold,
            shadow_mask_feather,
            False,
        )

        face_gate = decode_gate(gates, "face_gate")
        person_gate = decode_gate(gates, "person_gate")
        foreground_gate = decode_gate(gates, "foreground_subject_gate")

        face_exposure = decode_param(params, "face_exposure")
        person_exposure = decode_param(params, "person_exposure")
        foreground_exposure = decode_param(params, "foreground_subject_exposure")
        face_sat = decode_param(params, "face_sat")
        person_sat = decode_param(params, "person_sat")
        foreground_sat = decode_param(params, "foreground_subject_sat")
        face_hue_shift = decode_param(params, "face_hue_shift")
        face_warmth = decode_param(params, "face_warmth")
        face_soft_clarity = decode_param(params, "face_soft_clarity")
        person_hue_shift = decode_param(params, "person_hue_shift")
        person_clarity = decode_param(params, "person_clarity")
        foreground_hue_shift = decode_param(params, "foreground_subject_hue_shift")
        foreground_luma = decode_param(params, "foreground_subject_luma")
        foreground_contrast = decode_param(params, "foreground_subject_contrast")
        foreground_pop = decode_param(params, "foreground_subject_pop")
        highlight_warmth = decode_param(params, "highlight_warmth_local")
        shadow_tint = decode_param(params, "shadow_tint_local")
        shadow_desat = decode_param(params, "shadow_desat")

        local_blur_small = edge_aware_blur_small(color, 1.0, 9.0)
        local_blur_large = edge_aware_blur_small(color, 2.0, 9.0)
        local_fine_detail = color - local_blur_small

        face_adjusted = safe_color(color * torch.exp(face_exposure * LN_2))
        face_lab = rgb_to_oklab(face_adjusted)
        face_ab = rotate_ab(face_lab[:, 1:3, :, :] * face_sat.clamp_min(0.0), face_hue_shift)
        face_lab = stack_lab(
            channel(face_lab, 0),
            stack_ab(
                channel(face_ab, 0) + face_warmth * 0.010,
                channel(face_ab, 1) + face_warmth * 0.030,
            ),
        )
        face_adjusted = safe_color(oklab_to_rgb(face_lab))
        face_adjusted = mix_tensors(face_adjusted, local_blur_small, (-face_soft_clarity).clamp(0.0, 1.0))
        face_adjusted = safe_color(
            face_adjusted + local_fine_detail * face_soft_clarity.clamp(0.0, 1.0) * 0.45
        )
        color = apply_masked_mix(color, face_adjusted, face_mask, face_gate)

        person_adjusted = safe_color(color * torch.exp(person_exposure * LN_2))
        person_lab = rgb_to_oklab(person_adjusted)
        person_ab = rotate_ab(person_lab[:, 1:3, :, :] * person_sat.clamp_min(0.0), person_hue_shift)
        person_adjusted = safe_color(oklab_to_rgb(stack_lab(channel(person_lab, 0), person_ab)))
        person_detail = person_adjusted - local_blur_small
        person_adjusted = safe_color(person_adjusted + person_detail * person_clarity * 0.42)
        color = apply_masked_mix(color, person_adjusted, person_mask, person_gate)

        fg_lab = rgb_to_oklab(color)
        fg_ab = rotate_ab(fg_lab[:, 1:3, :, :], foreground_hue_shift) * foreground_sat.clamp_min(0.0)
        fg_l = (channel(fg_lab, 0) + foreground_luma * 0.08).clamp_min(0.0)
        fg_adjusted = safe_color(
            oklab_to_rgb(stack_lab(fg_l, fg_ab)) * torch.exp(foreground_exposure * LN_2)
        )
        fg_luma = luminance(fg_adjusted)
        fg_adjusted = (fg_adjusted - fg_luma) * (torch.ones_like(color) + foreground_contrast * 0.4) + fg_luma
        fg_adjusted = safe_color(fg_adjusted + (fg_adjusted - local_blur_large) * foreground_pop * 0.45)
        color = apply_masked_mix(color, fg_adjusted, foreground_mask, foreground_gate)

        tonal_lab = rgb_to_oklab(color)
        tonal_a = channel(tonal_lab, 1) + highlight_warmth * highlight_mask * 0.010
        tonal_b = channel(tonal_lab, 2) + highlight_warmth * highlight_mask * 0.032
        tonal_a = tonal_a + shadow_tint * shadow_mask * 0.026
        tonal_b = tonal_b - shadow_tint * shadow_mask * 0.018
        tonal_ab = mix_tensors(
            stack_ab(tonal_a, tonal_b),
            torch.zeros_like(stack_ab(tonal_a, tonal_b)),
            shadow_mask * shadow_desat.clamp(0.0, 1.0) * 0.75,
        )
        tonal_color = safe_color(oklab_to_rgb(stack_lab(channel(tonal_lab, 0), tonal_ab)))
        tonal_mix = (torch.maximum(highlight_mask, shadow_mask) * tonal_gate).clamp(0.0, 1.0)
        color = mix_tensors(color, tonal_color, tonal_mix)

    if config.enable_optics:
        bloom_gate = decode_gate(gates, "bloom_gate")
        bloom_threshold = decode_param(params, "bloom_threshold")
        bloom_intensity = decode_param(params, "bloom_intensity")
        bloom_radius = decode_param(params, "bloom_radius")
        bloom_softness = decode_param(params, "bloom_softness")
        bloom_veil_mix = decode_param(params, "bloom_veil_mix")
        bloom_extract = extract_highlights_approx(
            color,
            bloom_threshold,
            torch.ones_like(bloom_softness) * 0.05 + bloom_softness * 0.16,
        )
        bloom_mid_share, bloom_wide_share, bloom_far_share, bloom_veil_share = bloom_layer_shares(
            bloom_veil_mix
        )
        bloom_mid = scaled_blur(bloom_extract, bloom_stride(bloom_radius, bloom_softness))
        bloom_wide_extract = downsample_prefilter_tensor(bloom_extract, 2)
        bloom_wide = upsample_to(
            scaled_blur(bloom_wide_extract, bloom_stride(bloom_radius, bloom_softness) * 1.8),
            height,
            width,
        )
        bloom_far_extract = downsample_prefilter_tensor(bloom_wide_extract, 2)
        bloom_far = upsample_to(
            scaled_blur(bloom_far_extract, bloom_stride(bloom_radius, bloom_softness) * 2.6),
            height,
            width,
        )
        bloom_veil_extract = downsample_prefilter_tensor(bloom_far_extract, 2)
        bloom_veil = upsample_to(
            scaled_blur(bloom_veil_extract, bloom_stride(bloom_radius, bloom_softness) * 3.6),
            height,
            width,
        )
        color = clamp01(
            color
            + bloom_veil * bloom_intensity * bloom_veil_share * bloom_gate
            + bloom_far * bloom_intensity * bloom_far_share * bloom_gate
            + bloom_wide * bloom_intensity * bloom_wide_share * bloom_gate
            + bloom_mid * bloom_intensity * bloom_mid_share * bloom_gate
        )

        halation_gate = decode_gate(gates, "halation_gate")
        halation_threshold = decode_param(params, "halation_threshold")
        halation_intensity = decode_param(params, "halation_intensity")
        halation_radius = decode_param(params, "halation_radius")
        halation_red_bias = decode_param(params, "halation_red_bias")
        halation_warmth = decode_param(params, "halation_warmth")
        halation_core_balance = decode_param(params, "halation_core_balance")
        halation_extract = extract_highlights_approx(
            color,
            halation_threshold,
            torch.ones_like(halation_warmth) * 0.05 + halation_warmth * 0.08,
        )
        halation_shape = clamp01(
            stack_rgb(
                channel(halation_extract, 0)
                * (torch.ones_like(halation_red_bias) + halation_red_bias * 0.40),
                channel(halation_extract, 1)
                * (torch.ones_like(halation_warmth) * 0.25 + halation_warmth * 0.20),
                channel(halation_extract, 2) * torch.ones_like(halation_warmth) * 0.10,
            )
        )
        shares = halation_layer_shares(halation_core_balance)
        halation_core_share, halation_wide_share, halation_far_share, halation_veil_share = shares
        halation_core_extract = downsample_prefilter_tensor(halation_shape, 2)
        halation_core = upsample_to(
            scaled_blur(halation_core_extract, halation_stride(halation_radius)),
            height,
            width,
        )
        halation_wide_extract = downsample_prefilter_tensor(halation_core_extract, 2)
        halation_wide = upsample_to(
            scaled_blur(halation_wide_extract, halation_stride(halation_radius) * 1.8),
            height,
            width,
        )
        halation_far_extract = downsample_prefilter_tensor(halation_wide_extract, 2)
        halation_far = upsample_to(
            scaled_blur(halation_far_extract, halation_stride(halation_radius) * 2.5),
            height,
            width,
        )
        halation_veil_extract = downsample_prefilter_tensor(halation_far_extract, 2)
        halation_veil = upsample_to(
            scaled_blur(halation_veil_extract, halation_stride(halation_radius) * 3.2),
            height,
            width,
        )
        halation_tint = stack_rgb(
            torch.ones_like(halation_red_bias) * (0.92 + halation_red_bias.clamp_min(0.0) * 0.22),
            torch.ones_like(halation_warmth) * (0.22 + halation_warmth.clamp_min(0.0) * 0.18),
            torch.ones_like(halation_warmth) * 0.04,
        )
        color = clamp01(
            color
            + halation_veil * halation_tint * halation_intensity * halation_veil_share * halation_gate
            + halation_far * halation_tint * halation_intensity * halation_far_share * halation_gate
            + halation_wide * halation_tint * halation_intensity * halation_wide_share * halation_gate
            + halation_core * halation_tint * halation_intensity * halation_core_share * halation_gate
        )

        lens_gate = decode_gate(gates, "lens_character_gate")
        soft_glow = decode_param(params, "soft_glow")
        edge_softness = decode_param(params, "edge_softness")
        lens_blur = edge_aware_blur_texture(color, 2.0, 4.2)
        lens_highlights = extract_highlights_approx(
            color,
            glow_threshold(soft_glow),
            glow_knee(soft_glow),
        )
        lens_mid_glow = scaled_blur(lens_highlights, glow_mid_stride(soft_glow))
        lens_wide_extract = downsample_prefilter_tensor(lens_highlights, 2)
        lens_wide_glow = upsample_to(
            scaled_blur(lens_wide_extract, glow_wide_stride(soft_glow)),
            height,
            width,
        )
        lens_far_extract = downsample_prefilter_tensor(lens_wide_extract, 2)
        lens_far_glow = upsample_to(
            scaled_blur(lens_far_extract, glow_far_stride(soft_glow)),
            height,
            width,
        )
        edge_mask = radial_mask(
            height,
            width,
            device=neutral.device,
            dtype=neutral.dtype,
            midpoint=0.55,
            feather=0.45,
        )
        color = clamp01(
            color
            + lens_far_glow * soft_glow * lens_gate * 0.12 * stack_rgb(
                torch.ones_like(soft_glow),
                torch.ones_like(soft_glow) * 0.965,
                torch.ones_like(soft_glow) * 0.94,
            )
            + lens_wide_glow * soft_glow * lens_gate * 0.16 * stack_rgb(
                torch.ones_like(soft_glow),
                torch.ones_like(soft_glow) * 0.97,
                torch.ones_like(soft_glow) * 0.94,
            )
            + lens_mid_glow * soft_glow * lens_gate * 0.22 * stack_rgb(
                torch.ones_like(soft_glow),
                torch.ones_like(soft_glow) * 0.99,
                torch.ones_like(soft_glow) * 0.96,
            )
        )
        color = mix_tensors(color, lens_blur, edge_mask * edge_softness * lens_gate * 0.45)

        vignette_gate = decode_gate(gates, "vignette_gate")
        vignette_amount = decode_param(params, "vignette_amount")
        vignette_midpoint = decode_param(params, "vignette_midpoint")
        vignette_feather = decode_param(params, "vignette_feather")
        vignette_roundness = decode_param(params, "vignette_roundness")
        vignette_strength = radial_mask(
            height,
            width,
            device=neutral.device,
            dtype=neutral.dtype,
            roundness=vignette_roundness,
            midpoint=0.0,
            feather=1.0,
        )
        vignette_strength = smoothstep_tensor(
            vignette_midpoint,
            vignette_midpoint + vignette_feather + 1e-4,
            vignette_strength,
        )
        color = color * (
            torch.ones_like(vignette_strength) - vignette_strength * vignette_amount * vignette_gate * 0.35
        )

    if config.enable_texture:
        grain_gate = decode_gate(gates, "grain_gate")
        texture_gate = decode_gate(gates, "texture_gate")
        grain_luma_amount = decode_param(params, "grain_luma_amount")
        grain_chroma_amount = decode_param(params, "grain_chroma_amount")
        grain_size = decode_param(params, "grain_size")
        grain_shadow_bias = decode_param(params, "grain_shadow_bias")
        grain_highlight_suppress = decode_param(params, "grain_highlight_suppress")
        texture_boost = decode_param(params, "texture_boost")
        noise_clean_bias = decode_param(params, "noise_clean_bias")
        detail_preserve = decode_param(params, "detail_preserve")
        microcontrast_balance = decode_param(params, "texture_microcontrast_balance")
        texture_blur_small = edge_aware_blur_texture(color, 1.0, 6.8)
        texture_blur_large = edge_aware_blur_texture(color, 2.8, 6.8)
        fine_detail = color - texture_blur_small
        structure_detail = texture_blur_small - texture_blur_large
        fine_micro_weight = torch.ones_like(microcontrast_balance) + microcontrast_balance.clamp(
            0.0, 1.0
        ) * 0.65
        structure_micro_weight = torch.ones_like(microcontrast_balance) + (
            -microcontrast_balance
        ).clamp(0.0, 1.0) * 0.65
        color = mix_tensors(color, texture_blur_small, noise_clean_bias * texture_gate * 0.32)
        color = clamp01(
            color
            + fine_detail * texture_boost * texture_gate * fine_micro_weight * 0.55
            + structure_detail * texture_boost * texture_gate * structure_micro_weight * 0.30
        )
        color = mix_tensors(
            color,
            clamp01(
                color
                + fine_detail * fine_micro_weight * 0.75
                + structure_detail * structure_micro_weight * 0.35
            ),
            detail_preserve * texture_gate * 0.30,
        )

        luma = luminance(color)
        grain_shadow_w = torch.ones_like(luma) + grain_shadow_bias * (
            torch.ones_like(luma) - smoothstep_scalar(0.0, 0.5, luma)
        )
        grain_highlight_w = torch.ones_like(luma) - grain_highlight_suppress * smoothstep_scalar(
            0.6, 1.0, luma
        )
        detail_weight = torch.ones_like(luma) - smoothstep_scalar(
            0.18,
            0.9,
            (luminance(fine_detail) + luminance(structure_detail)).abs(),
        )
        grain_weight = grain_gate * grain_shadow_w * grain_highlight_w * (
            torch.ones_like(detail_weight) * 0.72 + detail_weight * 0.28
        )
        fine_grain_cell = grain_cell_uv(
            height,
            width,
            grain_size,
            scale=1.0,
            angle=0.18,
            device=neutral.device,
            dtype=neutral.dtype,
        )
        mid_grain_cell = grain_cell_uv(
            height,
            width,
            grain_size,
            scale=1.9,
            angle=-0.43,
            device=neutral.device,
            dtype=neutral.dtype,
        )
        coarse_grain_cell = grain_cell_uv(
            height,
            width,
            grain_size,
            scale=3.2,
            angle=0.73,
            device=neutral.device,
            dtype=neutral.dtype,
        )
        fine_noise = hash21(fine_grain_cell).expand(batch, -1, -1, -1) * 2.0 - 1.0
        mid_noise = hash31(mid_grain_cell, 1.7).expand(batch, -1, -1, -1) * 2.0 - 1.0
        coarse_noise = hash31(coarse_grain_cell, 3.4).expand(batch, -1, -1, -1) * 2.0 - 1.0
        chroma_noise_r = hash31(
            fine_grain_cell + stack_uv_scalar(17.0, 3.0, device=neutral.device, dtype=neutral.dtype),
            2.1,
        ).expand(batch, -1, -1, -1) * 2.0 - 1.0
        chroma_noise_b = hash31(
            mid_grain_cell + stack_uv_scalar(5.0, 29.0, device=neutral.device, dtype=neutral.dtype),
            4.2,
        ).expand(batch, -1, -1, -1) * 2.0 - 1.0
        noise = fine_noise * 0.58 + mid_noise * 0.27 + coarse_noise * 0.15
        color = clamp01(
            color + torch.ones_like(color) * (noise * grain_luma_amount * 0.08 * grain_weight)
        )
        color_r = channel(color, 0) + chroma_noise_r * grain_chroma_amount * 0.035 * grain_weight
        color_g = channel(color, 1)
        color_b = channel(color, 2) - chroma_noise_b * grain_chroma_amount * 0.035 * grain_weight
        color = clamp01(stack_rgb(color_r, color_g, color_b))

    if config.enable_finish:
        gamut_compress = decode_param(params, "gamut_compress")
        final_gamma_bias = decode_param(params, "final_gamma_bias")
        highlight_clip_softness = decode_param(params, "highlight_clip_softness")
        highlight_rolloff_pivot = decode_param(params, "highlight_rolloff_pivot")
        shadow_floor = decode_param(params, "shadow_floor")

        finish_luma = luminance(color)
        finish_chroma = color - finish_luma
        chroma_extent = tensor_max3(
            channel(finish_chroma.abs(), 0),
            channel(finish_chroma.abs(), 1),
            channel(finish_chroma.abs(), 2),
        )
        chroma_scale = torch.ones_like(chroma_extent) / (
            torch.ones_like(chroma_extent) + gamut_compress * chroma_extent * 1.8
        )
        color = finish_luma + finish_chroma * chroma_scale

        pivot_color = torch.ones_like(color) * highlight_rolloff_pivot
        above = (color - pivot_color).clamp(0.0, 8.0)
        clipped = pivot_color + above / (
            torch.ones_like(above) + above * (torch.ones_like(above) * 0.5 + highlight_clip_softness)
        )
        below = tensor_min(color, pivot_color)
        color = below + (clipped - pivot_color).clamp(0.0, 8.0)

        luma_after = luminance(safe_color(color))
        gamma_luma = luma_after.clamp_min(1e-5).pow(
            torch.ones_like(final_gamma_bias) / final_gamma_bias.clamp_min(0.05)
        )
        gamma_scale = gamma_luma / luma_after.clamp_min(1e-5)
        color = safe_color(color * gamma_scale)

        return clamp01(torch.maximum(color, torch.ones_like(color) * shadow_floor))

    return clamp01(color)


def pyramid_l1(pred: Tensor, target: Tensor, levels: int) -> Tensor:
    pred_level = pred
    target_level = target
    loss = None
    used_levels = 0

    for _ in range(max(levels, 1)):
        batch, _, height, width = pred_level.shape
        level_loss = (pred_level - target_level).abs().reshape(batch, 3, height * width).mean(
            dim=2
        ).mean(dim=1)
        loss = level_loss if loss is None else loss + level_loss
        used_levels += 1
        if height <= 8 or width <= 8:
            break
        pred_level = F.avg_pool2d(
            pred_level,
            kernel_size=2,
            stride=2,
            padding=0,
            ceil_mode=True,
            count_include_pad=True,
        )
        target_level = F.avg_pool2d(
            target_level,
            kernel_size=2,
            stride=2,
            padding=0,
            ceil_mode=True,
            count_include_pad=True,
        )

    assert loss is not None
    return loss / used_levels


def edge_l1(pred: Tensor, target: Tensor) -> Tensor:
    pred_grad = gradient_map(pred)
    target_grad = gradient_map(target)
    batch, _, height, width = pred_grad.shape
    return (pred_grad - target_grad).abs().reshape(batch, 3, height * width).mean(dim=2).mean(dim=1)


def gradient_map(image: Tensor) -> Tensor:
    batch, channels, height, width = image.shape
    right = image[:, :, :, 1:width]
    left = image[:, :, :, 0 : width - 1]
    grad_x = (right - left).abs()
    grad_x_last = torch.zeros(batch, channels, height, 1, device=image.device, dtype=image.dtype)
    grad_x = torch.cat([grad_x, grad_x_last], dim=3)

    down = image[:, :, 1:height, :]
    up = image[:, :, 0 : height - 1, :]
    grad_y = (down - up).abs()
    grad_y_last = torch.zeros(batch, channels, 1, width, device=image.device, dtype=image.dtype)
    grad_y = torch.cat([grad_y, grad_y_last], dim=2)
    return grad_x + grad_y


def decode_param(params: Tensor, name: str) -> Tensor:
    index = parameter_index(name)
    low, high = parameter_range(name)
    return params[:, index : index + 1].reshape(-1, 1, 1, 1) * (high - low) + low


def decode_gate(gates: Tensor, name: str) -> Tensor:
    index = gate_index(name)
    return gates[:, index : index + 1].reshape(-1, 1, 1, 1)


def channel(color: Tensor, index: int) -> Tensor:
    return color[:, index : index + 1, :, :]


def stack_rgb(r: Tensor, g: Tensor, b: Tensor) -> Tensor:
    return torch.cat([r, g, b], dim=1)


def mix_tensors(base: Tensor, adjusted: Tensor, mix: Tensor) -> Tensor:
    return base * (torch.ones_like(mix) - mix) + adjusted * mix


def average_blur(image: Tensor, kernel: int) -> Tensor:
    kernel = max(kernel, 1) | 1
    return F.avg_pool2d(
        image,
        kernel_size=kernel,
        stride=1,
        padding=kernel // 2,
        ceil_mode=True,
        count_include_pad=True,
    )


def tensor_min(a: Tensor, b: Tensor) -> Tensor:
    return torch.minimum(a, b)


def tensor_max3(a: Tensor, b: Tensor, c: Tensor) -> Tensor:
    return torch.maximum(torch.maximum(a, b), c)


def safe_color(color: Tensor) -> Tensor:
    return color.clamp_min(0.0)


def shift_sample(image: Tensor, dx: int, dy: int) -> Tensor:
    pad_left = max(-dx, 0)
    pad_right = max(dx, 0)
    pad_top = max(-dy, 0)
    pad_bottom = max(dy, 0)
    padded = F.pad(image, (pad_left, pad_right, pad_top, pad_bottom), mode="replicate")
    height = image.shape[2]
    width = image.shape[3]
    x_start = max(dx, 0)
    y_start = max(dy, 0)
    return padded[:, :, y_start : y_start + height, x_start : x_start + width]


def edge_aware_blur_small(image: Tensor, scale: float, similarity_strength: float) -> Tensor:
    offsets = (
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
        (1, 1),
        (-1, 1),
        (1, -1),
        (-1, -1),
    )
    weights = (0.12, 0.12, 0.12, 0.12, 0.07, 0.07, 0.07, 0.07)
    return edge_aware_blur(image, offsets, weights, 0.24, scale, similarity_strength)


def edge_aware_blur_texture(image: Tensor, scale: float, similarity_strength: float) -> Tensor:
    offsets = (
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
        (1, 1),
        (-1, 1),
        (1, -1),
        (-1, -1),
        (2, 0),
        (-2, 0),
        (0, 2),
        (0, -2),
        (2, 1),
        (-2, 1),
        (2, -1),
        (-2, -1),
    )
    weights = (
        0.095,
        0.095,
        0.095,
        0.095,
        0.068,
        0.068,
        0.068,
        0.068,
        0.045,
        0.045,
        0.045,
        0.045,
        0.032,
        0.032,
        0.032,
        0.032,
    )
    return edge_aware_blur(image, offsets, weights, 0.22, scale, similarity_strength)


def edge_aware_blur(
    image: Tensor,
    offsets: tuple[tuple[int, int], ...],
    weights: tuple[float, ...],
    center_weight: float,
    scale: float,
    similarity_strength: float,
) -> Tensor:
    center = image
    center_luma = luminance(center)
    accum = center * center_weight
    weight_sum = torch.ones_like(center_luma) * center_weight
    for (offset_x, offset_y), base_weight in zip(offsets, weights):
        dx = int(round(offset_x * scale))
        dy = int(round(offset_y * scale))
        sample = shift_sample(image, dx, dy)
        sample_luma = luminance(sample)
        similarity = torch.exp2(-(sample_luma - center_luma).abs() * similarity_strength)
        weight = similarity * base_weight
        accum = accum + sample * weight
        weight_sum = weight_sum + weight
    return accum / weight_sum.clamp_min(1e-4)


def scaled_blur(image: Tensor, scale: Tensor | float) -> Tensor:
    if isinstance(scale, Tensor):
        value = float(scale.detach().mean().item())
    else:
        value = float(scale)
    kernel = max(int(round(1.0 + value * 2.0)), 1) | 1
    return average_blur(image, kernel)


def downsample_prefilter_tensor(image: Tensor, divisor: int) -> Tensor:
    if divisor <= 1:
        return image
    return F.avg_pool2d(
        image,
        kernel_size=divisor,
        stride=divisor,
        padding=0,
        ceil_mode=True,
        count_include_pad=True,
    )


def upsample_to(image: Tensor, height: int, width: int) -> Tensor:
    return F.interpolate(image, size=(height, width), mode="bilinear", align_corners=False)


def bloom_stride(radius: Tensor, softness: Tensor) -> Tensor:
    return (torch.ones_like(radius) * 0.85 + radius.clamp_min(0.0) * 4.8) * (
        torch.ones_like(softness) + softness.clamp_min(0.0) * 0.65
    )


def bloom_layer_shares(veil_mix: Tensor) -> tuple[Tensor, Tensor, Tensor, Tensor]:
    bias = (veil_mix.clamp(0.0, 1.0) - 0.5) * 2.0
    mid = (0.47 - bias * 0.07).clamp(0.30, 0.56)
    wide = (0.28 - bias * 0.03).clamp(0.22, 0.34)
    far = (0.15 + bias * 0.02).clamp(0.10, 0.20)
    veil = (0.10 + bias * 0.08).clamp(0.02, 0.22)
    total = (mid + wide + far + veil).clamp_min(1e-6)
    return mid / total, wide / total, far / total, veil / total


def halation_stride(radius: Tensor) -> Tensor:
    return torch.ones_like(radius) * 1.1 + radius.clamp_min(0.0) * 7.5


def halation_layer_shares(core_balance: Tensor) -> tuple[Tensor, Tensor, Tensor, Tensor]:
    bias = (core_balance.clamp(0.0, 1.0) - 0.5) * 2.0
    core = (0.28 + bias * 0.08).clamp(0.20, 0.36)
    wide = (0.17 - bias * 0.01).clamp(0.14, 0.19)
    far = (0.10 - bias * 0.03).clamp(0.07, 0.13)
    veil = (0.07 - bias * 0.04).clamp(0.03, 0.11)
    total = (core + wide + far + veil).clamp_min(1e-6)
    scale = torch.ones_like(total) * (0.62 / total)
    return core * scale, wide * scale, far * scale, veil * scale


def glow_threshold(soft_glow: Tensor) -> Tensor:
    return (0.72 - soft_glow.clamp_min(0.0) * 0.18).clamp(0.35, 0.72)


def glow_knee(soft_glow: Tensor) -> Tensor:
    return torch.ones_like(soft_glow) * 0.10 + soft_glow.clamp_min(0.0) * 0.12


def glow_mid_stride(soft_glow: Tensor) -> Tensor:
    return torch.ones_like(soft_glow) * 1.0 + soft_glow.clamp_min(0.0) * 4.0


def glow_wide_stride(soft_glow: Tensor) -> Tensor:
    return torch.ones_like(soft_glow) * 1.9 + soft_glow.clamp_min(0.0) * 5.5


def glow_far_stride(soft_glow: Tensor) -> Tensor:
    return torch.ones_like(soft_glow) * 3.1 + soft_glow.clamp_min(0.0) * 7.0


def smoothstep_tensor(edge0: Tensor, edge1: Tensor, x: Tensor) -> Tensor:
    denom = (edge1 - edge0).abs().clamp_min(1e-4)
    t = ((x - edge0) / denom).clamp(0.0, 1.0)
    return t * t * (torch.ones_like(t) * 3.0 - t * 2.0)


def circular_distance_deg(angle: Tensor, center: float) -> Tensor:
    distance = (angle - center).abs()
    return tensor_min(distance, torch.ones_like(distance) * 360.0 - distance)


def cbrt_positive(value: Tensor) -> Tensor:
    return value.clamp_min(0.0).pow(1.0 / 3.0)


def rgb_to_oklab(color: Tensor) -> Tensor:
    r = channel(color, 0)
    g = channel(color, 1)
    b = channel(color, 2)
    lms_l = r * 0.4122214708 + g * 0.5363325363 + b * 0.0514459929
    m = r * 0.2119034982 + g * 0.6806995451 + b * 0.1073969566
    s = r * 0.0883024619 + g * 0.2817188376 + b * 0.6299787005
    l_ = cbrt_positive(lms_l)
    m_ = cbrt_positive(m)
    s_ = cbrt_positive(s)
    return stack_rgb(
        l_ * 0.2104542553 + m_ * 0.7936177850 - s_ * 0.0040720468,
        l_ * 1.9779984951 - m_ * 2.4285922050 + s_ * 0.4505937099,
        l_ * 0.0259040371 + m_ * 0.7827717662 - s_ * 0.8086757660,
    )


def oklab_to_rgb(lab: Tensor) -> Tensor:
    lightness = channel(lab, 0)
    a = channel(lab, 1)
    b = channel(lab, 2)
    l_ = lightness + a * 0.3963377774 + b * 0.2158037573
    m_ = lightness - a * 0.1055613458 - b * 0.0638541728
    s_ = lightness - a * 0.0894841775 - b * 1.2914855480
    l3 = l_ * l_ * l_
    m3 = m_ * m_ * m_
    s3 = s_ * s_ * s_
    return stack_rgb(
        l3 * 4.0767416621 - m3 * 3.3077115913 + s3 * 0.2309699292,
        l3 * -1.2684380046 + m3 * 2.6097574011 - s3 * 0.3413193965,
        l3 * -0.0041960863 - m3 * 0.7034186147 + s3 * 1.7076147010,
    )


def stack_ab(a: Tensor, b: Tensor) -> Tensor:
    return torch.cat([a, b], dim=1)


def stack_lab(lightness: Tensor, ab: Tensor) -> Tensor:
    return torch.cat([lightness, ab], dim=1)


def rotate_ab(ab: Tensor, degrees: Tensor) -> Tensor:
    radians = degrees * DEG_TO_RAD
    cosine = torch.cos(radians)
    sine = torch.sin(radians)
    a = channel(ab, 0)
    b = channel(ab, 1)
    return stack_ab(a * cosine - b * sine, a * sine + b * cosine)


def oklab_hue(ab: Tensor) -> Tensor:
    hue = torch.atan2(channel(ab, 1), channel(ab, 0)) * (180.0 / math.pi)
    return torch.remainder(hue, 360.0)


def hue_direction(angle: Tensor) -> Tensor:
    radians = angle * DEG_TO_RAD
    return stack_ab(torch.cos(radians), torch.sin(radians))


def sector_weight(hue: Tensor, center: float, width_scale: Tensor, smoothness: Tensor) -> Tensor:
    outer = 30.0 * width_scale
    inner = outer * (0.2 + (1.0 - smoothness) * 0.6)
    distance = circular_distance_deg(hue, center)
    return torch.ones_like(distance) - smoothstep_tensor(inner, outer, distance)


def hue_rgb_weights(angle: Tensor) -> Tensor:
    red = (torch.ones_like(angle) - circular_distance_deg(angle, 0.0) / 120.0).clamp(0.0, 1.0)
    green = (
        torch.ones_like(angle) - circular_distance_deg(angle, 120.0) / 120.0
    ).clamp(0.0, 1.0)
    blue = (
        torch.ones_like(angle) - circular_distance_deg(angle, 240.0) / 120.0
    ).clamp(0.0, 1.0)
    total = (red + green + blue).clamp_min(1e-4)
    return stack_rgb(red / total, green / total, blue / total)


def apply_hue_tint(color: Tensor, angle: Tensor, saturation: Tensor, weight: Tensor, scale: float) -> Tensor:
    tint = hue_rgb_weights(angle)
    centered_tint = tint - torch.ones_like(tint) * (1.0 / 3.0)
    return clamp01(color + centered_tint * saturation * weight * scale)


def pseudo_hue_shift_rgb(color: Tensor, shift_degrees: Tensor, scale: float) -> Tensor:
    shift = (shift_degrees / 40.0).clamp(-1.0, 1.0) * scale
    forward = shift.clamp(0.0, 1.0)
    backward = (-shift).clamp(0.0, 1.0)
    r = channel(color, 0)
    g = channel(color, 1)
    b = channel(color, 2)
    forward_color = stack_rgb(
        mix_tensors(r, g, forward),
        mix_tensors(g, b, forward),
        mix_tensors(b, r, forward),
    )
    backward_color = stack_rgb(
        mix_tensors(r, b, backward),
        mix_tensors(g, r, backward),
        mix_tensors(b, g, backward),
    )
    shifted = mix_tensors(color, forward_color, forward)
    return mix_tensors(shifted, backward_color, backward)


def extract_highlights_approx(color: Tensor, threshold: Tensor, feather: Tensor) -> Tensor:
    luma = luminance(color)
    weight = smoothstep_tensor(threshold, threshold + feather.clamp_min(1e-4), luma)
    return color * weight


@lru_cache(maxsize=16)
def _radial_grid(height: int, width: int) -> tuple[Tensor, Tensor]:
    y = torch.linspace(-1.0, 1.0, height, dtype=torch.float32)
    x = torch.linspace(-1.0, 1.0, width, dtype=torch.float32)
    grid_y, grid_x = torch.meshgrid(y, x, indexing="ij")
    return grid_x.unsqueeze(0).unsqueeze(0), grid_y.unsqueeze(0).unsqueeze(0)


def radial_mask(
    height: int,
    width: int,
    *,
    device: torch.device,
    dtype: torch.dtype,
    roundness: Tensor | None = None,
    midpoint: float,
    feather: float,
) -> Tensor:
    x, y = _radial_grid(height, width)
    x = x.to(device=device, dtype=dtype)
    y = y.to(device=device, dtype=dtype)
    if roundness is None:
        roundness = torch.zeros(1, 1, 1, 1, device=device, dtype=dtype)
    else:
        roundness = roundness.to(device=device, dtype=dtype)
    x_scale = torch.ones_like(roundness) + roundness.clamp(0.0, 1.0) * 0.4
    y_scale = torch.ones_like(roundness) + (-roundness).clamp(0.0, 1.0) * 0.4
    distance = torch.sqrt((x * x_scale).pow(2.0) + (y * y_scale).pow(2.0)).clamp(0.0, 1.4143) / 1.4143
    return smoothstep_scalar(midpoint, midpoint + max(feather, 1e-4), distance)


@lru_cache(maxsize=16)
def _uv_grid(height: int, width: int) -> Tensor:
    y = torch.linspace(0.0, 1.0, height, dtype=torch.float32)
    x = torch.linspace(0.0, 1.0, width, dtype=torch.float32)
    grid_y, grid_x = torch.meshgrid(y, x, indexing="ij")
    return torch.stack([grid_x, grid_y], dim=-1).unsqueeze(0)


def uv_grid(height: int, width: int, *, device: torch.device, dtype: torch.dtype) -> Tensor:
    return _uv_grid(height, width).to(device=device, dtype=dtype)


def stack_uv_scalar(x: float, y: float, *, device: torch.device, dtype: torch.dtype) -> Tensor:
    return torch.tensor([x, y], device=device, dtype=dtype).reshape(1, 1, 1, 2)


def fract(x: Tensor) -> Tensor:
    return x - torch.floor(x)


def hash21(cell: Tensor) -> Tensor:
    hashed = fract(
        torch.sin(cell[..., 0] * 127.1 + cell[..., 1] * 311.7) * 43758.5453123
    )
    return hashed.unsqueeze(1)


def hash31(cell: Tensor, seed: float) -> Tensor:
    hashed = fract(
        torch.sin(
            cell[..., 0] * (269.5 + seed * 13.0) + cell[..., 1] * (183.3 + seed * 7.0)
        )
        * (43758.5453123 + seed * 97.0)
    )
    return hashed.unsqueeze(1)


def grain_cell_uv(
    height: int,
    width: int,
    grain_size: Tensor,
    *,
    scale: float,
    angle: float,
    device: torch.device,
    dtype: torch.dtype,
) -> Tensor:
    uv = uv_grid(height, width, device=device, dtype=dtype)
    dims = torch.tensor([width, height], device=device, dtype=dtype).reshape(1, 1, 1, 2)
    centered = uv * dims
    cosine = math.cos(angle)
    sine = math.sin(angle)
    rotated_x = centered[..., 0] * cosine - centered[..., 1] * sine
    rotated_y = centered[..., 0] * sine + centered[..., 1] * cosine
    denominator = (grain_size.clamp_min(0.1) * scale).reshape(-1, 1, 1, 1)
    return torch.floor(torch.stack([rotated_x, rotated_y], dim=-1) / denominator)


def mask(mask_tensor: Tensor, name: str) -> Tensor:
    index = mask_index(name)
    return mask_tensor[:, index : index + 1, :, :]


def apply_masked_mix(base: Tensor, adjusted: Tensor, mask_tensor: Tensor, gate: Tensor) -> Tensor:
    mix = (mask_tensor * gate).clamp(0.0, 1.0)
    return base * (torch.ones_like(mix) - mix) + adjusted * mix


def luminance(color: Tensor) -> Tensor:
    return channel(color, 0) * 0.2126 + channel(color, 1) * 0.7152 + channel(color, 2) * 0.0722


def clamp01(tensor: Tensor) -> Tensor:
    return tensor.clamp(0.0, 1.0)


def smoothstep_scalar(edge0: float, edge1: float, x: Tensor) -> Tensor:
    denom = max(abs(edge1 - edge0), 1e-6)
    t = ((x - edge0) / denom).clamp(0.0, 1.0)
    return t * t * (torch.ones_like(t) * 3.0 - t * 2.0)


def mask_blur(mask_tensor: Tensor) -> Tensor:
    channels = mask_tensor.shape[1]
    kernel = mask_tensor.new_tensor(
        [
            [0.075, 0.14, 0.075],
            [0.14, 0.14, 0.14],
            [0.075, 0.14, 0.075],
        ]
    ).reshape(1, 1, 3, 3)
    padded = F.pad(mask_tensor, (1, 1, 1, 1), mode="replicate")
    return F.conv2d(padded, kernel.expand(channels, -1, -1, -1), groups=channels)


def prepare_semantic_mask(mask_tensor: Tensor) -> Tensor:
    return clamp01(mask_blur(clamp01(mask_tensor)))


def prepare_tonal_mask(
    neutral: Tensor,
    semantic_mask: Tensor,
    threshold: Tensor,
    feather: Tensor,
    highlight: bool,
) -> Tensor:
    rule = mask_blur(tonal_mask_rule(neutral, threshold, feather, highlight))
    merged = torch.maximum(clamp01(semantic_mask), rule)
    return clamp01(mask_blur(merged))


def tonal_mask_rule(
    neutral: Tensor,
    threshold: Tensor,
    feather: Tensor,
    highlight: bool,
) -> Tensor:
    luma = luminance(safe_color(neutral))
    feather = feather.clamp_min(1e-4)
    tonal = smoothstep_tensor(threshold - feather, threshold + feather, luma)
    if not highlight:
        tonal = torch.ones_like(luma) - tonal
    return clamp01(tonal)
