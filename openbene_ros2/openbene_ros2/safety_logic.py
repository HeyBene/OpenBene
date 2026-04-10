from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Iterable


@dataclass(frozen=True)
class SafetyConfig:
    max_linear_speed_mps: float = 0.15
    max_angular_speed_radps: float = 0.5
    slowdown_distance_m: float = 0.35
    stop_distance_m: float = 0.20
    front_sector_half_angle_deg: float = 30.0

    def validate(self) -> None:
        if self.max_linear_speed_mps <= 0.0:
            raise ValueError("max_linear_speed_mps must be positive.")
        if self.max_angular_speed_radps <= 0.0:
            raise ValueError("max_angular_speed_radps must be positive.")
        if self.stop_distance_m <= 0.0:
            raise ValueError("stop_distance_m must be positive.")
        if self.slowdown_distance_m <= self.stop_distance_m:
            raise ValueError("slowdown_distance_m must be greater than stop_distance_m.")
        if not 0.0 < self.front_sector_half_angle_deg <= 180.0:
            raise ValueError("front_sector_half_angle_deg must stay in (0, 180].")


def clamp_abs(value: float, limit: float) -> float:
    if limit <= 0.0:
        raise ValueError("limit must be positive.")
    return max(-limit, min(limit, value))


def front_min_range(
    ranges: Iterable[float],
    *,
    angle_min: float,
    angle_increment: float,
    front_sector_half_angle_deg: float,
    range_min: float,
    range_max: float,
) -> float | None:
    if angle_increment <= 0.0:
        raise ValueError("angle_increment must be positive.")

    half_angle_rad = math.radians(front_sector_half_angle_deg)
    nearest: float | None = None
    for index, value in enumerate(ranges):
        if not math.isfinite(value):
            continue
        if value < range_min or value > range_max:
            continue
        angle = angle_min + angle_increment * index
        if abs(angle) > half_angle_rad:
            continue
        nearest = value if nearest is None else min(nearest, value)
    return nearest


def apply_linear_safety(
    commanded_linear_mps: float,
    *,
    front_min_distance_m: float | None,
    cfg: SafetyConfig,
) -> float:
    linear = clamp_abs(commanded_linear_mps, cfg.max_linear_speed_mps)
    if linear <= 0.0:
        return linear
    if front_min_distance_m is None:
        return linear
    if front_min_distance_m <= cfg.stop_distance_m:
        return 0.0
    if front_min_distance_m >= cfg.slowdown_distance_m:
        return linear

    usable = front_min_distance_m - cfg.stop_distance_m
    span = cfg.slowdown_distance_m - cfg.stop_distance_m
    scale = max(0.0, min(1.0, usable / span))
    return linear * scale

