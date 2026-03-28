#!/usr/bin/env python3
"""Shared helpers for OpenBene ROS2 bridge code."""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

from PIL import Image


CAMERA_RGB_TOPIC = "/openbene/camera/rgb/image_raw/compressed"
CAMERA_DEPTH_TOPIC = "/openbene/camera/depth/image_raw"
CAMERA_INFO_TOPIC = "/openbene/camera/camera_info"
CAMERA_POSE_TOPIC = "/openbene/camera/pose"
SESSION_STATE_TOPIC = "/openbene/session/state"


@dataclass
class SessionFrame:
    index: int
    timestamp: float
    image_path: Path
    depth_path: Optional[Path]
    transform_matrix: List[List[float]]


def load_session(session_dir: Path) -> Tuple[dict, List[SessionFrame]]:
    manifest_path = session_dir / "transforms.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"Missing transforms.json: {manifest_path}")

    manifest = json.loads(manifest_path.read_text())
    frames: List[SessionFrame] = []
    for index, frame in enumerate(manifest.get("frames", [])):
        image_path = session_dir / frame["file_path"]
        depth_path = session_dir / frame["depth_file_path"] if frame.get("depth_file_path") else None
        frames.append(
            SessionFrame(
                index=index,
                timestamp=float(frame.get("timestamp", 0.0)),
                image_path=image_path,
                depth_path=depth_path,
                transform_matrix=frame["transform_matrix"],
            )
        )
    return manifest, frames


def rotation_matrix_to_quaternion(rotation: Sequence[Sequence[float]]) -> Tuple[float, float, float, float]:
    trace = rotation[0][0] + rotation[1][1] + rotation[2][2]
    if trace > 0.0:
        s = math.sqrt(trace + 1.0) * 2.0
        qw = 0.25 * s
        qx = (rotation[2][1] - rotation[1][2]) / s
        qy = (rotation[0][2] - rotation[2][0]) / s
        qz = (rotation[1][0] - rotation[0][1]) / s
    elif rotation[0][0] > rotation[1][1] and rotation[0][0] > rotation[2][2]:
        s = math.sqrt(1.0 + rotation[0][0] - rotation[1][1] - rotation[2][2]) * 2.0
        qw = (rotation[2][1] - rotation[1][2]) / s
        qx = 0.25 * s
        qy = (rotation[0][1] + rotation[1][0]) / s
        qz = (rotation[0][2] + rotation[2][0]) / s
    elif rotation[1][1] > rotation[2][2]:
        s = math.sqrt(1.0 + rotation[1][1] - rotation[0][0] - rotation[2][2]) * 2.0
        qw = (rotation[0][2] - rotation[2][0]) / s
        qx = (rotation[0][1] + rotation[1][0]) / s
        qy = 0.25 * s
        qz = (rotation[1][2] + rotation[2][1]) / s
    else:
        s = math.sqrt(1.0 + rotation[2][2] - rotation[0][0] - rotation[1][1]) * 2.0
        qw = (rotation[1][0] - rotation[0][1]) / s
        qx = (rotation[0][2] + rotation[2][0]) / s
        qy = (rotation[1][2] + rotation[2][1]) / s
        qz = 0.25 * s
    return qx, qy, qz, qw


def make_camera_info_msg(manifest: dict, stamp, frame_id: str):
    from sensor_msgs.msg import CameraInfo

    msg = CameraInfo()
    msg.header.stamp = stamp
    msg.header.frame_id = frame_id
    msg.width = int(manifest["w"])
    msg.height = int(manifest["h"])
    msg.k = [
        float(manifest["fl_x"]), 0.0, float(manifest["cx"]),
        0.0, float(manifest["fl_y"]), float(manifest["cy"]),
        0.0, 0.0, 1.0,
    ]
    msg.p = [
        float(manifest["fl_x"]), 0.0, float(manifest["cx"]), 0.0,
        0.0, float(manifest["fl_y"]), float(manifest["cy"]), 0.0,
        0.0, 0.0, 1.0, 0.0,
    ]
    return msg


def make_pose_msg(frame: SessionFrame, stamp, world_frame: str):
    from geometry_msgs.msg import PoseStamped

    pose = frame.transform_matrix
    rotation = [[pose[i][j] for j in range(3)] for i in range(3)]
    qx, qy, qz, qw = rotation_matrix_to_quaternion(rotation)

    msg = PoseStamped()
    msg.header.stamp = stamp
    msg.header.frame_id = world_frame
    msg.pose.position.x = float(pose[0][3])
    msg.pose.position.y = float(pose[1][3])
    msg.pose.position.z = float(pose[2][3])
    msg.pose.orientation.x = qx
    msg.pose.orientation.y = qy
    msg.pose.orientation.z = qz
    msg.pose.orientation.w = qw
    return msg


def make_rgb_msg(frame: SessionFrame, stamp, frame_id: str):
    from sensor_msgs.msg import CompressedImage

    msg = CompressedImage()
    msg.header.stamp = stamp
    msg.header.frame_id = frame_id
    msg.format = "jpeg"
    msg.data = frame.image_path.read_bytes()
    return msg


def make_depth_msg(frame: SessionFrame, stamp, frame_id: str):
    from sensor_msgs.msg import Image as RosImage

    if frame.depth_path is None:
        return None

    with Image.open(frame.depth_path) as depth_image:
        depth_image.load()
        width, height = depth_image.size
        raw_bytes = depth_image.tobytes()

    msg = RosImage()
    msg.header.stamp = stamp
    msg.header.frame_id = frame_id
    msg.width = width
    msg.height = height
    msg.encoding = "mono16"
    msg.is_bigendian = 0
    msg.step = width * 2
    msg.data = raw_bytes
    return msg
