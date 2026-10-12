"""Platform-neutral navigation core for the OpenBene anchor-navigation demos.

The same model, router, guidance builder, pose estimator and route executor are
implemented in Kotlin (Android demo) and Swift (iOS demo). This package is the
reference implementation: it is what the tests and the simulator run against,
and it defines the behaviour the two apps have to match.
"""

from .model import Edge, Location, MapData, Marker, Pose2D, Room, wrap_deg, wrap_rad
from .router import Route, RouteLeg, Router
from .guidance import GuidanceBuilder, GuidanceStep, StepKind
from .pose import ArObservation, PoseEstimator
from .executor import ExecutorConfig, ExecutorState, ExecutorStatus, RouteExecutor
from .robot_link import OpenBotProtocol, RobotLink, Telemetry, RecordingLink

__all__ = [
    "Edge",
    "Location",
    "MapData",
    "Marker",
    "Pose2D",
    "Room",
    "wrap_deg",
    "wrap_rad",
    "Route",
    "RouteLeg",
    "Router",
    "GuidanceBuilder",
    "GuidanceStep",
    "StepKind",
    "ArObservation",
    "PoseEstimator",
    "ExecutorConfig",
    "ExecutorState",
    "ExecutorStatus",
    "RouteExecutor",
    "OpenBotProtocol",
    "RobotLink",
    "Telemetry",
    "RecordingLink",
]
