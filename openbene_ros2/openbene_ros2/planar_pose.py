"""Helpers for projecting OpenBene camera poses into a 2D ROS odom plane."""

from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Sequence


@dataclass(frozen=True)
class PlanarPose:
    """A planar pose in ROS-style x/y/yaw form."""

    x: float
    y: float
    yaw: float


def planar_pose_from_opengl_camera_transform(
    transform_matrix: Sequence[Sequence[float]],
) -> PlanarPose:
    """Project an OpenGL camera-to-world pose onto the world XZ ground plane."""
    if len(transform_matrix) != 4 or any(len(row) != 4 for row in transform_matrix):
        raise ValueError("transform_matrix must be a 4x4 matrix.")

    x = float(transform_matrix[0][3])
    y = float(transform_matrix[2][3])

    # OpenGL camera poses look down the negative Z axis in camera space.
    forward_x = -float(transform_matrix[0][2])
    forward_y = -float(transform_matrix[2][2])
    yaw = math.atan2(forward_y, forward_x)

    return PlanarPose(x=x, y=y, yaw=yaw)


def quaternion_from_yaw(yaw: float) -> tuple[float, float, float, float]:
    """Return a ROS quaternion for a rotation around +Z."""
    half_yaw = yaw * 0.5
    return (0.0, 0.0, math.sin(half_yaw), math.cos(half_yaw))
