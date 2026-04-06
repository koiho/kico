from __future__ import annotations

import argparse
from dataclasses import dataclass
import importlib.util
import json
from pathlib import Path
import tomllib

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


DEFAULT_OPSET_VERSION = 17


@dataclass(slots=True)
class ONNXExportConfig:
    training_config: Path
    output: Path
    checkpoint: Path | None = None
    image_size: int | None = None
    backbone_name: str | None = None
    opset_version: int = DEFAULT_OPSET_VERSION
    dynamic_batch: bool = True

    def resolve(self, base_dir: Path) -> "ONNXExportConfig":
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
    parser.add_argument("--opset-version", type=int)
    parser.add_argument(
        "--no-dynamic-batch",
        action="store_true",
        help="export a fixed batch=1 ONNX graph",
    )
    return parser.parse_args()


def load_export_config(path: str | Path) -> ONNXExportConfig:
    path = Path(path)
    raw_text = path.read_text(encoding="utf-8")
    if path.suffix == ".toml":
        raw = tomllib.loads(raw_text)
    elif path.suffix == ".json":
        raw = json.loads(raw_text)
    else:
        raise ValueError(f"unsupported export config extension: {path.suffix}")

    valid_keys = set(ONNXExportConfig.__dataclass_fields__.keys())
    unknown_keys = sorted(set(raw.keys()) - valid_keys)
    if unknown_keys:
        raise ValueError(f"unknown export config keys: {', '.join(unknown_keys)}")

    config = ONNXExportConfig(
        training_config=Path(raw.get("training_config", "training.toml")),
        output=Path(raw["output"]),
        checkpoint=Path(raw["checkpoint"]) if raw.get("checkpoint") else None,
        image_size=raw.get("image_size"),
        backbone_name=raw.get("backbone_name"),
        opset_version=raw.get("opset_version", DEFAULT_OPSET_VERSION),
        dynamic_batch=raw.get("dynamic_batch", True),
    )
    return config.resolve(path.parent.resolve())


def find_default_export_config() -> Path | None:
    search_dirs = [Path(__file__).resolve().parent, Path.cwd()]
    for search_dir in search_dirs:
        for relative_path in (
            "export_onnx.toml",
            "export_onnx.json",
            "config/export_onnx.toml",
            "config/export_onnx.json",
        ):
            path = search_dir / relative_path
            if path.exists():
                return path
    return None


def normalize_output_path(raw_path: str | Path) -> Path:
    path = Path(raw_path)
    if path.suffix != ".onnx":
        return path.with_suffix(".onnx")
    return path


def require_onnx_dependency() -> None:
    if importlib.util.find_spec("onnx") is None:
        raise ModuleNotFoundError(
            "onnx export requires the `onnx` package. Install it first with `python -m pip install onnx`."
        )


def build_dynamic_axes(dynamic_batch: bool) -> dict[str, dict[int, str]] | None:
    if not dynamic_batch:
        return None
    dynamic_axes: dict[str, dict[int, str]] = {}
    for name in (*EXPORT_INPUT_NAMES, *EXPORT_OUTPUT_NAMES):
        dynamic_axes[name] = {0: "batch"}
    return dynamic_axes


def main() -> None:
    args = parse_args()
    export_config = None
    if args.export_config:
        export_config = load_export_config(args.export_config)
    elif not any((args.config, args.checkpoint, args.output, args.opset_version, args.no_dynamic_batch)):
        default_export_config = find_default_export_config()
        if default_export_config is None:
            raise FileNotFoundError(
                "no export config found; expected --export-config or ./export_onnx.toml|json"
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
        opset_version = export_config.opset_version
        dynamic_batch = export_config.dynamic_batch
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
        opset_version = args.opset_version or DEFAULT_OPSET_VERSION
        dynamic_batch = not args.no_dynamic_batch

    require_onnx_dependency()

    artifacts = load_model_for_export(config, checkpoint_arg)
    wrapper = ExportWrapper(artifacts.model)
    wrapper.eval()
    sample_inputs = build_sample_inputs(artifacts.model_image_size)
    output_path = normalize_output_path(output_arg)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    torch.onnx.export(
        wrapper,
        sample_inputs,
        str(output_path),
        input_names=list(EXPORT_INPUT_NAMES),
        output_names=list(EXPORT_OUTPUT_NAMES),
        opset_version=opset_version,
        export_params=True,
        do_constant_folding=True,
        dynamic_axes=build_dynamic_axes(dynamic_batch),
        training=torch.onnx.TrainingMode.EVAL,
        dynamo=False,
    )

    metadata = build_export_metadata(artifacts)
    metadata["format"] = "onnx"
    metadata["opset_version"] = opset_version
    metadata["dynamic_batch"] = dynamic_batch
    output_path.with_suffix(".json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
