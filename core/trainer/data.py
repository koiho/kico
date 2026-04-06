from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import csv
import json

import numpy as np
from PIL import Image
import torch
from torch.utils.data import Dataset

try:
    from .contract import GATE_NAMES, MASK_DIM, MASK_NAMES, PARAMETER_NAMES
except ImportError:  # pragma: no cover
    from contract import GATE_NAMES, MASK_DIM, MASK_NAMES, PARAMETER_NAMES


PROJECT_ROOT = Path(__file__).resolve().parents[2]
PAYLOAD_METADATA_FILENAME = "neutral_linear.rgba16f.json"

REQUIRED_MANIFEST_COLUMNS = (
    "reference_image_path",
    "neutral_preview_path",
    "mask_bundle_path",
    "label_json_path",
)


@dataclass(slots=True)
class ManifestEntry:
    base_dir: Path
    sample_id: str | None
    reference_image_path: str
    neutral_preview_path: str
    neutral_image_path: str | None
    mask_bundle_path: str
    label_json_path: str
    source_type: str
    fit_confidence: float


def parse_source_type(raw: str | None) -> str:
    value = (raw or "").strip().lower()
    if value in {"", "synthetic"}:
        return "synthetic"
    if value == "fitted_real_ref":
        return "fitted_real_ref"
    raise ValueError(
        f"invalid source_type `{raw}`: expected `synthetic` or `fitted_real_ref`"
    )


def resolve_fit_confidence(source_type: str, raw: str | None) -> float:
    if raw is None or raw == "":
        if source_type == "synthetic":
            return 1.0
        raise ValueError("fitted_real_ref samples must set fit_confidence in [0, 1]")
    value = float(raw)
    if not np.isfinite(value) or not 0.0 <= value <= 1.0:
        raise ValueError(f"invalid fit_confidence: expected finite value in [0, 1], got {value}")
    return value


def _resolve(base: Path, raw: str) -> Path:
    path = Path(raw)
    return path if path.is_absolute() else (base / path)


def require_manifest_columns(fieldnames: list[str] | None) -> None:
    columns = [] if fieldnames is None else list(fieldnames)
    missing = [name for name in REQUIRED_MANIFEST_COLUMNS if name not in columns]
    if missing:
        raise ValueError(f"manifest missing required columns: {', '.join(missing)}")


def require_non_empty_path(row: dict[str, str], key: str, row_number: int) -> str:
    value = (row.get(key) or "").strip()
    if value:
        return value
    raise ValueError(f"manifest row {row_number} missing required field `{key}`")


def require_existing_path(base_dir: Path, raw_path: str, key: str, row_number: int) -> str:
    path = _resolve(base_dir, raw_path)
    if path.exists():
        return raw_path
    raise FileNotFoundError(
        f"manifest row {row_number} points `{key}` to missing file: {path}"
    )


def resolve_optional_existing_path(
    base_dir: Path,
    row: dict[str, str],
    key: str,
    row_number: int,
) -> str | None:
    raw_path = (row.get(key) or "").strip()
    if not raw_path:
        return None
    return require_existing_path(base_dir, raw_path, key, row_number)


def infer_neutral_image_path(base_dir: Path, sample_id: str | None, label_json_path: str) -> str | None:
    if sample_id is None:
        return None
    metadata_path = base_dir / "metadata" / f"{sample_id}.json"
    if not metadata_path.exists():
        label_path = _resolve(base_dir, label_json_path)
        metadata_candidate = label_path.parent.parent / "metadata" / label_path.name
        if not metadata_candidate.exists():
            return None
        metadata_path = metadata_candidate
    with metadata_path.open("r", encoding="utf-8") as handle:
        metadata = json.load(handle)
    capture_path = (metadata.get("capture_path") or "").strip()
    if not capture_path:
        return None
    capture_candidates = [
        _resolve(base_dir, capture_path),
        PROJECT_ROOT / capture_path,
    ]
    for capture_dir in capture_candidates:
        neutral_image_path = capture_dir / "neutral_linear.rgba16f.bin"
        if neutral_image_path.exists():
            return str(neutral_image_path)
    return None


