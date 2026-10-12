"""Follow mode: keep driving behind a person the camera can see.

This is the OpenBot tracking behaviour the waypoint demo keeps alongside the
route executor: instead of a map, the phone drives towards whatever the camera
reports as a person, keeping the box centred and at a comfortable size.

The controller is deliberately small and stateless: the caller feeds it one
detection per frame (a normalised bounding box) plus the sonar reading, and it
returns one wheel command. Distance comes from the box height, which is crude
but works with the down tilted camera of the robot; tune ``target_height`` on the
bench before letting the robot drive.

``FollowController.kt`` (Kotlin) and ``FollowController.swift`` (Swift) are ports
of this file; keep the three in step.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class FollowConfig:
    """Gains for the follow controller. Box coordinates are fractions of the frame."""

    target_height: float = 0.55
    height_deadband: float = 0.15
    centre_deadband: float = 0.10
    turn_speed: float = 0.22
    cruise_speed: float = 0.28
    steer_gain: float = 1.6
    lost_timeout_s: float = 1.5
    obstacle_stop_cm: float = 35.0


@dataclass(frozen=True)
class FollowCommand:
    left: float
    right: float
    action: str


def follow_command(
    box: Optional[tuple[float, float, float, float]],
    config: FollowConfig = FollowConfig(),
    sonar_cm: Optional[float] = None,
    seconds_since_seen: float = 0.0,
) -> FollowCommand:
    """One wheel command from one detection.

    ``box`` is ``(centre_x, centre_y, width, height)`` in normalised frame
    coordinates, or ``None`` when nothing was detected this frame.
    """

    if sonar_cm is not None and sonar_cm <= config.obstacle_stop_cm:
        return FollowCommand(0.0, 0.0, "obstacle at {:.0f} cm".format(sonar_cm))

    if box is None:
        if seconds_since_seen > config.lost_timeout_s:
            return FollowCommand(0.0, 0.0, "target lost")
        return FollowCommand(0.0, 0.0, "searching for the target")

    centre_x, _centre_y, _width, height = box
    error = centre_x - 0.5

    if abs(error) > config.centre_deadband:
        if error > 0:
            return FollowCommand(-config.turn_speed, config.turn_speed, "turning right")
        return FollowCommand(config.turn_speed, -config.turn_speed, "turning left")

    low = config.target_height * (1.0 - config.height_deadband)
    high = config.target_height * (1.0 + config.height_deadband)
    if height < low:
        forward = config.cruise_speed * min(1.0, (low - height) / max(low, 1e-6) * 3.0 + 0.4)
        action = "closing in"
    elif height > high:
        return FollowCommand(0.0, 0.0, "too close, holding")
    else:
        forward = 0.0
        action = "holding distance"

    steer = max(-1.0, min(1.0, config.steer_gain * error))
    left = forward * (1.0 - steer)
    right = forward * (1.0 + steer)
    scale = max(abs(left), abs(right), 1e-6)
    if scale > 1.0:
        left /= scale
        right /= scale
    return FollowCommand(left, right, action)


def box_from_pixels(
    left_px: float,
    top_px: float,
    right_px: float,
    bottom_px: float,
    frame_width: float,
    frame_height: float,
) -> tuple[float, float, float, float]:
    """Pixel rectangle to the normalised box the controller expects."""

    width = max(0.0, right_px - left_px) / max(frame_width, 1e-6)
    height = max(0.0, bottom_px - top_px) / max(frame_height, 1e-6)
    centre_x = 0.5 * (left_px + right_px) / max(frame_width, 1e-6)
    centre_y = 0.5 * (top_px + bottom_px) / max(frame_height, 1e-6)
    return (centre_x, centre_y, width, height)


def distance_hint_m(height: float, camera_height_m: float = 0.40, fov_deg: float = 60.0, person_m: float = 1.70) -> float:
    """Rough distance to a person of ``person_m`` height, for the UI only."""

    if height <= 1e-3:
        return float("inf")
    focal = 0.5 / math.tan(math.radians(fov_deg) * 0.5)
    return focal * person_m / (height * 2.0 * camera_height_m)
