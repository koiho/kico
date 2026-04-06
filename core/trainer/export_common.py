from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import warnings

import torch
from torch import nn

try:
    from .config import TrainingConfig
    from .contract import (
        EXPORT_SCHEMA_VERSION,
        GATE_NAMES,
        MASK_DIM,
        PARAMETER_NAMES,
        TOTAL_GATE_DIM,
        TOTAL_PARAMETER_DIM,
    )
    from .model import StyleParamNet, StyleParamNetConfig
except ImportError:  # pragma: no cover
    from config import TrainingConfig
    from contract import (
        EXPORT_SCHEMA_VERSION,
        GATE_NAMES,
        MASK_DIM,
        PARAMETER_NAMES,
        TOTAL_GATE_DIM,
        TOTAL_PARAMETER_DIM,
    )
    from model import StyleParamNet, StyleParamNetConfig


EXPORT_INPUT_NAMES = ("ref_image", "neutral_preview", "mask_tensor")
EXPORT_OUTPUT_NAMES = ("renderer_params", "module_gates")


class ExportWrapper(nn.Module):
    def __init__(self, model: StyleParamNet) -> None:
        super().__init__()
        self.model = model

    def forward(
        self,
        ref_image: torch.Tensor,
        neutral_preview: torch.Tensor,
        mask_tensor: torch.Tensor,
    ) -> tuple[torch.Tensor, torch.Tensor]:
        out = self.model(ref_image, neutral_preview, mask_tensor)
        return out.params, out.gates


@dataclass(slots=True)
class LoadedExportArtifacts:
    config: TrainingConfig
    checkpoint_path: Path
    model: StyleParamNet
    model_image_size: int
    model_backbone_name: str


def parse_checkpoint_model_metadata(raw: object) -> tuple[int, str] | None:
    if not isinstance(raw, dict):
        return None
    image_size = raw.get("image_size")
    backbone_name = raw.get("backbone_name")
    if image_size is None or backbone_name is None:
        return None
    return int(image_size), str(backbone_name)


def resolve_checkpoint_path(config: TrainingConfig, raw_path: str | None) -> Path:
    if raw_path:
        return Path(raw_path)
    candidates = [config.output_dir / "best.pt", config.output_dir / "last.pt"]
    for path in candidates:
        if path.exists():
            return path
    raise FileNotFoundError(
        f"no checkpoint found, expected one of: {', '.join(str(path) for path in candidates)}"
    )


def resolve_backbone_model_name(backbone_name: str) -> str:
    if backbone_name in {"fastvit_sa24", "fastvit_sa24.apple_in1k"}:
        return "fastvit_sa24.apple_in1k"
    raise ValueError(f"unsupported backbone_name for pytorch export: {backbone_name}")


def load_model_for_export(config: TrainingConfig, checkpoint_arg: str | None) -> LoadedExportArtifacts:
    if checkpoint_arg:
        candidates = [Path(checkpoint_arg)]
    else:
        candidates = [config.output_dir / "best.pt", config.output_dir / "last.pt"]

    missing_paths = []
    load_errors: list[tuple[Path, Exception]] = []
    for checkpoint_path in candidates:
        if not checkpoint_path.exists():
            missing_paths.append(checkpoint_path)
            continue
        try:
            state = torch.load(checkpoint_path, map_location="cpu")
            model_metadata = None
            if isinstance(state, dict):
                model_metadata = parse_checkpoint_model_metadata(state.get("model_metadata"))
            if isinstance(state, dict) and "model" in state:
                state = state["model"]
            if model_metadata is None:
                model_image_size = int(config.image_size)
                model_backbone_name = str(config.backbone_name)
                warnings.warn(
                    f"checkpoint `{checkpoint_path}` is missing model_metadata; "
                    "falling back to export config image_size/backbone_name. "
                    "Legacy checkpoints may export incorrectly if these do not match training."
                )
            else:
                model_image_size, model_backbone_name = model_metadata
                if (
                    model_image_size != int(config.image_size)
                    or model_backbone_name != str(config.backbone_name)
                ):
                    warnings.warn(
                        f"ignoring export config image_size/backbone_name for checkpoint `{checkpoint_path}`; "
                        f"using checkpoint metadata image_size={model_image_size} "
                        f"backbone_name={model_backbone_name}"
                    )
            model = StyleParamNet(
                StyleParamNetConfig(
                    image_size=model_image_size,
                    backbone_model_name=resolve_backbone_model_name(model_backbone_name),
                    pretrained_backbone=False,
                )
            )
            model.load_state_dict(state)
            model.eval()
            if checkpoint_arg is None and checkpoint_path.name != "best.pt":
                warnings.warn(
                    f"falling back to checkpoint `{checkpoint_path}` because higher-priority candidates failed"
                )
            return LoadedExportArtifacts(
                config=config,
                checkpoint_path=checkpoint_path,
                model=model,
                model_image_size=model_image_size,
                model_backbone_name=model_backbone_name,
            )
        except Exception as error:
            load_errors.append((checkpoint_path, error))
            if checkpoint_arg is not None:
                raise RuntimeError(f"failed to load checkpoint `{checkpoint_path}`") from error
            warnings.warn(f"skipping unreadable checkpoint `{checkpoint_path}`: {error}")

    if checkpoint_arg is None and len(missing_paths) == len(candidates):
        raise FileNotFoundError(
            f"no checkpoint found, expected one of: {', '.join(str(path) for path in candidates)}"
        )

    details = ", ".join(f"{path}: {error}" for path, error in load_errors)
    raise RuntimeError(f"no readable checkpoint available for export ({details})")


def build_sample_inputs(image_size: int) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    sample_ref = torch.zeros(1, 3, image_size, image_size, dtype=torch.float32)
    sample_neutral = torch.zeros(1, 3, image_size, image_size, dtype=torch.float32)
    sample_mask = torch.zeros(1, MASK_DIM, image_size, image_size, dtype=torch.float32)
    return sample_ref, sample_neutral, sample_mask


def build_export_metadata(artifacts: LoadedExportArtifacts) -> dict[str, object]:
    return {
        "schema_version": EXPORT_SCHEMA_VERSION,
        "image_size": artifacts.model_image_size,
        "parameter_dim": TOTAL_PARAMETER_DIM,
        "gate_dim": TOTAL_GATE_DIM,
        "parameter_names": list(PARAMETER_NAMES),
        "gate_names": list(GATE_NAMES),
        "backbone_name": artifacts.model_backbone_name,
        "checkpoint": str(artifacts.checkpoint_path),
    }