def build_manifest_entry(base_dir: Path, row: dict[str, str], row_number: int) -> ManifestEntry:
    sample_id = (row.get("sample_id") or "").strip() or None
    source_type = parse_source_type(row.get("source_type"))
    fit_confidence = resolve_fit_confidence(source_type, row.get("fit_confidence"))
    reference_image_path = require_existing_path(
        base_dir,
        require_non_empty_path(row, "reference_image_path", row_number),
        "reference_image_path",
        row_number,
    )
    neutral_preview_path = require_existing_path(
        base_dir,
        require_non_empty_path(row, "neutral_preview_path", row_number),
        "neutral_preview_path",
        row_number,
    )
    mask_bundle_path = require_existing_path(
        base_dir,
        require_non_empty_path(row, "mask_bundle_path", row_number),
        "mask_bundle_path",
        row_number,
    )
    label_json_path = require_existing_path(
        base_dir,
        require_non_empty_path(row, "label_json_path", row_number),
        "label_json_path",
        row_number,
    )
    neutral_image_path = resolve_optional_existing_path(base_dir, row, "neutral_image_path", row_number)
    if neutral_image_path is None:
        neutral_image_path = infer_neutral_image_path(base_dir, sample_id, label_json_path)
    if source_type == "fitted_real_ref" and reference_image_path == neutral_preview_path:
        raise ValueError(
            "fitted_real_ref samples must use a real reference image path different from neutral_preview_path"
        )
    return ManifestEntry(
        base_dir=base_dir,
        sample_id=sample_id,
        reference_image_path=reference_image_path,
        neutral_preview_path=neutral_preview_path,
        neutral_image_path=neutral_image_path,
        mask_bundle_path=mask_bundle_path,
        label_json_path=label_json_path,
        source_type=source_type,
        fit_confidence=fit_confidence,
    )


def load_manifest_entries(path: str | Path) -> list[ManifestEntry]:
    path = Path(path)
    base_dir = path.parent
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        require_manifest_columns(reader.fieldnames)
        out = []
        for row_number, row in enumerate(reader, start=2):
            out.append(build_manifest_entry(base_dir, row, row_number))
    return out


def load_rgb_image(path: Path, image_size: int) -> np.ndarray:
    with Image.open(path) as handle:
        image = handle.convert("RGB").resize((image_size, image_size), Image.Resampling.BICUBIC)
        array = np.asarray(image, dtype=np.float32) / 255.0
    return np.transpose(array, (2, 0, 1))


def load_image_size(path: Path) -> tuple[int, int]:
    with Image.open(path) as handle:
        return handle.size


def load_payload_source_size(path: Path) -> tuple[int, int] | None:
    metadata_path = path.with_name(PAYLOAD_METADATA_FILENAME)
    if not metadata_path.exists():
        return None
    with metadata_path.open("r", encoding="utf-8") as handle:
        metadata = json.load(handle)
    width = int(metadata["width"])
    height = int(metadata["height"])
    if width <= 0 or height <= 0:
        raise ValueError(f"invalid payload metadata in {metadata_path}: width/height must be positive")
    return width, height


def load_rgba16f_image(path: Path, source_size: tuple[int, int], image_size: int) -> np.ndarray:
    width, height = source_size
    expected_bytes = width * height * 8
    data = path.read_bytes()
    if len(data) != expected_bytes:
        raise ValueError(
            f"invalid rgba16f payload size for {path}: expected {expected_bytes} bytes, got {len(data)}"
        )
    rgba = np.frombuffer(data, dtype=np.dtype("<f2")).reshape(height, width, 4).astype(np.float32)
    rgb = np.transpose(rgba[:, :, :3], (2, 0, 1))
    tensor = torch.from_numpy(rgb).unsqueeze(0)
    resized = torch.nn.functional.interpolate(
        tensor,
        size=(image_size, image_size),
        mode="bilinear",
        align_corners=False,
    )
    return resized.squeeze(0).contiguous().numpy()


