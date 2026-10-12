"""Route execution state machine.

The executor drives the OpenBot along the polyline of a route, expects a marker
fix during the approach of every anchored location, stops and rotates in place
when that fix is missing, and keeps the robot safe when the sonar or the bumper
reports something in the way.

The exact same state machine is implemented in the Android and iOS demos. This
version is the one covered by the unit tests and by the simulator.
"""

from __future__ import annotations

import math
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional

from .model import MapData, Pose2D
from .pose import PoseEstimator
from .robot_link import RobotLink
from .router import Route


class ExecutorState(str, Enum):
    IDLE = "idle"
    NEED_ANCHOR = "need_anchor"
    SCANNING = "scanning"
    DRIVING = "driving"
    ARRIVED = "arrived"
    BLOCKED = "blocked"
    FAILED = "failed"


@dataclass
class ExecutorConfig:
    waypoint_tolerance_m: float = 0.30
    arrival_tolerance_m: float = 0.40
    heading_tolerance_deg: float = 15.0
    cruise_speed: float = 0.35
    turn_speed: float = 0.22
    steer_gain: float = 1.6
    obstacle_stop_cm: float = 35.0
    obstacle_clear_cm: float = 50.0
    reanchor_at_waypoints: bool = True
    reanchor_drift_m: float = 4.0
    marker_scan_radius_m: float = 1.0
    marker_scan_heading_deg: float = 40.0
    hold_timeout_s: float = 2.5
    allow_scan_rotation: bool = True
    scan_speed: float = 0.25
    scan_timeout_s: float = 30.0


@dataclass
class ExecutorStatus:
    state: ExecutorState
    message: str
    leg_index: int = 0
    point_index: int = 0
    target: Optional[Pose2D] = None
    distance_to_target_m: float = 0.0
    distance_remaining_m: float = 0.0
    pose: Optional[Pose2D] = None
    drift_m: float = 0.0
    drift_warning: bool = False
    expected_marker_id: Optional[str] = None
    used_markers: List[str] = field(default_factory=list)


