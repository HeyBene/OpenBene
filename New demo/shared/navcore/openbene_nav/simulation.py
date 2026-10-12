"""A small differential-drive simulator used by the runnable demo.

It plays the role of the robot plus the AR sensor:

* it integrates the wheel commands and reports OpenBot-style telemetry
  (wheel rpm, sonar, bumper) into a RecordingLink;
* it hands out AR marker observations and AR device poses with configurable
  noise, an AR world that slowly distorts with travelled distance, and a
  deliberately biased wheel odometry so that anchor corrections are visible.

The AR session is only treated as usable for a short window after an anchor
fix, which mirrors a featureless corridor where the visual track degrades: the
robot then falls back on wheel odometry until the next marker.
"""

from __future__ import annotations

import math
import random
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

from .model import MapData, Pose2D, wrap_rad
from .pose import ArObservation
from .robot_link import RecordingLink, Telemetry


@dataclass
class SimConfig:
    wheel_base_m: float = 0.30
    wheel_radius_m: float = 0.0325
    max_wheel_speed_mps: float = 0.55
    odometry_scale_error: float = 0.08
    marker_detect_range_m: float = 1.8
    marker_half_fov_deg: float = 35.0
    marker_noise_xy_m: float = 0.02
    marker_noise_yaw_deg: float = 1.5
    sonar_max_cm: float = 200.0
    sonar_half_cone_deg: float = 12.0
    ar_tracking_window_s: float = 1.5
    ar_yaw_error_deg_per_m: float = 0.12
    ar_xy_error_m_per_m: float = 0.004
    dt_s: float = 0.05
    seed: int = 7


@dataclass
class Obstacle:
    x: float
    y: float
    radius_m: float
    clear_after_s: Optional[float] = None

    def active(self, time_s: float) -> bool:
        return self.clear_after_s is None or time_s < self.clear_after_s


@dataclass
class DifferentialDriveSim:
    pose: Pose2D
    config: SimConfig = field(default_factory=SimConfig)
    obstacles: List[Obstacle] = field(default_factory=list)
    time_s: float = 0.0
    travelled_m: float = 0.0

    def step(self, left: float, right: float, dt_s: float) -> None:
        v_left = left * self.config.max_wheel_speed_mps
        v_right = right * self.config.max_wheel_speed_mps
        linear = 0.5 * (v_left + v_right)
        angular = (v_right - v_left) / self.config.wheel_base_m
        moved = self.pose.translated(linear * dt_s)
        self.pose = Pose2D(moved.x, moved.y, wrap_rad(self.pose.yaw_rad + angular * dt_s))
        self.travelled_m += abs(linear * dt_s)
        self.time_s += dt_s

    def reported_rpm(self, left: float, right: float) -> Tuple[float, float]:
        scale = 1.0 + self.config.odometry_scale_error
        factor = scale / (2.0 * math.pi * self.config.wheel_radius_m) * 60.0
        return (
            left * self.config.max_wheel_speed_mps * factor,
            right * self.config.max_wheel_speed_mps * factor,
        )

    def sonar_cm(self) -> float:
        heading = self.pose.yaw_rad
        best = self.config.sonar_max_cm
        for obstacle in self.obstacles:
            if not obstacle.active(self.time_s):
                continue
            dx = obstacle.x - self.pose.x
            dy = obstacle.y - self.pose.y
            distance = max(0.0, math.hypot(dx, dy) - obstacle.radius_m)
            bearing = abs(wrap_rad(math.atan2(dy, dx) - heading))
            if bearing <= math.radians(self.config.sonar_half_cone_deg):
                best = min(best, distance * 100.0)
        return round(best, 1)


class SimulatedArSensor:
    """Marker observations and AR device poses, with drift and noise."""

    def __init__(self, map_data: MapData, config: SimConfig, ar_from_map: Pose2D) -> None:
        self.map_data = map_data
        self.config = config
        self.ar_from_map = ar_from_map
        self._random = random.Random(config.seed)
        self.last_anchor_s: Optional[float] = None
        self.anchor_count = 0

    def _distortion(self, travelled_m: float) -> Pose2D:
        return Pose2D(
            x=self.config.ar_xy_error_m_per_m * travelled_m,
            y=-0.5 * self.config.ar_xy_error_m_per_m * travelled_m,
            yaw_rad=math.radians(self.config.ar_yaw_error_deg_per_m * travelled_m),
        )

    def reported_ar_pose(self, true_pose: Pose2D, travelled_m: float) -> Pose2D:
        distorted_world = self._distortion(travelled_m).compose(self.ar_from_map)
        return distorted_world.compose(true_pose)

    def mark_anchor(self, time_s: float) -> None:
        self.last_anchor_s = time_s
        self.anchor_count += 1

    def ar_tracking_available(self, time_s: float) -> bool:
        if self.last_anchor_s is None:
            return False
        return (time_s - self.last_anchor_s) <= self.config.ar_tracking_window_s

    def ar_device_pose(self, true_pose: Pose2D, travelled_m: float, time_s: float) -> Optional[Pose2D]:
        if not self.ar_tracking_available(time_s):
            return None
        return self.reported_ar_pose(true_pose, travelled_m)

    def marker_observation(
        self,
        true_pose: Pose2D,
        travelled_m: float,
        time_s: float,
    ) -> Optional[ArObservation]:
        best = None
        best_distance = float("inf")
        for marker in self.map_data.markers:
            distance = true_pose.distance_to(marker.pose)
            if distance > self.config.marker_detect_range_m:
                continue
            if abs(true_pose.heading_error_to(marker.pose)) > math.radians(self.config.marker_half_fov_deg):
                continue
            if distance < best_distance:
                best = marker
                best_distance = distance
        if best is None:
            return None

        distorted_world = self._distortion(travelled_m).compose(self.ar_from_map)
        marker_in_ar = distorted_world.compose(best.pose)
        device_in_ar = distorted_world.compose(true_pose)
        noisy_device = Pose2D(
            device_in_ar.x + self._random.gauss(0.0, self.config.marker_noise_xy_m),
            device_in_ar.y + self._random.gauss(0.0, self.config.marker_noise_xy_m),
            wrap_rad(
                device_in_ar.yaw_rad
                + math.radians(self._random.gauss(0.0, self.config.marker_noise_yaw_deg))
            ),
        )
        return ArObservation(
            marker_id=best.id,
            marker_in_ar=marker_in_ar,
            device_in_ar=noisy_device,
            timestamp_s=time_s,
        )


def feed_telemetry(
    link: RecordingLink,
    sim: DifferentialDriveSim,
    left: float,
    right: float,
    now_s: float,
) -> Telemetry:
    rpm_left, rpm_right = sim.reported_rpm(left, right)
    telemetry = Telemetry(
        sonar_cm=sim.sonar_cm(),
        bumper=None,
        rpm_left=rpm_left,
        rpm_right=rpm_right,
        voltage=8.4,
        updated_at_s=now_s,
    )
    link.telemetry = telemetry
    return telemetry
