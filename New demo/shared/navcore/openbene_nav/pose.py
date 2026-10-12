"""Robot pose estimation: AR anchor alignment plus wheel-odometry dead reckoning.

Two coordinate frames are involved.

* the map frame (x east, y north, yaw counter-clockwise from +x) that the demo
  map JSON is written in;
* the AR world frame of ARKit / ARCore, whose horizontal plane is gravity
  aligned and whose origin is wherever the AR session started.

When a marker is detected we know the marker pose in both frames, so the rigid
transform between them can be solved once and reused for every later AR frame.
Wheel odometry keeps the estimate alive while the AR track is lost, and every
new marker detection collapses the drift back to zero.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Optional

from .model import MapData, Marker, Pose2D, wrap_rad


@dataclass(frozen=True)
class ArObservation:
    """One AR frame in which a marker was visible.

    Both poses are planar projections of the AR session poses: x and y are the
    horizontal position, yaw is the heading of the described frame around the
    gravity axis. For the marker that is the direction of the marker image +y
    axis, for the device it is the direction the camera looks at.
    """

    marker_id: str
    marker_in_ar: Pose2D
    device_in_ar: Pose2D
    timestamp_s: float = 0.0


class PoseEstimator:
    def __init__(
        self,
        map_data: MapData,
        wheel_base_m: float = 0.30,
        wheel_radius_m: float = 0.0325,
    ) -> None:
        self.map_data = map_data
        self.wheel_base_m = float(wheel_base_m)
        self.wheel_radius_m = float(wheel_radius_m)

        self.aligned: bool = False
        self.map_from_ar: Optional[Pose2D] = None
        self.pose: Optional[Pose2D] = None
        self.last_marker_id: Optional[str] = None
        self.last_fix_time_s: float = 0.0
        self.drift_m: float = 0.0
        self.ar_updates: int = 0
        self.odometry_updates: int = 0

    # ---------------------------------------------------------------- anchors

    def align(self, observation: ArObservation) -> Pose2D:
        """Solve the map/AR transform from a marker detection and snap the pose."""

        marker = self.map_data.marker(observation.marker_id)
        # The marker is known in both frames, so map_from_ar is solved once:
        # map_from_marker composed with marker_from_ar.
        map_from_ar = marker.pose.compose(observation.marker_in_ar.inverse())
        self.map_from_ar = map_from_ar
        self.aligned = True
        self.last_marker_id = observation.marker_id
        self.last_fix_time_s = observation.timestamp_s

        pose = map_from_ar.compose(observation.device_in_ar)
        self.pose = pose
        self.drift_m = 0.0
        self.ar_updates += 1
        return pose

    def update_from_ar(self, device_in_ar: Pose2D, timestamp_s: float = 0.0) -> Optional[Pose2D]:
        """Update the pose from an AR frame while already aligned."""

        if not self.aligned or self.map_from_ar is None:
            return None
        pose = self.map_from_ar.compose(device_in_ar)
        self.pose = pose
        self.drift_m = 0.0
        self.last_fix_time_s = timestamp_s
        self.ar_updates += 1
        return pose

    # -------------------------------------------------------------- odometry

    def integrate_odometry(self, rpm_left: float, rpm_right: float, dt_s: float) -> Optional[Pose2D]:
        """Dead-reckon the pose from wheel speeds reported by the OpenBot firmware."""

        if self.pose is None or dt_s <= 0.0:
            return self.pose

        circumference = 2.0 * math.pi * self.wheel_radius_m
        v_left = (float(rpm_left) / 60.0) * circumference
        v_right = (float(rpm_right) / 60.0) * circumference
        linear = 0.5 * (v_left + v_right)
        angular = (v_right - v_left) / self.wheel_base_m

        moved = self.pose.translated(linear * dt_s)
        self.pose = Pose2D(moved.x, moved.y, wrap_rad(self.pose.yaw_rad + angular * dt_s))
        self.drift_m += abs(linear * dt_s)
        self.odometry_updates += 1
        return self.pose

    # --------------------------------------------------------------- helpers

    def require_pose(self) -> Pose2D:
        if self.pose is None:
            raise RuntimeError("pose is not known yet: align on a marker first")
        return self.pose

    def marker_pose_in_map(self, marker: Marker) -> Pose2D:
        return marker.pose

    def reset(self) -> None:
        self.aligned = False
        self.map_from_ar = None
        self.pose = None
        self.last_marker_id = None
        self.drift_m = 0.0
