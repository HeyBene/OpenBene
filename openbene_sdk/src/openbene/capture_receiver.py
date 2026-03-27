#!/usr/bin/env python3
"""
PC-side WebSocket receiver for OpenBene LiDAR Capture.

Receives frames from the iOS app over WebSocket and writes a
Nerfstudio-compatible dataset to disk.

Usage:
    python capture_receiver.py --output ./captured_data/room1 --port 8765
"""

import asyncio
import json
import argparse
import sys
from pathlib import Path
from datetime import datetime

try:
    import websockets
except ImportError:
    print("Missing dependency: pip install websockets")
    sys.exit(1)


class CaptureReceiver:
    """Receives frames over WebSocket and writes Nerfstudio dataset."""

    def __init__(self, output_dir: Path):
        self.base_output_dir = output_dir
        self.output_dir = output_dir
        self.images_dir = output_dir / "images"
        self.depth_dir = output_dir / "depth"
        self.frames = []
        self.global_intrinsics = None
        self.frame_count = 0
        self._pending_metadata = None
        self._expecting = "metadata"  # metadata -> image -> depth(optional) -> manifest(optional pointcloud)
        self.session_info = None
        self._pending_pointcloud = None

    def _configure_output_dirs(self, output_dir: Path):
        self.output_dir = output_dir
        self.images_dir = output_dir / "images"
        self.depth_dir = output_dir / "depth"

    def _ensure_dirs(self):
        self.images_dir.mkdir(parents=True, exist_ok=True)
        self.depth_dir.mkdir(parents=True, exist_ok=True)

    def _reset_session_state(self):
        self.frames = []
        self.global_intrinsics = None
        self.frame_count = 0
        self._pending_metadata = None
        self._pending_pointcloud = None
        self._expecting = "metadata"

    def _session_output_dir(self, session_info: dict) -> Path:
        session_name = session_info.get("session_name") or f"session_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        safe_name = "".join(ch if ch.isalnum() or ch in ("-", "_") else "_" for ch in session_name)
        target = self.base_output_dir / safe_name
        if target.exists() and any(target.iterdir()):
            suffix = datetime.now().strftime('%Y%m%d_%H%M%S')
            target = self.base_output_dir / f"{safe_name}_{suffix}"
        return target

    async def handle_connection(self, websocket):
        remote = websocket.remote_address
        print(f"[+] iOS device connected: {remote[0]}:{remote[1]}")

        await websocket.send(json.dumps({
            "status": "connected",
            "receiver_state": "ready",
            "output_dir": str(self.output_dir),
            "capabilities": ["session_manifest", "pointcloud_v1"],
        }))

        self._ensure_dirs()

        try:
            async for message in websocket:
                await self._process_message(websocket, message)
        except websockets.exceptions.ConnectionClosed:
            print(f"[-] Connection closed: {remote[0]}:{remote[1]}")

        if self.frames and not (self.output_dir / "transforms.json").exists():
            print("[*] Auto-finalizing session...")
            self._write_transforms()

    async def _process_message(self, websocket, message):
        if isinstance(message, str):
            data = json.loads(message)
            msg_type = data.get("type", "")

            if msg_type == "session_start":
                self.session_info = data
                self._reset_session_state()
                self._configure_output_dirs(self._session_output_dir(data))
                self._ensure_dirs()
                self._expecting = "metadata"
                print(
                    f"[*] Session started: name={data.get('session_name')} "
                    f"mode={data.get('session_mode')} id={data.get('session_id')}"
                )
                print(f"[*] Session output: {self.output_dir}")
                await websocket.send(json.dumps({
                    "status": "session_started",
                    "session_id": data.get("session_id"),
                    "session_mode": data.get("session_mode"),
                    "output_dir": str(self.output_dir),
                }))

            elif msg_type == "frame":
                self._pending_metadata = data
                self._expecting = "image"

                if self.global_intrinsics is None:
                    self.global_intrinsics = {
                        "w": data["w"],
                        "h": data["h"],
                        "fl_x": data["fl_x"],
                        "fl_y": data["fl_y"],
                        "cx": data["cx"],
                        "cy": data["cy"],
                    }

            elif msg_type == "session_end":
                self._expecting = "manifest"
                print(
                    f"[*] Session ended: name={data.get('session_name')} "
                    f"mode={data.get('session_mode')} id={data.get('session_id')}"
                )
                await websocket.send(json.dumps({
                    "status": "session_ending",
                    "session_id": data.get("session_id"),
                    "received_frames": self.frame_count,
                }))

            elif msg_type == "pointcloud_start":
                self._pending_pointcloud = data
                self._expecting = "pointcloud"
                print(
                    f"[*] Point cloud incoming: file={data.get('file_name')} points={data.get('point_count')} bytes={data.get('byte_count')}"
                )

        elif isinstance(message, bytes):
            if self._expecting == "image":
                self._save_image(message)
                if self._pending_metadata and self._pending_metadata.get("has_depth"):
                    self._expecting = "depth"
                else:
                    self._finalize_frame()

            elif self._expecting == "depth":
                self._save_depth(message)
                self._finalize_frame()

            elif self._expecting == "manifest":
                manifest_path = self.output_dir / "transforms.json"
                manifest_path.write_bytes(message)
                print(f"[*] Received manifest from device, saved to {manifest_path}")
                print(f"[*] Session finalized with {self.frame_count} frame(s)")
                if self.session_info:
                    print("[*] Session summary")
                    print(f"    name: {self.session_info.get('session_name')}")
                    print(f"    mode: {self.session_info.get('session_mode')}")
                    print(f"    session_id: {self.session_info.get('session_id')}")
                print(f"    output: {self.output_dir}")
                self._expecting = "metadata"

            elif self._expecting == "pointcloud":
                info = self._pending_pointcloud or {}
                file_name = info.get("file_name") or "fused_pointcloud.ply"
                pointcloud_path = self.output_dir / file_name
                pointcloud_path.write_bytes(message)
                point_count = info.get("point_count") or 0
                print(f"[*] Received point cloud, saved to {pointcloud_path}")
                self._pending_pointcloud = None
                self._expecting = "metadata"
                await websocket.send(json.dumps({
                    "status": "pointcloud_received",
                    "point_count": point_count,
                    "file_name": file_name,
                }))

    def _save_image(self, jpeg_data: bytes):
        frame_name = f"{self._pending_metadata['index']:06d}.jpg"
        path = self.images_dir / frame_name
        path.write_bytes(jpeg_data)

    def _save_depth(self, png_data: bytes):
        frame_name = f"{self._pending_metadata['index']:06d}.png"
        path = self.depth_dir / frame_name
        path.write_bytes(png_data)

    def _finalize_frame(self):
        meta = self._pending_metadata
        if meta is None:
            return

        frame_name = f"{meta['index']:06d}"
        frame_entry = {
            "file_path": f"images/{frame_name}.jpg",
            "transform_matrix": meta["transform_matrix"],
            "timestamp": meta.get("timestamp", 0),
        }
        if meta.get("has_depth"):
            frame_entry["depth_file_path"] = f"depth/{frame_name}.png"

        self.frames.append(frame_entry)
        self.frame_count += 1
        print(f"  Frame {self.frame_count} received (index={meta['index']})")

        self._pending_metadata = None
        self._expecting = "metadata"

    def _write_transforms(self):
        manifest = dict(self.global_intrinsics or {})
        manifest["depth_scale"] = 1000.0
        manifest["depth_unit"] = "millimeters"
        manifest["coordinate_convention"] = "opengl"
        manifest["frames"] = self.frames
        if self.session_info:
            manifest["session_id"] = self.session_info.get("session_id")
            manifest["session_name"] = self.session_info.get("session_name")
            manifest["session_mode"] = self.session_info.get("session_mode")

        transforms_path = self.output_dir / "transforms.json"
        transforms_path.write_text(json.dumps(manifest, indent=2))
        print(f"[*] Wrote transforms.json ({len(self.frames)} frames) to {transforms_path}")


async def main(output_dir: Path, host: str, port: int):
    receiver = CaptureReceiver(output_dir)

    print(f"[*] OpenBene Capture Receiver")
    print(f"[*] Listening on ws://{host}:{port}")
    print(f"[*] Output directory: {output_dir}")
    print(f"[*] Waiting for iOS device to connect...")
    print()

    async with websockets.serve(
        receiver.handle_connection,
        host,
        port,
        max_size=8 * 1024 * 1024,
    ):
        await asyncio.Future()  # run forever


def parse_args():
    parser = argparse.ArgumentParser(description="OpenBene LiDAR Capture Receiver")
    parser.add_argument(
        "--output", "-o",
        type=str,
        default=f"./captured_data/session_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
        help="Output directory for the Nerfstudio dataset",
    )
    parser.add_argument("--host", type=str, default="0.0.0.0", help="Listen address")
    parser.add_argument("--port", "-p", type=int, default=8765, help="Listen port")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    output_dir = Path(args.output)
    try:
        asyncio.run(main(output_dir, args.host, args.port))
    except KeyboardInterrupt:
        print("\n[*] Receiver stopped.")
