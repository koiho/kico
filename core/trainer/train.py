from __future__ import annotations

import argparse
import math
from pathlib import Path
import random

import torch
from torch.utils.data import DataLoader

try:
    from .checkpoint import (
        ResumeState,
        load_checkpoint,
        load_history,
        load_resume_state,
        save_checkpoint,
        save_history,
        save_resume_state,
    )
    from .config import load_default_training_config, load_training_config
    from .data import StyleDataset, load_manifest_entries
    from .loss import StyleParamLoss
    from .model import StyleParamNet, StyleParamNetConfig
except ImportError:  # pragma: no cover
    from checkpoint import (
        ResumeState,
        load_checkpoint,
        load_history,
        load_resume_state,
        save_checkpoint,
        save_history,
        save_resume_state,
    )
    from config import load_default_training_config, load_training_config
    from data import StyleDataset, load_manifest_entries
    from loss import StyleParamLoss
    from model import StyleParamNet, StyleParamNetConfig


def default_device_name() -> str:
    if torch.cuda.is_available():
        return "cuda"
    if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        return "mps"
    return "cpu"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("config", nargs="?")
    parser.add_argument("--device", default=default_device_name())
    return parser.parse_args()


def split_train_val(entries: list, val_ratio: float) -> tuple[list, list]:
    if len(entries) < 2 or val_ratio <= 0.0:
        return entries, []
    rng = random.Random(0xC0DE_CAFE)
    grouped: dict[tuple[str, str, str], list] = {}
    for entry in entries:
        key = (
            str(entry.base_dir),
            entry.neutral_image_path or "",
            entry.neutral_preview_path,
        )
        grouped.setdefault(key, []).append(entry)
    groups = list(grouped.values())
    if len(groups) < 2:
        return list(entries), []
    rng.shuffle(groups)
    val_group_count = min(max(round(len(groups) * val_ratio), 1), len(groups) - 1)
    train_entries = [entry for group in groups[:-val_group_count] for entry in group]
    val_entries = [entry for group in groups[-val_group_count:] for entry in group]
    return train_entries, val_entries


def source_type_counts(entries: list) -> dict[str, int]:
    counts = {"synthetic": 0, "fitted_real_ref": 0}
    for entry in entries:
        counts[entry.source_type] = counts.get(entry.source_type, 0) + 1
    return counts


def infer_training_stage(entries: list) -> str:
    counts = source_type_counts(entries)
    synthetic = counts.get("synthetic", 0)
    fitted = counts.get("fitted_real_ref", 0)
    if synthetic > 0 and fitted == 0:
        return "cold_start"
    if fitted > 0 and synthetic == 0:
        return "augmentation"
    if synthetic == 0 and fitted == 0:
        return "empty"
    return "mixed"


def format_source_counts(entries: list) -> str:
    counts = source_type_counts(entries)
    return f"synthetic={counts.get('synthetic', 0)} fitted_real_ref={counts.get('fitted_real_ref', 0)}"


def checkpoint_model_metadata(config) -> dict[str, object]:
    return {
        "image_size": int(config.image_size),
        "backbone_name": str(config.backbone_name),
    }


def make_model(config) -> StyleParamNet:
    backbone_model_name = "fastvit_sa24.apple_in1k"
    if config.backbone_name not in {"fastvit_sa24", "fastvit_sa24.apple_in1k"}:
        raise ValueError(f"unsupported backbone_name for pytorch trainer: {config.backbone_name}")
    backbone_checkpoint = None if config.init_checkpoint is not None else config.backbone_checkpoint
    if backbone_checkpoint is not None and not backbone_checkpoint.exists():
        raise FileNotFoundError(f"backbone_checkpoint does not exist: {backbone_checkpoint}")
    use_official_pretrained = bool(
        config.pretrained_backbone and config.init_checkpoint is None and backbone_checkpoint is None
    )
    return StyleParamNet(
        StyleParamNetConfig(
            image_size=config.image_size,
            backbone_model_name=backbone_model_name,
            pretrained_backbone=use_official_pretrained,
            backbone_checkpoint=None if backbone_checkpoint is None else str(backbone_checkpoint),
        )
    )


