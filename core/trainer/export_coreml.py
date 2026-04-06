from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import tomllib

import coremltools as ct
import torch

try:
    from .config import load_default_training_config, load_training_config
    from .export_common import (
        EXPORT_INPUT_NAMES,
        EXPORT_OUTPUT_NAMES,
        ExportWrapper,
        build_export_metadata,
        build_sample_inputs,
        load_model_for_export,
    )
except ImportError:  # pragma: no cover
    import sys

    sys.path.append(str(Path(__file__).resolve().parent))
    from config import load_default_training_config, load_training_config
    from export_common import (
        EXPORT_INPUT_NAMES,
        EXPORT_OUTPUT_NAMES,
        ExportWrapper,
        build_export_metadata,
        build_sample_inputs,
        load_model_for_export,
    )


@dataclass(slots=True)
class CoreMLExportConfig:
    training_config: Path
    output: Path
    checkpoint: Path | None = None
    image_size: int | None = None
    backbone_name: str | None = None

    def resolve(self, base_dir: Path) -> "CoreMLExportConfig":
        def rel(path: Path | None) -> Path | None:
            if path is None or path.is_absolute():
                return path
            return (base_dir / path).resolve()

        self.training_config = rel(self.training_config)  # type: ignore[assignment]
        self.output = rel(self.output)  # type: ignore[assignment]
        self.checkpoint = rel(self.checkpoint)
        return self


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config")
    parser.add_argument("--checkpoint")
    parser.add_argument("--output")
    parser.add_argument("--export-config")
    return parser.parse_args()


def load_export_config(path: str | Path) -> CoreMLExportConfig:
    path = Path(path)
    raw_text = path.read_text(encoding="utf-8")
    if path.suffix == ".toml":
        raw = tomllib.loads(raw_text)
    elif path.suffix == ".json":
        raw = json.loads(raw_text)
    else:
        raise ValueError(f"unsupported export config extension: {path.suffix}")

    valid_keys = set(CoreMLExportConfig.__dataclass_fields__.keys())
    unknown_keys = sorted(set(raw.keys()) - valid_keys)
    if unknown_keys:
        raise ValueError(f"unknown export config keys: {', '.join(unknown_keys)}")

    config = CoreMLExportConfig(
        training_config=Path(raw.get("training_config", "training.toml")),
        output=Path(raw["output"]),
        checkpoint=Path(raw["checkpoint"]) if raw.get("checkpoint") else None,
        image_size=raw.get("image_size"),
        backbone_name=raw.get("backbone_name"),
    )
    return config.resolve(path.parent.resolve())


def find_default_export_config() -> Path | None:
    search_dirs = [Path(__file__).resolve().parent, Path.cwd()]
    for search_dir in search_dirs:
        for relative_path in (
            "export_coreml.toml",
            "export_coreml.json",
            "config/export_coreml.toml",
            "config/export_coreml.json",
        ):
            path = search_dir / relative_path
            if path.exists():
                return path
    return None


def normalize_output_path(raw_path: str | Path) -> Path:
    path = Path(raw_path)
    if path.suffix not in {".mlpackage", ".mlmodel"}:
        return path.with_suffix(".mlpackage")
    if path.suffix == ".mlmodel":
        return path.with_suffix(".mlpackage")
    return path


def main() -> None:
    args = parse_args()
    export_config = None
    if args.export_config:
        export_config = load_export_config(args.export_config)
    elif not any((args.config, args.checkpoint, args.output)):
        default_export_config = find_default_export_config()
        if default_export_config is None:
            raise FileNotFoundError(
                "no export config found; expected --export-config or ./export_coreml.toml|json"
            )
        export_config = load_export_config(default_export_config)

    if export_config is not None:
        config = load_training_config(export_config.training_config)
        if export_config.image_size is not None:
            config.image_size = export_config.image_size
        if export_config.backbone_name is not None:
            config.backbone_name = export_config.backbone_name
        checkpoint_arg = str(export_config.checkpoint) if export_config.checkpoint is not None else None
        output_arg = str(export_config.output)
    else:
        config = (
            load_training_config(args.config)
            if args.config
            else load_default_training_config(Path(__file__).resolve().parent)
        )
        if not args.output:
            raise ValueError("cli mode requires --output")
        checkpoint_arg = args.checkpoint
        output_arg = args.output

    artifacts = load_model_for_export(config, checkpoint_arg)
    wrapper = ExportWrapper(artifacts.model)
    wrapper.eval()
    sample_ref, sample_neutral, sample_mask = build_sample_inputs(artifacts.model_image_size)
    traced = torch.jit.trace(wrapper, (sample_ref, sample_neutral, sample_mask))

    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[
            ct.TensorType(name=EXPORT_INPUT_NAMES[0], shape=sample_ref.shape, dtype=sample_ref.numpy().dtype),
            ct.TensorType(
                name=EXPORT_INPUT_NAMES[1],
                shape=sample_neutral.shape,
                dtype=sample_neutral.numpy().dtype,
            ),
            ct.TensorType(name=EXPORT_INPUT_NAMES[2], shape=sample_mask.shape, dtype=sample_mask.numpy().dtype),
        ],
        outputs=[
            ct.TensorType(name=EXPORT_OUTPUT_NAMES[0]),
            ct.TensorType(name=EXPORT_OUTPUT_NAMES[1]),
        ],
    )
    output_path = normalize_output_path(output_arg)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(output_path))
    metadata = build_export_metadata(artifacts)
    metadata["format"] = "coreml"
    output_path.with_suffix(".json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
