"""Shared helpers for the navcore tests."""

from __future__ import annotations

import os

from openbene_nav.executor import ExecutorConfig, RouteExecutor
from openbene_nav.model import MapData, Pose2D
from openbene_nav.pose import ArObservation, PoseEstimator
from openbene_nav.robot_link import RecordingLink

MAP_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "maps",
    "demo_floor.json",
)


def load_map() -> MapData:
    return MapData.load(MAP_PATH)


def build_executor(map_data: MapData, config: ExecutorConfig = None):
    estimator = PoseEstimator(map_data)
    link = RecordingLink()
    executor = RouteExecutor(map_data, estimator, link, config or ExecutorConfig())
    return estimator, link, executor


def localize(map_data: MapData, estimator: PoseEstimator, marker_id: str, device_pose: Pose2D = None) -> Pose2D:
    """Align the estimator as if the AR world and the map frame were identical."""

    marker = map_data.marker(marker_id)
    observation = ArObservation(
        marker_id=marker_id,
        marker_in_ar=marker.pose,
        device_in_ar=device_pose or marker.pose,
    )
    return estimator.align(observation)


def drive_to(executor, estimator: PoseEstimator, points, start_time: float = 0.0, dt: float = 0.05):
    """Teleport the estimated pose through a list of points, ticking once per point."""

    status = None
    now = start_time
    for point in points:
        estimator.pose = point
        status = executor.tick(dt, now)
        now += dt
    return status
