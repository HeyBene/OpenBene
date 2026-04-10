"""Reusable WebSocket protocol handling for OpenBene LiDAR capture uploads."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import json
from pathlib import Path
import re
from typing import Any, Callable


@dataclass(frozen=True)
class DepthFrameEvent:
    """A single uploaded depth frame ready for downstream processing."""

    session_dir: Path
    session_name: str
    index: int
    timestamp: float
    fl_x: float
    fl_y: float
    cx: float
    cy: float
    width: int
    height: int
    depth_width: int
    depth_height: int
    depth_scale: float
    depth_unit: str
    image_path: Path | None
    depth_path: Path
    depth_png_bytes: bytes
    confidence_path: Path | None
    confidence_png_bytes: bytes | None
    tracking_state: str | None
    depth_source: str | None
    transform_matrix: tuple[tuple[float, float, float, float], ...]


class CaptureProtocolProcessor:
    """State machine for the OpenBene iPhone LiDAR WebSocket upload protocol."""

    def __init__(
        self,
        output_root_dir: str | Path,
        *,
        on_depth_frame: Callable[[DepthFrameEvent], None] | None = None,
    ) -> None:
        self.output_root_dir = Path(output_root_dir).expanduser().resolve()
        self.output_root_dir.mkdir(parents=True, exist_ok=True)
        self.on_depth_frame = on_depth_frame
        self.depth_scale = 1000.0
        self.depth_unit = "millimeters"
        self.coordinate_convention = "opengl"
        self._reset_runtime_state()

    @property
    def current_session_dir(self) -> Path | None:
        return self._session_dir

    @property
    def frame_count(self) -> int:
        return self._frame_count

    @property
    def current_output_dir(self) -> Path:
        if self._session_dir is not None:
            return self._session_dir
        return self.output_root_dir

    def handshake_payload(self) -> dict[str, Any]:
        return {
            "status": "connected",
            "receiver_state": "ready",
            "output_dir": str(self.current_output_dir),
            "capabilities": ["session_manifest", "pointcloud_v1", "live_localization_v1"],
        }

    def handle_text_message(self, message: str) -> list[dict[str, Any]]:
        data = json.loads(message)
        msg_type = str(data.get("type", ""))

        if msg_type == "session_start":
            self._start_session(data)
            return [
                {
                    "status": "session_started",
                    "session_id": data.get("session_id"),
                    "session_mode": data.get("session_mode"),
                    "output_dir": str(self.current_output_dir),
                }
            ]

        if msg_type == "frame":
            self._ensure_active_session(preferred_name=self._session_name_from_payload(data))
            self._finalize_incomplete_frame_if_needed()
            self._pending_metadata = data
            self._pending_image_path = None
            self._pending_depth_path = None
            self._pending_depth_png_bytes = None
            self._pending_confidence_path = None
            self._pending_confidence_png_bytes = None
            self._pending_binary_sequence = self._binary_sequence_from_metadata(data)

            if self._global_intrinsics is None:
                self._global_intrinsics = {
                    "w": int(data["w"]),
                    "h": int(data["h"]),
                    "fl_x": float(data["fl_x"]),
                    "fl_y": float(data["fl_y"]),
                    "cx": float(data["cx"]),
                    "cy": float(data["cy"]),
                }

            if self._pending_binary_sequence:
                self._expecting = self._pending_binary_sequence.pop(0)
            else:
                self._finalize_frame()
            return []

        if msg_type == "session_end":
            self._ensure_active_session(preferred_name=self._session_name_from_payload(data))
            self._finalize_incomplete_frame_if_needed()
            self._expecting = "manifest"
            if self._session_info is not None:
                self._session_info.update(data)
            return [
                {
                    "status": "session_ending",
                    "session_id": data.get("session_id"),
                    "received_frames": self._frame_count,
                }
            ]

        if msg_type == "pointcloud_start":
            self._ensure_active_session()
            self._pending_pointcloud = data
            self._expecting = "pointcloud"
            return []

        return []

    def handle_binary_message(self, message: bytes) -> list[dict[str, Any]]:
        if self._expecting == "image":
            self._pending_image_path = self._save_image(message)
            self._advance_pending_binary_sequence()
            return []

        if self._expecting == "depth":
            self._pending_depth_path = self._save_depth(message)
            self._pending_depth_png_bytes = message
            self._advance_pending_binary_sequence()
            return []

        if self._expecting == "confidence":
            self._pending_confidence_path = self._save_confidence(message)
            self._pending_confidence_png_bytes = message
            self._advance_pending_binary_sequence()
            return []

        if self._expecting == "manifest":
            manifest_path = self._write_manifest_bytes(message)
            self._manifest_received = True
            self._expecting = "metadata"
            return [
                {
                    "status": "session_saved",
                    "session_id": self._session_info.get("session_id") if self._session_info else None,
                    "output_dir": str(manifest_path.parent),
                    "received_frames": self._frame_count,
                }
            ]

        if self._expecting == "pointcloud":
            info = self._pending_pointcloud or {}
            pointcloud_path = self._write_pointcloud_bytes(message, info)
            self._pending_pointcloud = None
            self._expecting = "metadata"
            return [
                {
                    "status": "pointcloud_received",
                    "point_count": int(info.get("point_count", 0)),
                    "file_name": pointcloud_path.name,
                }
            ]

        return []

    def finalize_if_needed(self) -> None:
        if self._session_dir is None:
            return
        self._finalize_incomplete_frame_if_needed()
        if self._frames and not self._manifest_received:
            self._write_transforms()

    def _start_session(self, data: dict[str, Any]) -> None:
        self.finalize_if_needed()
        self._reset_runtime_state()
        self._session_info = dict(data)
        self._ensure_active_session(preferred_name=self._session_name_from_payload(data))

    def _reset_runtime_state(self) -> None:
        self._session_info: dict[str, Any] | None = None
        self._session_dir: Path | None = None
        self._images_dir: Path | None = None
        self._depth_dir: Path | None = None
        self._confidence_dir: Path | None = None
        self._frames: list[dict[str, Any]] = []
        self._global_intrinsics: dict[str, Any] | None = None
        self._frame_count = 0
        self._pending_metadata: dict[str, Any] | None = None
        self._pending_image_path: Path | None = None
        self._pending_depth_path: Path | None = None
        self._pending_depth_png_bytes: bytes | None = None
        self._pending_confidence_path: Path | None = None
        self._pending_confidence_png_bytes: bytes | None = None
        self._pending_binary_sequence: list[str] = []
        self._expecting = "metadata"
        self._pending_pointcloud: dict[str, Any] | None = None
        self._manifest_received = False
        self._session_name = ""

    def _ensure_active_session(self, preferred_name: str | None = None) -> None:
        if self._session_dir is not None:
            return

        session_name = preferred_name or f"session_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        session_dir = self._make_unique_session_dir(session_name)
        session_dir.mkdir(parents=True, exist_ok=True)
        self._session_dir = session_dir
        self._images_dir = session_dir / "images"
        self._depth_dir = session_dir / "depth"
        self._images_dir.mkdir(parents=True, exist_ok=True)
        self._depth_dir.mkdir(parents=True, exist_ok=True)
        self._session_name = session_dir.name

    def _ensure_confidence_dir(self) -> Path:
        if self._confidence_dir is None:
            if self._session_dir is None:
                raise ValueError("Cannot create confidence directory without an active session.")
            self._confidence_dir = self._session_dir / "confidence"
            self._confidence_dir.mkdir(parents=True, exist_ok=True)
        return self._confidence_dir

    def _make_unique_session_dir(self, session_name: str) -> Path:
        safe_name = self._sanitize_session_name(session_name)
        candidate = self.output_root_dir / safe_name
        suffix = 1
        while candidate.exists():
            candidate = self.output_root_dir / f"{safe_name}_{suffix:02d}"
            suffix += 1
        return candidate

    def _sanitize_session_name(self, session_name: str) -> str:
        normalized = re.sub(r"[^A-Za-z0-9._-]+", "_", session_name.strip())
        return normalized.strip("._") or f"session_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

    def _session_name_from_payload(self, data: dict[str, Any]) -> str | None:
        value = data.get("session_name")
        if value is None:
            return None
        return str(value)

    def _binary_sequence_from_metadata(self, metadata: dict[str, Any]) -> list[str]:
        sequence: list[str] = []
        if bool(metadata.get("has_image", True)):
            sequence.append("image")
        if bool(metadata.get("has_depth", False)):
            sequence.append("depth")
        if bool(metadata.get("has_confidence", False)):
            sequence.append("confidence")
        return sequence

    def _advance_pending_binary_sequence(self) -> None:
        if self._pending_binary_sequence:
            self._expecting = self._pending_binary_sequence.pop(0)
            return
        self._finalize_frame()

    def _finalize_incomplete_frame_if_needed(self) -> None:
        if self._pending_metadata is not None:
            self._finalize_frame()

    def _save_image(self, jpeg_data: bytes) -> Path:
        if self._pending_metadata is None:
            raise ValueError("Received image bytes without pending frame metadata.")
        assert self._images_dir is not None
        frame_name = f"{int(self._pending_metadata['index']):06d}.jpg"
        path = self._images_dir / frame_name
        path.write_bytes(jpeg_data)
        return path

    def _save_depth(self, png_data: bytes) -> Path:
        if self._pending_metadata is None:
            raise ValueError("Received depth bytes without pending frame metadata.")
        assert self._depth_dir is not None
        frame_name = f"{int(self._pending_metadata['index']):06d}.png"
        path = self._depth_dir / frame_name
        path.write_bytes(png_data)
        return path

    def _save_confidence(self, png_data: bytes) -> Path:
        if self._pending_metadata is None:
            raise ValueError("Received confidence bytes without pending frame metadata.")
        confidence_dir = self._ensure_confidence_dir()
        frame_name = f"{int(self._pending_metadata['index']):06d}.png"
        path = confidence_dir / frame_name
        path.write_bytes(png_data)
        return path

    def _emit_depth_frame_event(self) -> None:
        if self.on_depth_frame is None or self._pending_metadata is None:
            return
        if self._pending_depth_path is None or self._pending_depth_png_bytes is None:
            return
        assert self._session_dir is not None

        event = DepthFrameEvent(
            session_dir=self._session_dir,
            session_name=self._session_name,
            index=int(self._pending_metadata["index"]),
            timestamp=float(self._pending_metadata.get("timestamp", 0.0)),
            fl_x=float(self._pending_metadata["fl_x"]),
            fl_y=float(self._pending_metadata["fl_y"]),
            cx=float(self._pending_metadata["cx"]),
            cy=float(self._pending_metadata["cy"]),
            width=int(self._pending_metadata["w"]),
            height=int(self._pending_metadata["h"]),
            depth_width=int(self._pending_metadata.get("depth_width", 0)),
            depth_height=int(self._pending_metadata.get("depth_height", 0)),
            depth_scale=self.depth_scale,
            depth_unit=self.depth_unit,
            image_path=self._pending_image_path,
            depth_path=self._pending_depth_path,
            depth_png_bytes=self._pending_depth_png_bytes,
            confidence_path=self._pending_confidence_path,
            confidence_png_bytes=self._pending_confidence_png_bytes,
            tracking_state=(
                str(self._pending_metadata["tracking_state"])
                if self._pending_metadata.get("tracking_state") is not None
                else None
            ),
            depth_source=(
                str(self._pending_metadata["depth_source"])
                if self._pending_metadata.get("depth_source") is not None
                else None
            ),
            transform_matrix=tuple(
                tuple(float(value) for value in row)
                for row in self._pending_metadata["transform_matrix"]
            ),
        )
        self.on_depth_frame(event)

    def _finalize_frame(self) -> None:
        if self._pending_metadata is None:
            return

        self._emit_depth_frame_event()

        index = int(self._pending_metadata["index"])
        frame_name = f"{index:06d}"
        frame_entry: dict[str, Any] = {
            "transform_matrix": self._pending_metadata["transform_matrix"],
            "timestamp": float(self._pending_metadata.get("timestamp", 0.0)),
        }
        if self._pending_image_path is not None:
            frame_entry["file_path"] = f"images/{frame_name}.jpg"
        if self._pending_depth_path is not None:
            frame_entry["depth_file_path"] = f"depth/{frame_name}.png"
        if self._pending_confidence_path is not None:
            frame_entry["confidence_file_path"] = f"confidence/{frame_name}.png"
        if self._pending_metadata.get("tracking_state") is not None:
            frame_entry["tracking_state"] = str(self._pending_metadata["tracking_state"])
        if self._pending_metadata.get("depth_source") is not None:
            frame_entry["depth_source"] = str(self._pending_metadata["depth_source"])

        self._frames.append(frame_entry)
        self._frame_count += 1
        self._pending_metadata = None
        self._pending_image_path = None
        self._pending_depth_path = None
        self._pending_depth_png_bytes = None
        self._pending_confidence_path = None
        self._pending_confidence_png_bytes = None
        self._pending_binary_sequence = []
        self._expecting = "metadata"

    def _write_manifest_bytes(self, message: bytes) -> Path:
        if self._session_dir is None:
            raise ValueError("Received manifest bytes before a session directory was created.")
        manifest_path = self._session_dir / "transforms.json"
        manifest_path.write_bytes(message)
        return manifest_path

    def _write_pointcloud_bytes(self, message: bytes, info: dict[str, Any]) -> Path:
        if self._session_dir is None:
            raise ValueError("Received point cloud bytes before a session directory was created.")
        file_name = str(info.get("file_name") or "fused_pointcloud.ply")
        path = self._session_dir / file_name
        path.write_bytes(message)
        return path

    def _write_transforms(self) -> Path:
        if self._session_dir is None:
            raise ValueError("Cannot write transforms.json without an active session.")

        manifest = dict(self._global_intrinsics or {})
        manifest["depth_scale"] = self.depth_scale
        manifest["depth_unit"] = self.depth_unit
        manifest["coordinate_convention"] = self.coordinate_convention
        manifest["frames"] = self._frames
        if self._session_info:
            manifest["session_id"] = self._session_info.get("session_id")
            manifest["session_name"] = self._session_info.get("session_name")
            manifest["session_mode"] = self._session_info.get("session_mode")

        transforms_path = self._session_dir / "transforms.json"
        transforms_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
        return transforms_path