def make_optimizer(model: StyleParamNet, config) -> torch.optim.Optimizer:
    backbone_ids = {id(param) for param in iter_backbone_parameters(model)}
    backbone_params = []
    head_params = []
    for _, param in model.named_parameters():
        if not param.requires_grad:
            continue
        if id(param) in backbone_ids:
            backbone_params.append(param)
        else:
            head_params.append(param)
    return torch.optim.AdamW(
        [
            {
                "params": head_params,
                "lr": config.lr,
                "base_lr": config.lr,
                "is_backbone": False,
            },
            {
                "params": backbone_params,
                "lr": config.lr * config.backbone_lr_scale,
                "base_lr": config.lr * config.backbone_lr_scale,
                "is_backbone": True,
            },
        ],
        weight_decay=config.weight_decay,
    )


def metric_value(tensor: torch.Tensor) -> float:
    return float(tensor.detach().cpu().item())


def set_backbone_trainability(model: StyleParamNet, trainable: bool) -> None:
    model.ref_encoder.train(mode=trainable)
    for param in model.ref_encoder.parameters():
        param.requires_grad_(trainable)


def freeze_backbone_norm_stats(model: StyleParamNet) -> None:
    # Keep BN running stats stable during small-batch backbone fine-tuning.
    for module in model.ref_encoder.modules():
        if isinstance(module, torch.nn.modules.batchnorm._BatchNorm):
            module.eval()


def iter_backbone_parameters(model: StyleParamNet):
    yield from model.ref_encoder.parameters()


def lr_schedule_multiplier(epoch: int, total_epochs: int, warmup_epochs: int, min_lr_ratio: float) -> float:
    if total_epochs <= 1:
        return 1.0
    step = epoch + 1
    if warmup_epochs > 0 and step <= warmup_epochs:
        return max(step / warmup_epochs, 1e-3)
    if total_epochs <= warmup_epochs:
        return 1.0
    progress = (step - warmup_epochs) / max(total_epochs - warmup_epochs, 1)
    cosine = 0.5 * (1.0 + math.cos(math.pi * min(max(progress, 0.0), 1.0)))
    return min_lr_ratio + (1.0 - min_lr_ratio) * cosine


def apply_learning_rates(
    optimizer: torch.optim.Optimizer,
    config,
    epoch: int,
    freeze_backbone: bool,
) -> dict[str, float]:
    multiplier = lr_schedule_multiplier(epoch, config.epochs, config.warmup_epochs, config.min_lr_ratio)
    lrs = {"head_lr": 0.0, "backbone_lr": 0.0}
    for group in optimizer.param_groups:
        base_lr = float(group.get("base_lr", config.lr))
        is_backbone = bool(group.get("is_backbone", False))
        if is_backbone and freeze_backbone:
            group["lr"] = 0.0
            lrs["backbone_lr"] = 0.0
            continue
        group["lr"] = base_lr * multiplier
        if is_backbone:
            lrs["backbone_lr"] = float(group["lr"])
        else:
            lrs["head_lr"] = float(group["lr"])
    return lrs


def run_epoch(
    model,
    loader,
    criterion,
    optimizer,
    device,
    freeze_backbone: bool,
    freeze_backbone_norm_stats_enabled: bool,
    scaler,
    use_amp: bool,
) -> dict[str, float]:
    model.train()
    set_backbone_trainability(model, not freeze_backbone)
    if not freeze_backbone and freeze_backbone_norm_stats_enabled:
        freeze_backbone_norm_stats(model)
    metrics = {
        "loss": 0.0,
        "param_loss": 0.0,
        "gate_loss": 0.0,
        "gate_sparsity": 0.0,
        "param_boundary": 0.0,
        "render_loss": 0.0,
        "reference_render_loss": 0.0,
        "pyramid_loss": 0.0,
        "edge_loss": 0.0,
        "oklab_loss": 0.0,
        "style_loss": 0.0,
        "fitted_ratio": 0.0,
    }
    steps = 0
    for batch in loader:
        batch = {k: v.to(device) for k, v in batch.items()}
        optimizer.zero_grad(set_to_none=True)
        with torch.autocast(device_type=device.type, dtype=torch.float16, enabled=use_amp):
            if freeze_backbone:
                out = model.forward_frozen_backbone(
                    batch["ref_image"],
                    batch["neutral_preview"],
                    batch["mask_tensor"],
                )
            else:
                out = model(batch["ref_image"], batch["neutral_preview"], batch["mask_tensor"])
            loss = criterion(
                out.params,
                batch["target_params"],
                out.gates,
                batch["target_gates"],
                batch["ref_image"],
                batch["neutral_image"],
                batch["mask_tensor"],
                batch["synthetic_mask"],
                batch["fitted_mask"],
                batch["fit_confidence"],
                batch["render_supervision_mask"],
            )
        scaler.scale(loss.loss).backward()
        scaler.unscale_(optimizer)
        torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
        scaler.step(optimizer)
        scaler.update()
        metrics["loss"] += metric_value(loss.loss)
        metrics["param_loss"] += metric_value(loss.param_loss)
        metrics["gate_loss"] += metric_value(loss.gate_loss)
        metrics["gate_sparsity"] += metric_value(loss.gate_sparsity)
        metrics["param_boundary"] += metric_value(loss.param_boundary)
        metrics["render_loss"] += metric_value(loss.render_loss)
        metrics["reference_render_loss"] += metric_value(loss.reference_render_loss)
        metrics["pyramid_loss"] += metric_value(loss.pyramid_loss)
        metrics["edge_loss"] += metric_value(loss.edge_loss)
        metrics["oklab_loss"] += metric_value(loss.oklab_loss)
        metrics["style_loss"] += metric_value(loss.style_loss)
        metrics["fitted_ratio"] += metric_value(loss.fitted_ratio)
        steps += 1
    if steps:
        for key in metrics:
            metrics[key] /= steps
    return metrics


