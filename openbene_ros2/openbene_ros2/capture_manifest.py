"""Helpers for loading OpenBene LiDAR capture datasets."""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class CaptureFrame:
    """A single frame entry inside an OpenBene capture manifest."""

    index: int
    image_path: Path | None
    depth_path: Path | None
    confidence_path: Path | None
    timestamp: float
    tracking_state: str | None
    depth_source: str | None
    transform_matrix: tuple[tuple[float, float, float, float], ...]


@dataclass(frozen=True)
class CaptureManifest:
    """The parsed `transforms.json` file plus resolved frame paths."""

    dataset_dir: Path
    width: int
    height: int
    fl_x: float
    fl_y: float
    cx: float
    cy: float
    depth_scale: float
    depth_unit: str
    coordinate_convention: str
    frames: tuple[CaptureFrame, ...]

    @property
    def depth_frames(self) -> tuple[CaptureFrame, ...]:
        """Return only frames that reference a depth image."""
        return tuple(frame for frame in self.frames if frame.depth_path is not None)


def _normalize_transform_matrix(raw_matrix: Any) -> tuple[tuple[float, float, float, float], ...]:
    if not isinstance(raw_matrix, list) or len(raw_matrix) != 4:
        raise ValueError("Each frame must provide a 4x4 transform_matrix.")

    normalized_rows = []
    for row in raw_matrix:
        if not isinstance(row, list) or len(row) != 4:
            raise ValueError("Each frame transform_matrix row must contain 4 numeric values.")
        normalized_rows.append(tuple(float(value) for value in row))

    return tuple(normalized_rows)


def _frame_index_from_payload(frame_data: dict[str, Any], default_index: int) -> int:
    if "index" in frame_data:
        return int(frame_data["index"])

    file_path = str(frame_data.get("file_path", ""))
    stem = Path(file_path).stem
    if stem.isdigit():
        return int(stem)

    return default_index


def load_capture_manifest(dataset_dir: str | Path) -> CaptureManifest:
    """Load an OpenBene LiDAR capture dataset written as `transforms.json`."""
    dataset_path = Path(dataset_dir).expanduser().resolve()
    transforms_path = dataset_path / "transforms.json"

    if not transforms_path.exists():
        raise FileNotFoundError(f"Could not find capture manifest: {transforms_path}")

    payload = json.loads(transforms_path.read_text(encoding="utf-8"))
    frames_payload = payload.get("frames")
    if not isinstance(frames_payload, list) or not frames_payload:
        raise ValueError("Capture manifest does not contain any frames.")

    frames: list[CaptureFrame] = []
    for default_index, frame_data in enumerate(frames_payload):
        if not isinstance(frame_data, dict):
            raise ValueError("Each frame entry in the capture manifest must be a JSON object.")

        image_rel_path = frame_data.get("file_path")
        depth_rel_path = frame_data.get("depth_file_path")
        confidence_rel_path = frame_data.get("confidence_file_path")
        frames.append(
            CaptureFrame(
                index=_frame_index_from_payload(frame_data, default_index),
                image_path=(dataset_path / str(image_rel_path)).resolve() if image_rel_path else None,
                depth_path=(dataset_path / str(depth_rel_path)).resolve() if depth_rel_path else None,
                confidence_path=(dataset_path / str(confidence_rel_path)).resolve() if confidence_rel_path else None,
                timestamp=float(frame_data.get("timestamp", 0.0)),
                tracking_state=(
                    str(frame_data["tracking_state"])
                    if frame_data.get("tracking_state") is not None
                    else None
                ),
                depth_source=(
                    str(frame_data["depth_source"])
                    if frame_data.get("depth_source") is not None
                    else None
                ),
                transform_matrix=_normalize_transform_matrix(frame_data.get("transform_matrix")),
            )
        )

    return CaptureManifest(
        dataset_dir=dataset_path,
        width=int(payload["w"]),
        height=int(payload["h"]),
        fl_x=float(payload["fl_x"]),
        fl_y=float(payload["fl_y"]),
        cx=float(payload["cx"]),
        cy=float(payload["cy"]),
        depth_scale=float(payload.get("depth_scale", 1000.0)),
        depth_unit=str(payload.get("depth_unit", "millimeters")),
        coordinate_convention=str(payload.get("coordinate_convention", "opengl")),
        frames=tuple(frames),
    )
