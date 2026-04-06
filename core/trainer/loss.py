from __future__ import annotations

from dataclasses import dataclass

import torch
from torch import Tensor, nn

try:
    from .config import LossConfig
    from .contract import PARAMETER_NAMES, TOTAL_PARAMETER_DIM, parameter_index
    from .render import RenderApproxConfig, edge_l1, pyramid_l1, rgb_to_oklab, soft_render_approx
except ImportError:  # pragma: no cover
    from config import LossConfig
    from contract import PARAMETER_NAMES, TOTAL_PARAMETER_DIM, parameter_index
    from render import RenderApproxConfig, edge_l1, pyramid_l1, rgb_to_oklab, soft_render_approx


CONTRAST_INDEX = parameter_index("contrast")
CONTRAST_PIVOT_INDEX = parameter_index("contrast_pivot")
BOUNDARY_SENSITIVE_PARAM_INDICES = (
    (CONTRAST_INDEX, 1.0),
    (CONTRAST_PIVOT_INDEX, 0.75),
)


@dataclass(slots=True)
class LossBreakdown:
    loss: Tensor
    param_loss: Tensor
    gate_loss: Tensor
    gate_sparsity: Tensor
    param_boundary: Tensor
    render_loss: Tensor
    reference_render_loss: Tensor
    pyramid_loss: Tensor
    edge_loss: Tensor
    oklab_loss: Tensor
    style_loss: Tensor
    fitted_ratio: Tensor


def weighted_batch_mean(values: Tensor, weights: Tensor) -> Tensor:
    weights = weights.reshape(values.shape[0])
    weighted = values * weights
    return weighted.sum() / weights.sum().clamp_min(1e-6)


def masked_metric_mean(values: Tensor, mask: Tensor) -> Tensor:
    mask = mask.reshape(values.shape[0])
    weighted = values * mask
    return weighted.sum() / mask.sum().clamp_min(1e-6)


def auxiliary_loss_scale(param_loss_per: Tensor, gate_loss_per: Tensor, delta: float) -> Tensor:
    combined = param_loss_per + gate_loss_per
    scale = torch.exp(-combined.detach() / max(delta, 1e-6))
    return scale.clamp_(0.2, 1.0)


