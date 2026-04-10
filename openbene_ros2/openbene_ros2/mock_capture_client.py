"""Synthetic OpenBene LiDAR upload client for no-phone testing."""

from __future__ import annotations

import asyncio
import json
from typing import Any


def _build_manifest_payload() -> dict[str, Any]:
    return {
        "w": 640,
        "h": 480,
        "fl_x": 320.0,
        "fl_y": 320.0,
        "cx": 320.0,
        "cy": 240.0,
        "depth_scale": 1000.0,
        "depth_unit": "millimeters",
        "coordinate_convention": "opengl",
        "frames": [
            {
                "file_path": "images/000000.jpg",
                "depth_file_path": "depth/000000.png",
                "confidence_file_path": "confidence/000000.png",
                "tracking_state": "normal",
                "depth_source": "smoothed_scene_depth",
                "timestamp": 0.0,
                "transform_matrix": [
                    [1.0, 0.0, 0.0, 0.0],
                    [0.0, 1.0, 0.0, 0.0],
                    [0.0, 0.0, 1.0, 0.0],
                    [0.0, 0.0, 0.0, 1.0],
                ],
            }
        ],
    }


def _build_frame_metadata() -> dict[str, Any]:
    return {
        "type": "frame",
        "index": 0,
        "timestamp": 0.0,
        "fl_x": 320.0,
        "fl_y": 320.0,
        "cx": 320.0,
        "cy": 240.0,
        "w": 640,
        "h": 480,
        "transfer_mode": "live",
        "has_image": False,
        "has_depth": True,
        "has_confidence": True,
        "depth_width": 256,
        "depth_height": 192,
        "confidence_width": 256,
        "confidence_height": 192,
        "tracking_state": "normal",
        "depth_source": "smoothed_scene_depth",
        "transform_matrix": [
            [1.0, 0.0, 0.0, 0.0],
            [0.0, 1.0, 0.0, 0.0],
            [0.0, 0.0, 1.0, 0.0],
            [0.0, 0.0, 0.0, 1.0],
        ],
    }


def _make_mock_media_bytes() -> tuple[bytes, bytes, bytes]:
    try:
        import cv2
        import numpy as np
    except Exception as exc:
        raise RuntimeError(
            "Missing runtime dependency for mock_capture_client. "
            "Install the local SDK first with 'python3 -m pip install -e /path/to/OpenBene/openbene_sdk'."
        ) from exc

    rgb = np.zeros((480, 640, 3), dtype=np.uint8)
    rgb[:, :, 1] = 180
    rgb[:, :, 2] = 80
    rgb[180:300, 240:400, :] = (50, 50, 230)

    depth = np.full((192, 256), 2000, dtype=np.uint16)
    depth[:, 108:148] = 1200

    confidence = np.full((192, 256), 2, dtype=np.uint8)
    confidence[:, :32] = 0

    ok_jpg, jpg = cv2.imencode(".jpg", rgb)
    ok_png, png = cv2.imencode(".png", depth)
    ok_conf, conf_png = cv2.imencode(".png", confidence)
    if not ok_jpg or not ok_png or not ok_conf:
        raise RuntimeError("Failed to encode synthetic RGB/depth/confidence images.")
    return bytes(jpg), bytes(png), bytes(conf_png)


async def _main() -> int:
    try:
        import websockets
    except Exception as exc:
        raise RuntimeError(
            "Missing runtime dependency for mock_capture_client. "
            "Install the local SDK first with 'python3 -m pip install -e /path/to/OpenBene/openbene_sdk'."
        ) from exc

    jpg_bytes, depth_png_bytes, confidence_png_bytes = _make_mock_media_bytes()
    manifest_payload = _build_manifest_payload()

    uri = "ws://127.0.0.1:8765"
    async with websockets.connect(uri) as websocket:
        try:
            await asyncio.wait_for(websocket.recv(), timeout=2.0)
        except asyncio.TimeoutError:
            pass

        await websocket.send(
            json.dumps(
                {
                    "type": "session_start",
                    "session_id": "mock-session-001",
                    "session_name": "mock_session",
                    "session_mode": "Auto",
                    "depth_enabled": True,
                    "started_at": 0.0,
                }
            )
        )
        await websocket.send(json.dumps(_build_frame_metadata()))
        await websocket.send(depth_png_bytes)
        await websocket.send(confidence_png_bytes)
        await websocket.send(
            json.dumps(
                {
                    "type": "session_end",
                    "session_id": "mock-session-001",
                    "session_name": "mock_session",
                    "session_mode": "Auto",
                    "manifest_size": len(json.dumps(manifest_payload).encode("utf-8")),
                }
            )
        )
        await websocket.send(json.dumps(manifest_payload).encode("utf-8"))
        await asyncio.sleep(0.2)

    return 0


def main() -> int:
    return asyncio.run(_main())


if __name__ == "__main__":
    raise SystemExit(main())