def resolve_raw_source_size(raw_path: Path, fallback_preview_path: Path) -> tuple[int, int]:
    metadata_size = load_payload_source_size(raw_path)
    if metadata_size is not None:
        return metadata_size
    raw_preview_path = raw_path.with_name("neutral_preview.png")
    if raw_preview_path.exists():
        preview_size = load_image_size(raw_preview_path)
    else:
        preview_size = load_image_size(fallback_preview_path)
    width, height = preview_size
    if raw_path.stat().st_size == width * height * 8:
        return preview_size
    raise ValueError(
        f"cannot infer rgba16f payload size for {raw_path}: missing {raw_path.with_name(PAYLOAD_METADATA_FILENAME)} "
        f"and preview-based fallback {width}x{height} does not match file length {raw_path.stat().st_size} bytes"
    )


def load_mask_bundle(base_dir: Path, raw_path: str, image_size: int) -> np.ndarray:
    if not raw_path.strip():
        return np.zeros((MASK_DIM, image_size, image_size), dtype=np.float32)
    path = _resolve(base_dir, raw_path)
    with np.load(path) as bundle:
        masks = []
        for name in MASK_NAMES:
            key = f"{name}.npy"
            mask = bundle[key].astype(np.float32)
            mask_img = Image.fromarray(np.clip(mask, 0.0, 1.0) * 255.0).convert("L")
            mask_img = mask_img.resize((image_size, image_size), Image.Resampling.BILINEAR)
            masks.append(np.asarray(mask_img, dtype=np.float32) / 255.0)
    return np.stack(masks, axis=0)


def load_labels(path: Path) -> tuple[np.ndarray, np.ndarray]:
    with path.open("r", encoding="utf-8") as handle:
        labels = json.load(handle)
    params = np.asarray(
        [validate_normalized_label_value(name, labels["renderer_params"][name]) for name in PARAMETER_NAMES],
        dtype=np.float32,
    )
    gates = np.asarray(
        [validate_normalized_label_value(name, labels["module_gates"][name]) for name in GATE_NAMES],
        dtype=np.float32,
    )
    return params, gates


def validate_normalized_label_value(name: str, value: float) -> float:
    value = float(value)
    if not np.isfinite(value) or not 0.0 <= value <= 1.0:
        raise ValueError(
            f"invalid normalized label value for {name}: expected finite value in [0, 1], got {value}"
        )
    return value


class StyleDataset(Dataset):
    def __init__(self, entries: list[ManifestEntry], image_size: int) -> None:
        self.entries = entries
        self.image_size = image_size

    def __len__(self) -> int:
        return len(self.entries)

    def __getitem__(self, index: int) -> dict[str, torch.Tensor]:
        entry = self.entries[index]
        ref_path = _resolve(entry.base_dir, entry.reference_image_path)
        neutral_path = _resolve(entry.base_dir, entry.neutral_preview_path)
        neutral_image_path = None if entry.neutral_image_path is None else _resolve(entry.base_dir, entry.neutral_image_path)
        label_path = _resolve(entry.base_dir, entry.label_json_path)
        target_params, target_gates = load_labels(label_path)
        source_type = entry.source_type
        neutral_preview = torch.from_numpy(load_rgb_image(neutral_path, self.image_size))
        render_supervision_mask = 1.0
        if neutral_image_path is None:
            neutral_image = neutral_preview.clone()
            render_supervision_mask = 0.0
        else:
            neutral_image = torch.from_numpy(
                load_rgba16f_image(
                    neutral_image_path,
                    resolve_raw_source_size(neutral_image_path, neutral_path),
                    self.image_size,
                )
            )
        return {
            "ref_image": torch.from_numpy(load_rgb_image(ref_path, self.image_size)),
            "neutral_preview": neutral_preview,
            "neutral_image": neutral_image,
            "mask_tensor": torch.from_numpy(load_mask_bundle(entry.base_dir, entry.mask_bundle_path, self.image_size)),
            "target_params": torch.from_numpy(target_params),
            "target_gates": torch.from_numpy(target_gates),
            "synthetic_mask": torch.tensor([1.0 if source_type == "synthetic" else 0.0], dtype=torch.float32),
            "fitted_mask": torch.tensor([0.0 if source_type == "synthetic" else 1.0], dtype=torch.float32),
            "fit_confidence": torch.tensor([entry.fit_confidence], dtype=torch.float32),
            "render_supervision_mask": torch.tensor([render_supervision_mask], dtype=torch.float32),
        }