class StyleParamLoss(nn.Module):
    def __init__(self, config: LossConfig) -> None:
        super().__init__()
        self.config = config
        self.huber_delta = float(config.huber_delta)
        self.render_config = RenderApproxConfig(
            enable_global_color=bool(config.proxy_global_color),
            enable_local=bool(config.proxy_local),
            enable_optics=bool(config.proxy_optics),
            enable_texture=bool(config.proxy_texture),
            enable_finish=bool(config.proxy_finish),
        )
        self.render_loss_enabled = bool(
            config.proxy_render_enabled
            and (
                self.render_config.enable_global_color
                or self.render_config.enable_local
                or self.render_config.enable_optics
                or self.render_config.enable_texture
                or self.render_config.enable_finish
            )
        )
        self.register_buffer(
            "param_weights",
            torch.tensor(build_param_weights(), dtype=torch.float32).reshape(1, TOTAL_PARAMETER_DIM),
            persistent=False,
        )

    def forward(
        self,
        pred_params: Tensor,
        target_params: Tensor,
        pred_gates: Tensor,
        target_gates: Tensor,
        reference_image: Tensor,
        neutral_image: Tensor,
        mask_tensor: Tensor,
        synthetic_mask: Tensor,
        fitted_mask: Tensor,
        fit_confidence: Tensor,
        render_supervision_mask: Tensor,
    ) -> LossBreakdown:
        fitted_weight = fitted_mask * fit_confidence
        param_loss_per = weighted_pseudo_huber(
            pred_params,
            target_params,
            self.huber_delta,
            self.param_weights.to(device=pred_params.device, dtype=pred_params.dtype),
        ).mean(dim=1)
        gate_loss_per = weighted_pseudo_huber(
            pred_gates,
            target_gates,
            self.huber_delta,
            None,
        ).mean(dim=1)
        gate_sparsity_per = pred_gates.mean(dim=1)
        param_boundary_per = boundary_sensitive_param_loss(
            pred_params,
            target_params,
            self.config.param_boundary_margin,
            self.config.param_boundary_target_margin,
        )
        aux_scale = auxiliary_loss_scale(param_loss_per, gate_loss_per, self.huber_delta).reshape(-1, 1)
        if self.render_loss_enabled and bool(render_supervision_mask.detach().amax().item() > 0.0):
            pred_rendered = soft_render_approx(
                neutral_image,
                pred_params,
                pred_gates,
                mask_tensor,
                self.render_config,
            )
            target_rendered = soft_render_approx(
                neutral_image,
                target_params,
                target_gates,
                mask_tensor,
                self.render_config,
            )
            batch_size, _, render_height, render_width = pred_rendered.shape
            reference_linear = srgb_to_linear(reference_image)
            render_loss_per = (
                (pred_rendered - target_rendered)
                .abs()
                .reshape(batch_size, 3, render_height * render_width)
                .mean(dim=2)
                .mean(dim=1)
            )
            reference_render_loss_per = (
                (pred_rendered - reference_linear)
                .abs()
                .reshape(batch_size, 3, render_height * render_width)
                .mean(dim=2)
                .mean(dim=1)
            )
            pyramid_loss_per = pyramid_l1(pred_rendered, reference_linear, 3)
            edge_loss_per = edge_l1(pred_rendered, reference_linear)
            oklab_loss_per = oklab_l1(pred_rendered, reference_linear)
            style_loss_per = style_moment_loss(pred_rendered, reference_linear)
        else:
            zeros = torch.zeros_like(param_loss_per)
            render_loss_per = zeros
            reference_render_loss_per = zeros
            pyramid_loss_per = zeros
            edge_loss_per = zeros
            oklab_loss_per = zeros
            style_loss_per = zeros
        param_route_weight = (
            synthetic_mask * self.config.synthetic_param_weight
            + fitted_weight * self.config.fitted_param_weight
        )
        gate_route_weight = (
            synthetic_mask * self.config.synthetic_gate_weight
            + fitted_weight * self.config.fitted_gate_weight
        )
        gate_sparsity_route_weight = (
            synthetic_mask * self.config.synthetic_gate_sparsity_weight
            + fitted_weight * self.config.fitted_gate_sparsity_weight
        ) * aux_scale
        param_boundary_route_weight = (
            synthetic_mask * self.config.synthetic_param_boundary_weight
            + fitted_weight * self.config.fitted_param_boundary_weight
        )
        render_route_weight = (
            synthetic_mask * self.config.synthetic_render_weight
            + fitted_weight * self.config.fitted_render_weight
        ) * aux_scale * render_supervision_mask
        reference_render_route_weight = (
            synthetic_mask * self.config.synthetic_reference_render_weight
            + fitted_weight * self.config.fitted_reference_render_weight
        ) * aux_scale * render_supervision_mask
        pyramid_route_weight = (
            synthetic_mask * self.config.synthetic_pyramid_weight
            + fitted_weight * self.config.fitted_pyramid_weight
        ) * aux_scale * render_supervision_mask
        edge_route_weight = (
            synthetic_mask * self.config.synthetic_edge_weight
            + fitted_weight * self.config.fitted_edge_weight
        ) * aux_scale * render_supervision_mask
        oklab_route_weight = (
            synthetic_mask * self.config.synthetic_oklab_weight
            + fitted_weight * self.config.fitted_oklab_weight
        ) * aux_scale * render_supervision_mask
        style_route_weight = (
            synthetic_mask * self.config.synthetic_style_weight
            + fitted_weight * self.config.fitted_style_weight
        ) * aux_scale * render_supervision_mask
        param_loss = param_loss_per.mean()
        gate_loss = gate_loss_per.mean()
        gate_sparsity = gate_sparsity_per.mean()
        param_boundary = param_boundary_per.mean()
        render_loss = masked_metric_mean(render_loss_per, render_supervision_mask)
        reference_render_loss = masked_metric_mean(reference_render_loss_per, render_supervision_mask)
        pyramid_loss = masked_metric_mean(pyramid_loss_per, render_supervision_mask)
        edge_loss = masked_metric_mean(edge_loss_per, render_supervision_mask)
        oklab_loss = masked_metric_mean(oklab_loss_per, render_supervision_mask)
        style_loss = masked_metric_mean(style_loss_per, render_supervision_mask)
        total = (
            weighted_batch_mean(param_loss_per, param_route_weight)
            + weighted_batch_mean(gate_loss_per, gate_route_weight)
            + weighted_batch_mean(gate_sparsity_per, gate_sparsity_route_weight)
            + weighted_batch_mean(param_boundary_per, param_boundary_route_weight)
            + weighted_batch_mean(render_loss_per, render_route_weight)
            + weighted_batch_mean(reference_render_loss_per, reference_render_route_weight)
            + weighted_batch_mean(pyramid_loss_per, pyramid_route_weight)
            + weighted_batch_mean(edge_loss_per, edge_route_weight)
            + weighted_batch_mean(oklab_loss_per, oklab_route_weight)
            + weighted_batch_mean(style_loss_per, style_route_weight)
        )
        return LossBreakdown(
            loss=total,
            param_loss=param_loss,
            gate_loss=gate_loss,
            gate_sparsity=gate_sparsity,
            param_boundary=param_boundary,
            render_loss=render_loss,
            reference_render_loss=reference_render_loss,
            pyramid_loss=pyramid_loss,
            edge_loss=edge_loss,
            oklab_loss=oklab_loss,
            style_loss=style_loss,
            fitted_ratio=fitted_mask.mean(),
        )