@torch.no_grad()
def evaluate(model, loader, criterion, device, use_amp: bool) -> dict[str, float]:
    model.eval()
    metrics = {
        "loss": 0.0,
        "param_loss": 0.0,
        "gate_loss": 0.0,
        "gate_sparsity": 0.0,
        "param_boundary": 0.0,
        "render_loss": 0.0,
        "reference_render_loss": 0.0,
        "pyramid_loss": 0.0,
        "edge_loss": 0.0,
        "oklab_loss": 0.0,
        "style_loss": 0.0,
        "fitted_ratio": 0.0,
    }
    steps = 0
    for batch in loader:
        batch = {k: v.to(device) for k, v in batch.items()}
        with torch.autocast(device_type=device.type, dtype=torch.float16, enabled=use_amp):
            out = model(batch["ref_image"], batch["neutral_preview"], batch["mask_tensor"])
            loss = criterion(
                out.params,
                batch["target_params"],
                out.gates,
                batch["target_gates"],
                batch["ref_image"],
                batch["neutral_image"],
                batch["mask_tensor"],
                batch["synthetic_mask"],
                batch["fitted_mask"],
                batch["fit_confidence"],
                batch["render_supervision_mask"],
            )
        metrics["loss"] += metric_value(loss.loss)
        metrics["param_loss"] += metric_value(loss.param_loss)
        metrics["gate_loss"] += metric_value(loss.gate_loss)
        metrics["gate_sparsity"] += metric_value(loss.gate_sparsity)
        metrics["param_boundary"] += metric_value(loss.param_boundary)
        metrics["render_loss"] += metric_value(loss.render_loss)
        metrics["reference_render_loss"] += metric_value(loss.reference_render_loss)
        metrics["pyramid_loss"] += metric_value(loss.pyramid_loss)
        metrics["edge_loss"] += metric_value(loss.edge_loss)
        metrics["oklab_loss"] += metric_value(loss.oklab_loss)
        metrics["style_loss"] += metric_value(loss.style_loss)
        metrics["fitted_ratio"] += metric_value(loss.fitted_ratio)
        steps += 1
    if steps:
        for key in metrics:
            metrics[key] /= steps
    return metrics


