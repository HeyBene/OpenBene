#!/usr/bin/env python3
"""
OpenBene live ROS2 bridge.

Current implementation focus:
- watch receiver output directories
- detect new sessions and newly written frames
- support dry-run simulation on macOS

Future ROS2 mode will reuse the same detection flow and replace dry-run logs
with actual ROS2 message publication.
"""

from __future__ import annotations

import argparse
import json
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Set

import sys

CURRENT_DIR = Path(__file__).resolve().parent
if str(CURRENT_DIR) not in sys.path:
    sys.path.insert(0, str(CURRENT_DIR))

from ros2_bridge_common import (
    CAMERA_DEPTH_TOPIC,
    CAMERA_INFO_TOPIC,
    CAMERA_POSE_TOPIC,
    CAMERA_RGB_TOPIC,
    SESSION_STATE_TOPIC,
    SessionFrame,
    make_camera_info_msg,
    make_depth_msg,
    make_pose_msg,
    make_rgb_msg,
)


@dataclass
class SessionFrameRecord:
    index: int
    image_path: Path
    depth_path: Optional[Path]
    timestamp: float
    transform_matrix: List[List[float]]


@dataclass
class SessionTracker:
    session_dir: Path
    published_indices: Set[int] = field(default_factory=set)
    manifest_loaded: bool = False
    session_name: str = ""
    session_mode: str = "mapping"
    session_closed: bool = False


@dataclass
class LiveBridgeConfig:
    watch_dir: Path
    frame_id: str
    world_frame: str
    dry_run: bool
    poll_interval: float
    once: bool


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="OpenBene live ROS2 bridge")
    parser.add_argument("--watch-dir", type=Path, required=True, help="Receiver output root directory to watch")
    parser.add_argument("--frame-id", type=str, default="openbene_camera", help="ROS camera frame_id")
    parser.add_argument("--world-frame", type=str, default="openbene_world", help="ROS world frame_id")
    parser.add_argument("--dry-run", action="store_true", help="Simulate live publishing without ROS2")
    parser.add_argument("--poll-interval", type=float, default=1.0, help="Polling interval in seconds")
    parser.add_argument("--once", action="store_true", help="Run one scan pass and exit")
    return parser.parse_args()


def load_manifest(session_dir: Path) -> Optional[dict]:
    manifest_path = session_dir / "transforms.json"
    if not manifest_path.exists():
        return None
    try:
        return json.loads(manifest_path.read_text())
    except json.JSONDecodeError:
        return None


def discover_session_dirs(watch_dir: Path) -> List[Path]:
    if not watch_dir.exists():
        return []
    if (watch_dir / "transforms.json").exists():
        return [watch_dir]
    return sorted([path for path in watch_dir.iterdir() if path.is_dir()])


def extract_ready_frames(session_dir: Path, manifest: dict) -> List[SessionFrameRecord]:
    frames = []
    for index, frame in enumerate(manifest.get("frames", [])):
        image_path = session_dir / frame["file_path"]
        depth_path = session_dir / frame["depth_file_path"] if frame.get("depth_file_path") else None
        if not image_path.exists():
            continue
        if depth_path is not None and not depth_path.exists():
            continue
        frames.append(
            SessionFrameRecord(
                index=index,
                image_path=image_path,
                depth_path=depth_path,
                timestamp=float(frame.get("timestamp", 0.0)),
                transform_matrix=frame["transform_matrix"],
            )
        )
    return frames


def print_topics() -> None:
    print("topics:")
    print(f"  {CAMERA_RGB_TOPIC}")
    print(f"  {CAMERA_DEPTH_TOPIC}")
    print(f"  {CAMERA_INFO_TOPIC}")
    print(f"  {CAMERA_POSE_TOPIC}")
    print(f"  {SESSION_STATE_TOPIC}")


def dry_run_publish_session_start(tracker: SessionTracker) -> None:
    print(f"[dry-run] session_start name={tracker.session_name or tracker.session_dir.name} mode={tracker.session_mode}")


def dry_run_publish_frame(frame: SessionFrameRecord) -> None:
    has_depth = frame.depth_path is not None
    print(f"[dry-run] publish frame={frame.index:06d} rgb={frame.image_path.name} depth={'yes' if has_depth else 'no'} timestamp={frame.timestamp:.3f}")


def to_common_frame(frame: SessionFrameRecord) -> SessionFrame:
    return SessionFrame(
        index=frame.index,
        timestamp=frame.timestamp,
        image_path=frame.image_path,
        depth_path=frame.depth_path,
        transform_matrix=frame.transform_matrix,
    )


def dry_run_publish_session_state(session_dir: Path, frame_count: int) -> None:
    print(f"[dry-run] session_state session={session_dir.name} published_frames={frame_count}")


def dry_run_publish_session_end(session_dir: Path, frame_count: int) -> None:
    print(f"[dry-run] session_end session={session_dir.name} published_frames={frame_count}")


def session_is_complete(manifest: dict, tracker: SessionTracker, ready_frames: List[SessionFrameRecord]) -> bool:
    expected = len(manifest.get("frames", []))
    return tracker.manifest_loaded and expected > 0 and len(ready_frames) >= expected


