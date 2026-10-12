"""Closed-loop episode runner used by the CLI demo and by the tests.

It wires the simulator, the AR sensor, the pose estimator and the route
executor the same way the phone apps wire ARKit / ARCore, BLE telemetry and the
same state machine: every frame looks for a marker, aligns on it when one is
visible, otherwise falls back on the AR pose and on wheel odometry.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Callable, List, Optional, Sequence

from .executor import ExecutorConfig, ExecutorState, RouteExecutor
from .model import MapData, Pose2D, wrap_deg
from .pose import PoseEstimator
from .robot_link import RecordingLink
from .router import Route
from .simulation import DifferentialDriveSim, Obstacle, SimConfig, SimulatedArSensor, feed_telemetry


@dataclass
class TraceEvent:
    time_s: float
    state: str
    message: str
    true_x: float
    true_y: float
    est_x: float
    est_y: float
    drift_m: float
    error_m: float

    def format(self) -> str:
        return (
            "t={:6.1f}s {:10s} true=({:6.2f},{:6.2f}) est=({:6.2f},{:6.2f}) "
            "err={:4.2f}m drift={:4.2f}m  {}"
        ).format(
            self.time_s,
            self.state,
            self.true_x,
            self.true_y,
            self.est_x,
            self.est_y,
            self.error_m,
            self.drift_m,
            self.message,
        )


@dataclass
class EpisodeResult:
    arrived: bool
    final_state: str
    elapsed_s: float
    travelled_m: float
    used_markers: List[str] = field(default_factory=list)
    anchor_fixes: int = 0
    true_pose: Optional[Pose2D] = None
    estimated_pose: Optional[Pose2D] = None
    position_error_m: float = 0.0
    heading_error_deg: float = 0.0
    distance_to_goal_m: float = 0.0
    trace: List[TraceEvent] = field(default_factory=list)
    state_changes: List[str] = field(default_factory=list)

    def report(self) -> str:
        lines = [
            "result          : " + ("ARRIVED" if self.arrived else "NOT ARRIVED"),
            "final state     : " + self.final_state,
            "elapsed         : {:.1f} s".format(self.elapsed_s),
            "travelled       : {:.2f} m".format(self.travelled_m),
            "marker fixes    : {} ({})".format(self.anchor_fixes, ", ".join(self.used_markers) or "none"),
            "distance to goal: {:.2f} m".format(self.distance_to_goal_m),
            "position error  : {:.2f} m".format(self.position_error_m),
            "heading error   : {:.1f} deg".format(self.heading_error_deg),
        ]
        return "\n".join(lines)


def run_episode(
    map_data: MapData,
    route: Route,
    sim_config: Optional[SimConfig] = None,
    executor_config: Optional[ExecutorConfig] = None,
    start_pose: Optional[Pose2D] = None,
    obstacles: Optional[Sequence[Obstacle]] = None,
    max_time_s: float = 180.0,
    trace_every_s: float = 2.0,
    on_event: Optional[Callable[[TraceEvent], None]] = None,
    ar_from_map: Optional[Pose2D] = None,
) -> EpisodeResult:
    config = sim_config or SimConfig()
    dt = config.dt_s
    result = EpisodeResult(
        arrived=False,
        final_state=ExecutorState.IDLE.value,
        elapsed_s=0.0,
        travelled_m=0.0,
    )

    estimator = PoseEstimator(
        map_data,
        wheel_base_m=config.wheel_base_m,
        wheel_radius_m=config.wheel_radius_m,
    )
    link = RecordingLink()
    start = start_pose or map_data.location(route.start_location_id).pose
    sim = DifferentialDriveSim(pose=start, config=config, obstacles=list(obstacles or []))
    sensor = SimulatedArSensor(
        map_data,
        config,
        ar_from_map if ar_from_map is not None else Pose2D(3.5, -2.0, math.radians(37.0)),
    )
    executor = RouteExecutor(map_data, estimator, link, executor_config)
    executor.start(route)

    time_s = 0.0
    next_trace = 0.0
    last_state = executor.state
    visible_marker: Optional[str] = None

    while time_s < max_time_s:
        observation = sensor.marker_observation(sim.pose, sim.travelled_m, time_s)
        if observation is not None:
            estimator.align(observation)
            executor.note_marker(observation.marker_id)
            sensor.mark_anchor(time_s)
            if observation.marker_id not in result.used_markers:
                result.used_markers.append(observation.marker_id)
            if observation.marker_id != visible_marker:
                result.anchor_fixes += 1
            visible_marker = observation.marker_id
        else:
            visible_marker = None
            ar_pose = sensor.ar_device_pose(sim.pose, sim.travelled_m, time_s)
            if ar_pose is not None:
                estimator.update_from_ar(ar_pose, time_s)

        last = link.last_command or {"left": 0.0, "right": 0.0}
        feed_telemetry(link, sim, float(last["left"]), float(last["right"]), time_s)
        status = executor.tick(dt, time_s)

        command = link.last_command
        sim.step(float(command["left"]), float(command["right"]), dt)
        time_s += dt

        if executor.state is not last_state or time_s >= next_trace:
            event = _trace_event(time_s, status, sim, estimator)
            result.trace.append(event)
            if on_event is not None:
                on_event(event)
            if executor.state is not last_state:
                result.state_changes.append(
                    "{} -> {} ({})".format(last_state.value, executor.state.value, status.message)
                )
                next_trace = time_s + trace_every_s
                last_state = executor.state
            else:
                next_trace = time_s + trace_every_s

        if executor.state in (ExecutorState.ARRIVED, ExecutorState.FAILED):
            break

    result.arrived = executor.state is ExecutorState.ARRIVED
    result.final_state = executor.state.value
    result.elapsed_s = time_s
    result.travelled_m = sim.travelled_m
    result.true_pose = sim.pose
    result.estimated_pose = estimator.pose
    if estimator.pose is not None:
        result.position_error_m = estimator.pose.distance_to(sim.pose)
        result.heading_error_deg = wrap_deg(estimator.pose.yaw_deg - sim.pose.yaw_deg)
    goal = map_data.location(route.destination_location_id).pose
    result.distance_to_goal_m = sim.pose.distance_to(goal)
    return result


def _trace_event(
    time_s: float,
    status,
    sim: DifferentialDriveSim,
    estimator: PoseEstimator,
) -> TraceEvent:
    pose = estimator.pose
    est_x = pose.x if pose is not None else float("nan")
    est_y = pose.y if pose is not None else float("nan")
    error = pose.distance_to(sim.pose) if pose is not None else float("nan")
    return TraceEvent(
        time_s=time_s,
        state=status.state.value,
        message=status.message,
        true_x=sim.pose.x,
        true_y=sim.pose.y,
        est_x=est_x,
        est_y=est_y,
        drift_m=status.drift_m,
        error_m=error,
    )
