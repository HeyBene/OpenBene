#!/usr/bin/env python3
"""
Replay an OpenBene LiDAR capture session into ROS 2 topics.

This is the ROS2 bridge v1 for OpenBene. Its current role is session replay,
which is the fastest path to validating ROS2 integration before adding live
receiver streaming.

Current output topics:
- /openbene/camera/rgb/image_raw/compressed
- /openbene/camera/depth/image_raw
- /openbene/camera/camera_info
- /openbene/camera/pose

Future live mode is expected to reuse the same topic structure with WebSocket
receiver input instead of session directory replay.
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path
from typing import List

import sys

CURRENT_DIR = Path(__file__).resolve().parent
if str(CURRENT_DIR) not in sys.path:
    sys.path.insert(0, str(CURRENT_DIR))

from ros2_bridge_common import (
    CAMERA_DEPTH_TOPIC,
    CAMERA_INFO_TOPIC,
    CAMERA_POSE_TOPIC,
    CAMERA_RGB_TOPIC,
    SessionFrame,
    load_session,
    make_camera_info_msg,
    make_depth_msg,
    make_pose_msg,
    make_rgb_msg,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Replay an OpenBene capture session to ROS 2")
    parser.add_argument("session_dir", type=Path, help="Path to session directory")
    parser.add_argument("--dry-run", action="store_true", help="Validate session and print replay plan without ROS 2")
    parser.add_argument("--rate", type=float, default=1.0, help="Playback rate multiplier (default: 1.0)")
    parser.add_argument("--frame-id", type=str, default="openbene_camera", help="ROS frame_id for camera topics")
    parser.add_argument("--world-frame", type=str, default="openbene_world", help="ROS frame_id for pose world frame")
    return parser.parse_args()


def print_dry_run(manifest: dict, frames: List[SessionFrame], session_dir: Path) -> None:
    depth_count = sum(1 for frame in frames if frame.depth_path is not None)
    print(f"session_dir: {session_dir}")
    print(f"frame_count: {len(frames)}")
    print(f"depth_frame_count: {depth_count}")
    print(f"image_size: {manifest.get('w')}x{manifest.get('h')}")
    print(f"fx_fy: {manifest.get('fl_x')}, {manifest.get('fl_y')}")
    print(f"session_mode: {manifest.get('session_mode', 'mapping')}")
    print("topics:")
    print(f"  {CAMERA_RGB_TOPIC}")
    print(f"  {CAMERA_DEPTH_TOPIC}")
    print(f"  {CAMERA_INFO_TOPIC}")
    print(f"  {CAMERA_POSE_TOPIC}")
    if frames:
        print(f"first_rgb: {frames[0].image_path}")
        if frames[0].depth_path:
            print(f"first_depth: {frames[0].depth_path}")


def run_ros2_replay(manifest: dict, frames: List[SessionFrame], rate: float, frame_id: str, world_frame: str) -> None:
    try:
        import rclpy
        from rclpy.node import Node
        from sensor_msgs.msg import CompressedImage, Image as RosImage, CameraInfo
        from geometry_msgs.msg import PoseStamped
    except ImportError as exc:
        raise RuntimeError(
            "ROS 2 Python dependencies are missing. Run with --dry-run here, or install ROS 2 and rclpy on the target machine."
        ) from exc

    class SessionReplayNode(Node):
        def __init__(self):
            super().__init__("openbene_session_replay")
            self.rgb_pub = self.create_publisher(CompressedImage, CAMERA_RGB_TOPIC, 10)
            self.depth_pub = self.create_publisher(RosImage, CAMERA_DEPTH_TOPIC, 10)
            self.camera_info_pub = self.create_publisher(CameraInfo, CAMERA_INFO_TOPIC, 10)
            self.pose_pub = self.create_publisher(PoseStamped, CAMERA_POSE_TOPIC, 10)

    rclpy.init()
    node = SessionReplayNode()

    try:
        previous_timestamp = None
        for frame in frames:
            now = node.get_clock().now().to_msg()

            node.camera_info_pub.publish(make_camera_info_msg(manifest, now, frame_id))
            node.rgb_pub.publish(make_rgb_msg(frame, now, frame_id))

            depth_msg = make_depth_msg(frame, now, frame_id)
            if depth_msg is not None:
                node.depth_pub.publish(depth_msg)

            node.pose_pub.publish(make_pose_msg(frame, now, world_frame))
            node.get_logger().info(f"Published frame {frame.index:06d}")

            if previous_timestamp is not None:
                dt = max(0.0, (frame.timestamp - previous_timestamp) / max(rate, 1e-6))
                time.sleep(dt)
            previous_timestamp = frame.timestamp
    finally:
        node.destroy_node()
        rclpy.shutdown()


def main() -> None:
    args = parse_args()
    session_dir = args.session_dir.expanduser().resolve()
    manifest, frames = load_session(session_dir)

    if args.dry_run:
        print_dry_run(manifest, frames, session_dir)
        return

    run_ros2_replay(
        manifest=manifest,
        frames=frames,
        rate=max(args.rate, 1e-6),
        frame_id=args.frame_id,
        world_frame=args.world_frame,
    )


if __name__ == "__main__":
    main()