def weighted_pseudo_huber(pred: Tensor, target: Tensor, delta: float, weights: Tensor | None) -> Tensor:
    diff = (pred - target).abs()
    scaled = (diff / delta).pow(2.0)
    huber = (scaled + 1.0).sqrt().sub(1.0) * (delta * delta)
    if weights is not None:
        huber = huber * weights
    return huber


def boundary_sensitive_param_loss(
    pred_params: Tensor,
    target_params: Tensor,
    boundary_margin: float,
    target_margin: float,
) -> Tensor:
    if boundary_margin <= 0.0:
        return pred_params.new_zeros((pred_params.shape[0],))
    penalties = []
    for index, weight in BOUNDARY_SENSITIVE_PARAM_INDICES:
        pred = pred_params[:, index]
        target = target_params[:, index]
        pred_distance = torch.minimum(pred, 1.0 - pred)
        target_distance = torch.minimum(target, 1.0 - target)
        pred_penalty = ((boundary_margin - pred_distance).clamp_min(0.0) / max(boundary_margin, 1e-6)).pow(2.0)
        target_interior = ((target_distance - target_margin).clamp_min(0.0) / max(target_margin, 1e-6)).clamp(
            0.0,
            1.0,
        )
        penalties.append(pred_penalty * target_interior * weight)
    return torch.stack(penalties, dim=1).mean(dim=1)


def oklab_l1(pred: Tensor, target: Tensor) -> Tensor:
    pred_lab = rgb_to_oklab(pred.clamp_min(0.0))
    target_lab = rgb_to_oklab(target.clamp_min(0.0))
    batch = pred_lab.shape[0]
    l_loss = (pred_lab[:, 0:1] - target_lab[:, 0:1]).abs().reshape(batch, -1).mean(dim=1)
    ab_loss = (pred_lab[:, 1:3] - target_lab[:, 1:3]).abs().reshape(batch, -1).mean(dim=1)
    return l_loss * 0.8 + ab_loss * 1.2


def srgb_to_linear(image: Tensor) -> Tensor:
    low = image / 12.92
    high = ((image + 0.055) / 1.055).clamp_min(0.0).pow(2.4)
    return torch.where(image <= 0.04045, low, high)


def style_moment_loss(pred: Tensor, target: Tensor) -> Tensor:
    pred_lab = rgb_to_oklab(pred.clamp_min(0.0))
    target_lab = rgb_to_oklab(target.clamp_min(0.0))
    pred_mean, pred_std = channel_moments(pred_lab)
    target_mean, target_std = channel_moments(target_lab)
    mean_loss = (pred_mean - target_mean).abs()
    std_loss = (pred_std - target_std).abs()
    channel_weight = torch.tensor([0.7, 1.15, 1.15], device=pred.device, dtype=pred.dtype).reshape(1, 3)
    return ((mean_loss + std_loss) * channel_weight).mean(dim=1)


def channel_moments(image: Tensor) -> tuple[Tensor, Tensor]:
    flat = image.reshape(image.shape[0], image.shape[1], -1)
    mean = flat.mean(dim=2)
    var = (flat - mean.unsqueeze(2)).pow(2.0).mean(dim=2)
    std = var.clamp_min(1e-8).sqrt()
    return mean, std


def build_param_weights() -> list[float]:
    out = []
    for name in PARAMETER_NAMES:
        if name in {"exposure_ev", "contrast", "contrast_pivot", "global_saturation"}:
            out.append(3.0)
        elif name in {
            "global_vibrance",
            "blacks",
            "whites",
            "shadows",
            "highlights",
            "warmth_bias",
            "fade",
            "final_gamma_bias",
        }:
            out.append(1.5)
        else:
            out.append(1.0)
    return out
