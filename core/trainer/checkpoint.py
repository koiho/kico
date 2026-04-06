from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
import json

import torch


@dataclass(slots=True)
class ResumeState:
    completed_epochs: int
    best_val: float | None


def history_path(output_dir: Path) -> Path:
    return output_dir / "history.json"


def resume_state_path(output_dir: Path) -> Path:
    return output_dir / "resume_state.json"


def save_checkpoint(
    output_dir: Path,
    name: str,
    model_state: dict,
    optim_state: dict | None = None,
    model_metadata: dict[str, object] | None = None,
) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / f"{name}.pt"
    payload = {"model": model_state}
    if optim_state is not None:
        payload["optimizer"] = optim_state
    if model_metadata is not None:
        payload["model_metadata"] = model_metadata
    torch.save(payload, path)
    return path


def load_checkpoint(path: str | Path, device: str | torch.device = "cpu") -> dict:
    return torch.load(Path(path), map_location=device)


def save_history(output_dir: Path, history: list[dict]) -> None:
    history_path(output_dir).write_text(json.dumps(history, indent=2), encoding="utf-8")


def load_history(output_dir: Path) -> list[dict]:
    path = history_path(output_dir)
    if not path.exists():
        return []
    return json.loads(path.read_text(encoding="utf-8"))


def save_resume_state(output_dir: Path, state: ResumeState) -> None:
    resume_state_path(output_dir).write_text(
        json.dumps(asdict(state), indent=2),
        encoding="utf-8",
    )


def load_resume_state(output_dir: Path) -> ResumeState:
    raw = json.loads(resume_state_path(output_dir).read_text(encoding="utf-8"))
    return ResumeState(
        completed_epochs=int(raw["completed_epochs"]),
        best_val=None if raw.get("best_val") is None else float(raw["best_val"]),
    )
