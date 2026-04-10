"""Small pure helpers for converting ROS velocity commands to wheel commands."""

from __future__ import annotations


def clamp(value: float, lower: float = -1.0, upper: float = 1.0) -> float:
    """Clamp a numeric value into the requested closed interval."""
    return max(lower, min(upper, value))


def twist_to_drive(
    linear_x: float,
    angular_z: float,
    *,
    linear_scale: float = 1.0,
    angular_scale: float = 0.6,
) -> tuple[float, float]:
    """Convert a ROS-style linear/angular command into differential wheel speeds."""
    left = clamp(linear_x * linear_scale - angular_z * angular_scale)
    right = clamp(linear_x * linear_scale + angular_z * angular_scale)
    return left, right