def run_dry_loop(config: LiveBridgeConfig) -> None:
    trackers: Dict[Path, SessionTracker] = {}
    print(f"watch_dir: {config.watch_dir}")
    print(f"poll_interval: {config.poll_interval}")
    print_topics()

    while True:
        for session_dir in discover_session_dirs(config.watch_dir):
            tracker = trackers.get(session_dir)
            if tracker is None:
                tracker = SessionTracker(session_dir=session_dir)
                trackers[session_dir] = tracker

            manifest = load_manifest(session_dir)
            if manifest is None:
                continue

            if not tracker.manifest_loaded:
                tracker.manifest_loaded = True
                tracker.session_name = str(manifest.get("session_name", session_dir.name))
                tracker.session_mode = str(manifest.get("session_mode", "mapping"))
                dry_run_publish_session_start(tracker)

            ready_frames = extract_ready_frames(session_dir, manifest)
            new_frames = [frame for frame in ready_frames if frame.index not in tracker.published_indices]
            for frame in new_frames:
                dry_run_publish_frame(frame)
                tracker.published_indices.add(frame.index)

            if tracker.manifest_loaded:
                dry_run_publish_session_state(session_dir, len(tracker.published_indices))
                if session_is_complete(manifest, tracker, ready_frames) and not tracker.session_closed:
                    tracker.session_closed = True
                    dry_run_publish_session_end(session_dir, len(tracker.published_indices))

        if config.once:
            break
        time.sleep(max(0.1, config.poll_interval))


def run_ros2_loop(config: LiveBridgeConfig) -> None:
    try:
        import rclpy
        from rclpy.node import Node
        from std_msgs.msg import String
    except ImportError as exc:
        raise RuntimeError(
            "ROS 2 Python dependencies are missing. Use --dry-run here and run live mode on the ROS2 machine later."
        ) from exc

    class LiveBridgeNode(Node):
        def __init__(self):
            super().__init__("openbene_live_bridge")
            from sensor_msgs.msg import CameraInfo, CompressedImage, Image as RosImage
            from geometry_msgs.msg import PoseStamped

            self.session_state_pub = self.create_publisher(String, SESSION_STATE_TOPIC, 10)
            self.rgb_pub = self.create_publisher(CompressedImage, CAMERA_RGB_TOPIC, 10)
            self.depth_pub = self.create_publisher(RosImage, CAMERA_DEPTH_TOPIC, 10)
            self.camera_info_pub = self.create_publisher(CameraInfo, CAMERA_INFO_TOPIC, 10)
            self.pose_pub = self.create_publisher(PoseStamped, CAMERA_POSE_TOPIC, 10)
            self.get_logger().info(f"Watching {config.watch_dir}")

        def publish_session_state(self, payload: dict) -> None:
            msg = String()
            msg.data = json.dumps(payload)
            self.session_state_pub.publish(msg)

    rclpy.init()
    node = LiveBridgeNode()
    trackers: Dict[Path, SessionTracker] = {}

    try:
        while True:
            for session_dir in discover_session_dirs(config.watch_dir):
                tracker = trackers.get(session_dir)
                if tracker is None:
                    tracker = SessionTracker(session_dir=session_dir)
                    trackers[session_dir] = tracker

                manifest = load_manifest(session_dir)
                if manifest is None:
                    continue

                if not tracker.manifest_loaded:
                    tracker.manifest_loaded = True
                    tracker.session_name = str(manifest.get("session_name", session_dir.name))
                    tracker.session_mode = str(manifest.get("session_mode", "mapping"))
                    node.get_logger().info(f"Session discovered: {tracker.session_name} ({tracker.session_mode})")
                    node.publish_session_state({
                        "event": "session_start",
                        "session_name": tracker.session_name,
                        "session_mode": tracker.session_mode,
                        "published_frames": 0,
                    })

                ready_frames = extract_ready_frames(session_dir, manifest)
                new_frames = [frame for frame in ready_frames if frame.index not in tracker.published_indices]
                for frame in new_frames:
                    common_frame = to_common_frame(frame)
                    now = node.get_clock().now().to_msg()
                    node.camera_info_pub.publish(make_camera_info_msg(manifest, now, config.frame_id))
                    node.rgb_pub.publish(make_rgb_msg(common_frame, now, config.frame_id))
                    depth_msg = make_depth_msg(common_frame, now, config.frame_id)
                    if depth_msg is not None:
                        node.depth_pub.publish(depth_msg)
                    node.pose_pub.publish(make_pose_msg(common_frame, now, config.world_frame))
                    tracker.published_indices.add(frame.index)
                    node.get_logger().info(f"Published live frame: {frame.index:06d}")

                node.publish_session_state({
                    "event": "session_update",
                    "session_name": tracker.session_name or session_dir.name,
                    "session_mode": tracker.session_mode,
                    "published_frames": len(tracker.published_indices),
                })

                if session_is_complete(manifest, tracker, ready_frames) and not tracker.session_closed:
                    tracker.session_closed = True
                    node.publish_session_state({
                        "event": "session_end",
                        "session_name": tracker.session_name or session_dir.name,
                        "session_mode": tracker.session_mode,
                        "published_frames": len(tracker.published_indices),
                    })

            rclpy.spin_once(node, timeout_sec=0.05)
            if config.once:
                break
            time.sleep(max(0.1, config.poll_interval))
    finally:
        node.destroy_node()
        rclpy.shutdown()


def main() -> None:
    args = parse_args()
    config = LiveBridgeConfig(
        watch_dir=args.watch_dir.expanduser().resolve(),
        frame_id=args.frame_id,
        world_frame=args.world_frame,
        dry_run=args.dry_run,
        poll_interval=float(args.poll_interval),
        once=args.once,
    )

    if config.dry_run:
        run_dry_loop(config)
        return

    run_ros2_loop(config)


if __name__ == "__main__":
    main()
