from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class KeyboardTeleopConfig:
    linear_speed_mps: float = 0.12
    angular_speed_radps: float = 0.40
    arc_linear_scale: float = 0.60

    def validate(self) -> None:
        if self.linear_speed_mps <= 0.0:
            raise ValueError("linear_speed_mps must be positive.")
        if self.angular_speed_radps <= 0.0:
            raise ValueError("angular_speed_radps must be positive.")
        if not 0.0 < self.arc_linear_scale <= 1.0:
            raise ValueError("arc_linear_scale must stay inside (0, 1].")


@dataclass(frozen=True)
class KeyboardTeleopCommand:
    linear_x: float
    angular_z: float
    label: str


def command_for_key(
    raw_key: str,
    *,
    cfg: KeyboardTeleopConfig,
) -> KeyboardTeleopCommand | None:
    if len(raw_key) != 1:
        return None

    key = raw_key.lower()
    linear = cfg.linear_speed_mps
    angular = cfg.angular_speed_radps
    arc_linear = linear * cfg.arc_linear_scale

    if key == "w":
        return KeyboardTeleopCommand(linear_x=linear, angular_z=0.0, label="forward")
    if key == "s":
        return KeyboardTeleopCommand(linear_x=-linear, angular_z=0.0, label="reverse")
    if key == "a":
        return KeyboardTeleopCommand(linear_x=0.0, angular_z=angular, label="turn_left")
    if key == "d":
        return KeyboardTeleopCommand(linear_x=0.0, angular_z=-angular, label="turn_right")
    if key == "q":
        return KeyboardTeleopCommand(linear_x=arc_linear, angular_z=angular, label="arc_left")
    if key == "e":
        return KeyboardTeleopCommand(linear_x=arc_linear, angular_z=-angular, label="arc_right")
    if key in ("x", " "):
        return KeyboardTeleopCommand(linear_x=0.0, angular_z=0.0, label="stop")
    return None
