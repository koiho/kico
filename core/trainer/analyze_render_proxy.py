from __future__ import annotations

import argparse
import json
from pathlib import Path

import torch

try:
    from .data import StyleDataset, load_manifest_entries
    from .loss import edge_l1, oklab_l1, srgb_to_linear
    from .render import pyramid_l1, soft_render_approx
except ImportError:  # pragma: no cover
    from data import StyleDataset, load_manifest_entries
    from loss import edge_l1, oklab_l1, srgb_to_linear
    from render import pyramid_l1, soft_render_approx


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit trainer soft_render_approx against real renderer outputs stored in a manifest"
    )
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--image-size", type=int, default=256)
    parser.add_argument("--limit", type=int, default=0, help="0 means no limit")
    parser.add_argument(
        "--include-fitted",
        action="store_true",
        help="include fitted_real_ref samples; by default only synthetic samples are audited",
    )
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def scalar_l1(pred: torch.Tensor, target: torch.Tensor) -> torch.Tensor:
    batch, _, height, width = pred.shape
    return (pred - target).abs().reshape(batch, 3, height * width).mean(dim=2).mean(dim=1)


@torch.no_grad()
def main() -> None:
    args = parse_args()
    entries = load_manifest_entries(args.manifest)
    if not args.include_fitted:
        entries = [entry for entry in entries if entry.source_type == "synthetic"]
    entries = [entry for entry in entries if entry.neutral_image_path is not None]
    if args.limit > 0:
        entries = entries[: args.limit]
    if not entries:
        raise SystemExit("no eligible manifest entries found for proxy audit")

    dataset = StyleDataset(entries, args.image_size)
    aggregates = {
        "count": 0,
        "render_l1": 0.0,
        "pyramid_l1": 0.0,
        "edge_l1": 0.0,
        "oklab_l1": 0.0,
    }

    for index in range(len(dataset)):
        sample = dataset[index]
        if float(sample["render_supervision_mask"].item()) <= 0.0:
            continue

        ref_image = sample["ref_image"].unsqueeze(0)
        neutral_image = sample["neutral_image"].unsqueeze(0)
        mask_tensor = sample["mask_tensor"].unsqueeze(0)
        target_params = sample["target_params"].unsqueeze(0)
        target_gates = sample["target_gates"].unsqueeze(0)

        proxy = soft_render_approx(neutral_image, target_params, target_gates, mask_tensor)
        reference_linear = srgb_to_linear(ref_image)

        aggregates["count"] += 1
        aggregates["render_l1"] += float(scalar_l1(proxy, reference_linear).item())
        aggregates["pyramid_l1"] += float(pyramid_l1(proxy, reference_linear, 3).item())
        aggregates["edge_l1"] += float(edge_l1(proxy, reference_linear).item())
        aggregates["oklab_l1"] += float(oklab_l1(proxy, reference_linear).item())

    if aggregates["count"] == 0:
        raise SystemExit("no samples with render supervision were available for proxy audit")

    count = float(aggregates["count"])
    summary = {
        "manifest": str(args.manifest),
        "image_size": args.image_size,
        "sample_count": aggregates["count"],
        "mean_render_l1": aggregates["render_l1"] / count,
        "mean_pyramid_l1": aggregates["pyramid_l1"] / count,
        "mean_edge_l1": aggregates["edge_l1"] / count,
        "mean_oklab_l1": aggregates["oklab_l1"] / count,
    }
    print(json.dumps(summary, indent=2 if args.pretty else None, sort_keys=True))


if __name__ == "__main__":
    main()
