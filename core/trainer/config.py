from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import json
import tomllib


@dataclass(slots=True)
class LossConfig:
    synthetic_param_weight: float = 1.0
    synthetic_gate_weight: float = 0.35
    synthetic_gate_sparsity_weight: float = 0.0
    synthetic_param_boundary_weight: float = 0.03
    fitted_param_weight: float = 0.40
    fitted_gate_weight: float = 0.20
    fitted_gate_sparsity_weight: float = 0.0
    fitted_param_boundary_weight: float = 0.02
    synthetic_render_weight: float = 0.08
    synthetic_reference_render_weight: float = 0.04
    synthetic_pyramid_weight: float = 0.03
    synthetic_edge_weight: float = 0.01
    synthetic_oklab_weight: float = 0.02
    synthetic_style_weight: float = 0.005
    fitted_render_weight: float = 0.05
    fitted_reference_render_weight: float = 0.06
    fitted_pyramid_weight: float = 0.02
    fitted_edge_weight: float = 0.01
    fitted_oklab_weight: float = 0.04
    fitted_style_weight: float = 0.01
    huber_delta: float = 0.15
    param_boundary_margin: float = 0.08
    param_boundary_target_margin: float = 0.12
    proxy_render_enabled: bool = True
    proxy_global_color: bool = True
    proxy_local: bool = True
    proxy_optics: bool = False
    proxy_texture: bool = False
    proxy_finish: bool = True

    @classmethod
    def from_mapping(cls, raw: dict | None) -> "LossConfig":
        if not raw:
            return cls()
        valid_keys = set(cls.__dataclass_fields__.keys())
        unknown_keys = sorted(set(raw.keys()) - valid_keys)
        if unknown_keys:
            raise ValueError(f"unknown loss config keys: {', '.join(unknown_keys)}")
        cfg = cls()
        for key, value in raw.items():
            setattr(cfg, key, value)
        return cfg


@dataclass(slots=True)
class TrainingConfig:
    manifest_path: Path
    val_manifest_path: Path | None = None
    init_checkpoint: Path | None = None
    backbone_checkpoint: Path | None = None
    output_dir: Path | None = None
    image_size: int = 256
    epochs: int = 20
    batch_size: int = 16
    num_workers: int = 4
    lr: float = 1e-3
    weight_decay: float = 1e-4
    freeze_backbone_epochs: int = 3
    backbone_lr_scale: float = 0.1
    warmup_epochs: int = 1
    min_lr_ratio: float = 0.1
    val_ratio: float = 0.1
    resume: bool = False
    backbone_name: str = "fastvit_sa24"
    pretrained_backbone: bool = True
    amp: bool = True
    loss: LossConfig = field(default_factory=LossConfig)

    def resolve(self, base_dir: Path) -> "TrainingConfig":
        def rel(path: Path | None) -> Path | None:
            if path is None or path.is_absolute():
                return path
            return (base_dir / path).resolve()

        self.manifest_path = rel(self.manifest_path)  # type: ignore[assignment]
        self.val_manifest_path = rel(self.val_manifest_path)
        self.init_checkpoint = rel(self.init_checkpoint)
        self.backbone_checkpoint = rel(self.backbone_checkpoint)
        if self.output_dir is None:
            self.output_dir = self.manifest_path.parent / "pytorch_checkpoints"
        else:
            self.output_dir = rel(self.output_dir)
        return self


def load_training_config(path: str | Path) -> TrainingConfig:
    path = Path(path)
    raw_text = path.read_text(encoding="utf-8")
    if path.suffix == ".toml":
        raw = tomllib.loads(raw_text)
    elif path.suffix == ".json":
        raw = json.loads(raw_text)
    else:
        raise ValueError(f"unsupported config extension: {path.suffix}")

    valid_keys = set(TrainingConfig.__dataclass_fields__.keys())
    unknown_keys = sorted(set(raw.keys()) - valid_keys)
    if unknown_keys:
        raise ValueError(f"unknown training config keys: {', '.join(unknown_keys)}")

    cfg = TrainingConfig(
        manifest_path=Path(raw["manifest_path"]),
        val_manifest_path=Path(raw["val_manifest_path"]) if raw.get("val_manifest_path") else None,
        init_checkpoint=Path(raw["init_checkpoint"]) if raw.get("init_checkpoint") else None,
        backbone_checkpoint=Path(raw["backbone_checkpoint"]) if raw.get("backbone_checkpoint") else None,
        output_dir=Path(raw["output_dir"]) if raw.get("output_dir") else None,
        image_size=raw.get("image_size", 256),
        epochs=raw.get("epochs", 20),
        batch_size=raw.get("batch_size", 16),
        num_workers=raw.get("num_workers", 4),
        lr=raw.get("lr", 1e-3),
        weight_decay=raw.get("weight_decay", 1e-4),
        freeze_backbone_epochs=raw.get("freeze_backbone_epochs", 3),
        backbone_lr_scale=raw.get("backbone_lr_scale", 0.1),
        warmup_epochs=raw.get("warmup_epochs", 1),
        min_lr_ratio=raw.get("min_lr_ratio", 0.1),
        val_ratio=raw.get("val_ratio", 0.1),
        resume=raw.get("resume", False),
        backbone_name=raw.get("backbone_name", "fastvit_sa24"),
        pretrained_backbone=raw.get("pretrained_backbone", True),
        amp=raw.get("amp", True),
        loss=LossConfig.from_mapping(raw.get("loss")),
    )
    return cfg.resolve(path.parent.resolve())


def load_default_training_config(search_dir: str | Path | None = None) -> TrainingConfig:
    base_dir = Path(search_dir) if search_dir is not None else Path.cwd()
    candidates = (
        "training.toml",
        "training.json",
        "training.cold_start.toml",
        "training.augmentation.toml",
        "config/training.toml",
        "config/training.json",
        "config/training.cold_start.toml",
        "config/training.augmentation.toml",
    )
    for relative_path in candidates:
        path = base_dir / relative_path
        if path.exists():
            return load_training_config(path)
    raise FileNotFoundError(
        f"no training config found in {base_dir}, expected one of: {', '.join(candidates)}"
    )