def main() -> None:
    args = parse_args()
    if args.config:
        config = load_training_config(args.config)
    else:
        config = load_default_training_config(Path(__file__).resolve().parent)
    device = torch.device(args.device)
    use_amp = bool(config.amp and device.type == "cuda")
    loader_common = {
        "batch_size": config.batch_size,
        "num_workers": config.num_workers,
        "pin_memory": device.type == "cuda",
    }
    if config.num_workers > 0:
        loader_common["persistent_workers"] = True
    entries = load_manifest_entries(config.manifest_path)
    if config.val_manifest_path:
        train_entries = entries
        val_entries = load_manifest_entries(config.val_manifest_path)
    else:
        train_entries, val_entries = split_train_val(entries, config.val_ratio)
    train_loader = DataLoader(
        StyleDataset(train_entries, config.image_size),
        shuffle=True,
        **loader_common,
    )
    val_loader = None if not val_entries else DataLoader(
        StyleDataset(val_entries, config.image_size),
        shuffle=False,
        **loader_common,
    )
    model = make_model(config).to(device)
    optimizer = make_optimizer(model, config)
    scaler = torch.cuda.amp.GradScaler(enabled=use_amp)
    criterion = StyleParamLoss(config.loss)
    history = []
    best_val = None
    start_epoch = 0
    config.output_dir.mkdir(parents=True, exist_ok=True)

    if config.resume and config.init_checkpoint is not None:
        print(
            f"resume=true, ignoring init_checkpoint={config.init_checkpoint} "
            f"and restoring from {config.output_dir / 'last.pt'}"
        )

    if config.resume:
        resume_checkpoint = config.output_dir / "last.pt"
        resume_state = config.output_dir / "resume_state.json"
        if not resume_checkpoint.exists():
            raise FileNotFoundError(f"resume=true but missing checkpoint: {resume_checkpoint}")
        if not resume_state.exists():
            raise FileNotFoundError(f"resume=true but missing resume state: {resume_state}")
        checkpoint = load_checkpoint(resume_checkpoint, device=device)
        model.load_state_dict(checkpoint["model"])
        if "optimizer" in checkpoint:
            optimizer.load_state_dict(checkpoint["optimizer"])
        state = load_resume_state(config.output_dir)
        history = load_history(config.output_dir)
        start_epoch = state.completed_epochs
        best_val = state.best_val
    elif config.init_checkpoint:
        if not config.init_checkpoint.exists():
            raise FileNotFoundError(f"init_checkpoint does not exist: {config.init_checkpoint}")
        checkpoint = load_checkpoint(config.init_checkpoint, device=device)
        if isinstance(checkpoint, dict) and "model" in checkpoint:
            checkpoint = checkpoint["model"]
        incompatible = model.load_state_dict(checkpoint, strict=False)
        if incompatible.missing_keys or incompatible.unexpected_keys:
            details = []
            if incompatible.missing_keys:
                details.append(f"missing_keys={sorted(incompatible.missing_keys)}")
            if incompatible.unexpected_keys:
                details.append(f"unexpected_keys={sorted(incompatible.unexpected_keys)}")
            detail_text = " ".join(details)
            raise RuntimeError(
                "init_checkpoint is not a full compatible trainer checkpoint; "
                f"{detail_text}. Use backbone_checkpoint for backbone-only initialization."
            )

    if config.resume:
        init_source = f"resume:{config.output_dir / 'last.pt'}"
    elif config.init_checkpoint is not None:
        init_source = f"trainer_checkpoint:{config.init_checkpoint}"
    elif config.backbone_checkpoint is not None:
        init_source = f"local_backbone_checkpoint:{config.backbone_checkpoint}"
    elif config.pretrained_backbone:
        init_source = "official_timm_fastvit_pretrained"
    else:
        init_source = "random_backbone_init"
    stage_name = infer_training_stage(train_entries)
    train_source_summary = format_source_counts(train_entries)
    val_source_summary = format_source_counts(val_entries) if val_entries else "synthetic=0 fitted_real_ref=0"

    print(
        f"pytorch training | stage={stage_name} train_samples={len(train_entries)} "
        f"train_sources=[{train_source_summary}] val_samples={len(val_entries)} "
        f"val_sources=[{val_source_summary}] image_size={config.image_size} "
        f"epochs={config.epochs} batch_size={config.batch_size} start_epoch={start_epoch} "
        f"device={device.type} init={init_source} amp={use_amp}"
    )

    for epoch in range(start_epoch, config.epochs):
        freeze_backbone = epoch < config.freeze_backbone_epochs
        current_lrs = apply_learning_rates(optimizer, config, epoch, freeze_backbone)
        train_metrics = run_epoch(
            model,
            train_loader,
            criterion,
            optimizer,
            device,
            freeze_backbone,
            config.freeze_backbone_norm_stats,
            scaler,
            use_amp,
        )
        val_metrics = None if val_loader is None else evaluate(model, val_loader, criterion, device, use_amp)
        record = {
            "epoch": epoch + 1,
            "freeze_backbone": freeze_backbone,
            **current_lrs,
            "train": train_metrics,
            "val": val_metrics,
        }
        history.append(record)
        print(record)

        save_checkpoint(
            config.output_dir,
            "last",
            model.state_dict(),
            optimizer.state_dict(),
            model_metadata=checkpoint_model_metadata(config),
        )
        save_history(config.output_dir, history)
        if val_metrics is not None:
            val_loss = float(val_metrics["loss"])
            if best_val is None or val_loss < best_val:
                best_val = val_loss
                save_checkpoint(
                    config.output_dir,
                    "best",
                    model.state_dict(),
                    model_metadata=checkpoint_model_metadata(config),
                )
        save_resume_state(config.output_dir, ResumeState(completed_epochs=epoch + 1, best_val=best_val))


if __name__ == "__main__":
    main()