class RouteExecutor:
    def __init__(
        self,
        map_data: MapData,
        estimator: PoseEstimator,
        link: RobotLink,
        config: Optional[ExecutorConfig] = None,
    ) -> None:
        self.map_data = map_data
        self.estimator = estimator
        self.link = link
        self.config = config or ExecutorConfig()

        self.route: Optional[Route] = None
        self.state: ExecutorState = ExecutorState.IDLE
        self.leg_index: int = 0
        self.point_index: int = 0
        self.message: str = "idle"
        self.used_markers: List[str] = []
        self._expected_marker_id: Optional[str] = None
        self._leg_arrival_marker_id: Optional[str] = None
        self._leg_marker_fixed: bool = False
        self._drift_warning: bool = False
        self._scan_started_s: Optional[float] = None
        self._started_s: Optional[float] = None
        self._last_odometry_s: Optional[float] = None

    # ------------------------------------------------------------------ setup

    def start(self, route: Route, start_location_id: Optional[str] = None) -> None:
        self.route = route
        self.leg_index = 0
        self.point_index = 0
        self.used_markers = []
        self._started_s = None
        self._last_odometry_s = None
        self._scan_started_s = None
        self._expected_marker_id = None
        self._leg_arrival_marker_id = None
        self._leg_marker_fixed = False
        self._drift_warning = False

        if self.estimator.aligned:
            self._begin_leg()
            self.state = ExecutorState.DRIVING
            self.message = "route accepted"
            return

        self._begin_leg()
        location = self.map_data.location(start_location_id or route.start_location_id)
        self._request_anchor(location.marker_id, "scan marker of " + location.name)

    def stop(self) -> None:
        self.link.stop()
        self.state = ExecutorState.IDLE
        self.message = "stopped"

    # ------------------------------------------------------------------- tick

    def tick(self, dt_s: float, now_s: Optional[float] = None) -> ExecutorStatus:
        now = time.monotonic() if now_s is None else float(now_s)
        if self._started_s is None:
            self._started_s = now
        if self.route is None:
            self.link.stop()
            return self._status()

        self._integrate_odometry(now)

        if self._bumper_hit():
            self.link.stop()
            self.state = ExecutorState.FAILED
            self.message = "bumper collision: clear the robot and restart the route"
            return self._status()

        if self._obstacle_ahead():
            self.link.stop()
            self.state = ExecutorState.BLOCKED
            self.message = "obstacle at {:.0f} cm".format(self.link.telemetry.sonar_cm or 0.0)
            return self._status()

        if self.state is ExecutorState.BLOCKED:
            self.message = "path clear, resuming"
            self.state = ExecutorState.DRIVING if self.estimator.aligned else ExecutorState.NEED_ANCHOR

        if self.state in (ExecutorState.ARRIVED, ExecutorState.FAILED):
            self.link.stop()
            return self._status()

        if self.state in (ExecutorState.NEED_ANCHOR, ExecutorState.SCANNING) or not self.estimator.aligned:
            self._handle_anchor_wait(now)
            return self._status()

        if self.estimator.drift_m > self.config.reanchor_drift_m:
            nearby = self._reachable_marker()
            if nearby is not None:
                self._request_anchor(
                    nearby.id,
                    "dead-reckoning drift {:.1f} m: re-localise on {}".format(self.estimator.drift_m, nearby.id),
                )
                self._handle_anchor_wait(now)
                return self._status()
            self._drift_warning = True

        self._drive_route()
        return self._status()

    # ------------------------------------------------------------- behaviours

    def _begin_leg(self) -> None:
        if self.route is None or self.leg_index >= len(self.route.legs):
            self._leg_arrival_marker_id = None
            self._leg_marker_fixed = False
            return
        leg = self.route.legs[self.leg_index]
        self._leg_arrival_marker_id = self.map_data.location(leg.to_id).marker_id
        self._leg_marker_fixed = False

    def _drive_route(self) -> None:
        route = self.route
        assert route is not None
        if self.leg_index >= len(route.legs):
            self._finish()
            return

        leg = route.legs[self.leg_index]
        target = leg.path[self.point_index]
        pose = self.estimator.require_pose()
        distance = pose.distance_to(target)
        last_point = self.point_index == len(leg.path) - 1
        last_leg = self.leg_index == len(route.legs) - 1
        tolerance = self.config.arrival_tolerance_m if (last_point and last_leg) else self.config.waypoint_tolerance_m

        if distance <= tolerance:
            if not last_point:
                self.point_index += 1
                return
            if not last_leg:
                self._advance_leg()
                return
            self._finish()
            return

        self.state = ExecutorState.DRIVING
        self.message = "driving to waypoint {}, {:.1f} m".format(self.point_index, distance)
        self._steer_towards(target, pose)

    def _advance_leg(self) -> None:
        assert self.route is not None
        leg = self.route.legs[self.leg_index]
        arrival = self.map_data.location(leg.to_id)
        if self.config.reanchor_at_waypoints and arrival.marker_id and not self._leg_marker_fixed:
            self._request_anchor(arrival.marker_id, "re-localise on marker of " + arrival.name)
            self.state = ExecutorState.SCANNING
            return
        self.leg_index += 1
        self.point_index = 0
        self._begin_leg()
        self.state = ExecutorState.DRIVING

    def _finish(self) -> None:
        assert self.route is not None
        self.link.stop()
        self.state = ExecutorState.ARRIVED
        self.message = "arrived at " + self.route.room.name

    def _request_anchor(self, marker_id: Optional[str], message: str) -> None:
        self.link.stop()
        self.state = ExecutorState.NEED_ANCHOR
        self._expected_marker_id = marker_id
        self.message = message
        self._scan_started_s = None

    def _handle_anchor_wait(self, now: float) -> None:
        if self._expected_marker_id is None:
            self._expected_marker_id = self._nearest_marker_id()
        if self._expected_marker_id is None:
            self.link.stop()
            self.state = ExecutorState.FAILED
            self.message = "no marker available to localise"
            return
        if self._scan_started_s is None:
            self._scan_started_s = now
        if now - self._scan_started_s > self.config.scan_timeout_s:
            self.link.stop()
            self.state = ExecutorState.FAILED
            self.message = "marker {} not found within {:.0f} s".format(
                self._expected_marker_id, self.config.scan_timeout_s
            )
            return
        holding = self._facing_expected_marker() and (now - self._scan_started_s) < self.config.hold_timeout_s
        if holding:
            self.link.stop()
            self.message = "hold position, looking for marker " + str(self._expected_marker_id)
        elif self.config.allow_scan_rotation:
            self.link.drive(-self.config.scan_speed, self.config.scan_speed)
            self.message = "rotating to find marker " + str(self._expected_marker_id)
        else:
            self.link.stop()
            self.message = "waiting for marker " + str(self._expected_marker_id)

    def _expected_marker_pose(self) -> Optional[Pose2D]:
        if self._expected_marker_id is None:
            return None
        try:
            return self.map_data.marker(self._expected_marker_id).pose
        except KeyError:
            return None

    def _facing_expected_marker(self) -> bool:
        marker = self._expected_marker_pose()
        pose = self.estimator.pose
        if marker is None or pose is None:
            return False
        return abs(pose.heading_error_to(marker)) <= math.radians(self.config.marker_scan_heading_deg)

    def _reachable_marker(self):
        """The nearest marker that is close enough for the camera to see it."""

        pose = self.estimator.pose
        if pose is None:
            return None
        best = None
        best_distance = float("inf")
        for marker in self.map_data.markers:
            distance = pose.distance_to(marker.pose)
            if distance <= self.config.marker_scan_radius_m and distance < best_distance:
                best = marker
                best_distance = distance
        return best

    def _steer_towards(self, target: Pose2D, pose: Pose2D) -> None:
        error = pose.heading_error_to(target)
        if abs(error) > math.radians(self.config.heading_tolerance_deg):
            speed = self.config.turn_speed
            if error > 0:
                self.link.drive(-speed, speed)
            else:
                self.link.drive(speed, -speed)
            return

        steer = max(-1.0, min(1.0, self.config.steer_gain * error))
        speed = self.config.cruise_speed
        left = speed * (1.0 - steer)
        right = speed * (1.0 + steer)
        scale = max(abs(left), abs(right), 1e-6)
        if scale > 1.0:
            left /= scale
            right /= scale
        self.link.drive(left, right)

    # ----------------------------------------------------------------- helpers

    def _integrate_odometry(self, now: float) -> None:
        telemetry = self.link.telemetry
        if self._last_odometry_s is None:
            self._last_odometry_s = now
            return
        elapsed = max(0.0, now - self._last_odometry_s)
        self._last_odometry_s = now
        self.estimator.integrate_odometry(telemetry.rpm_left, telemetry.rpm_right, elapsed)

    def _obstacle_ahead(self) -> bool:
        sonar = self.link.telemetry.sonar_cm
        if sonar is None:
            return False
        if self.state is ExecutorState.BLOCKED:
            return sonar <= self.config.obstacle_clear_cm
        return sonar <= self.config.obstacle_stop_cm

    def _bumper_hit(self) -> bool:
        return self.link.telemetry.bumper is not None

    def _nearest_marker_id(self) -> Optional[str]:
        if self.estimator.pose is None:
            if self.route is not None:
                return self.map_data.location(self.route.start_location_id).marker_id
            return None
        return self.map_data.nearest_location(self.estimator.pose).marker_id

    def _remaining_distance(self) -> float:
        if self.route is None or self.estimator.pose is None:
            return 0.0
        if self.state is ExecutorState.ARRIVED:
            return 0.0
        remaining = 0.0
        pose = self.estimator.pose
        for leg_index in range(self.leg_index, len(self.route.legs)):
            leg = self.route.legs[leg_index]
            start_index = self.point_index if leg_index == self.leg_index else 0
            previous = pose if leg_index == self.leg_index else leg.path[0]
            for point in leg.path[start_index:]:
                remaining += previous.distance_to(point)
                previous = point
        return remaining

    def _status(self) -> ExecutorStatus:
        pose = self.estimator.pose
        target: Optional[Pose2D] = None
        distance_to_target = 0.0
        if self.route is not None and self.leg_index < len(self.route.legs):
            leg = self.route.legs[self.leg_index]
            if self.point_index < len(leg.path):
                target = leg.path[self.point_index]
                if pose is not None:
                    distance_to_target = pose.distance_to(target)
        return ExecutorStatus(
            state=self.state,
            message=self.message,
            leg_index=self.leg_index,
            point_index=self.point_index,
            target=target,
            distance_to_target_m=distance_to_target,
            distance_remaining_m=self._remaining_distance(),
            pose=pose,
            drift_m=self.estimator.drift_m,
            drift_warning=self._drift_warning,
            expected_marker_id=self._expected_marker_id,
            used_markers=list(self.used_markers),
        )

    def note_marker(self, marker_id: str) -> None:
        """Called by the app or the harness right after a marker alignment."""

        if marker_id not in self.used_markers:
            self.used_markers.append(marker_id)
        if marker_id == self._leg_arrival_marker_id:
            self._leg_marker_fixed = True

        if self.state is ExecutorState.SCANNING:
            if marker_id == self._expected_marker_id:
                self.leg_index += 1
                self.point_index = 0
                self._begin_leg()
                self.state = ExecutorState.DRIVING
                self.message = "re-localised on " + marker_id
                self._scan_started_s = None
            return

        if self.state is ExecutorState.NEED_ANCHOR:
            self.state = ExecutorState.DRIVING
            self.message = "localised on " + marker_id
            self._scan_started_s = None

    @property
    def expected_marker_id(self) -> Optional[str]:
        return self._expected_marker_id

    @property
    def scan_started_s(self) -> Optional[float]:
        return self._scan_started_s
