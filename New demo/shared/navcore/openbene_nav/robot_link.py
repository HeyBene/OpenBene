"""OpenBot command framing, telemetry parsing and a recording link for tests.

The wire format matches the ESP32 firmware used by OpenBot: single ASCII header
followed by a payload, newline terminated. The same constants are used by the
Android BLE link and the iOS CoreBluetooth link.
"""

from __future__ import annotations

import math
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Protocol

SERVICE_UUID = "61653dc3-4021-4d1e-ba83-8b4eec61d613"
CHAR_RX_UUID = "06386c14-86ea-4d71-811c-48f97c58f8c9"
CHAR_TX_UUID = "9bf1103b-834c-47cf-b149-c9e4bcf778a7"
MAX_PWM = 255


@dataclass
class Telemetry:
    sonar_cm: Optional[float] = None
    bumper: Optional[str] = None
    rpm_left: float = 0.0
    rpm_right: float = 0.0
    voltage: Optional[float] = None
    features: Optional[str] = None
    updated_at_s: float = 0.0

    def obstacle(self, threshold_cm: float) -> bool:
        if self.sonar_cm is None:
            return False
        return self.sonar_cm <= float(threshold_cm)


class RobotLink(Protocol):
    """Minimal robot interface used by the route executor."""

    @property
    def telemetry(self) -> Telemetry:
        ...

    def drive(self, left: float, right: float) -> None:
        ...

    def stop(self) -> None:
        ...


class OpenBotProtocol:
    """Pure functions that turn intentions into OpenBot firmware payloads."""

    @staticmethod
    def clamp_speed(speed: float) -> float:
        return max(-1.0, min(1.0, float(speed)))

    @staticmethod
    def speed_to_pwm(speed: float) -> int:
        return int(round(OpenBotProtocol.clamp_speed(speed) * MAX_PWM))

    @staticmethod
    def ctrl_cmd(left: float, right: float) -> bytes:
        return "c{},{}\n".format(
            OpenBotProtocol.speed_to_pwm(left), OpenBotProtocol.speed_to_pwm(right)
        ).encode("ascii")

    @staticmethod
    def heartbeat_cmd(interval_ms: int) -> bytes:
        return "h{}\n".format(int(interval_ms)).encode("ascii")

    @staticmethod
    def feature_cmd() -> bytes:
        return b"f\n"

    @staticmethod
    def sensor_stream_cmd(header: str, interval_ms: int) -> bytes:
        if len(header) != 1:
            raise ValueError("header must be a single ASCII character")
        return "{}{}\n".format(header, int(interval_ms)).encode("ascii")

    @staticmethod
    def parse_line(line: str) -> Dict[str, object]:
        text = line.strip()
        if not text:
            return {}
        header, body = text[0], text[1:]
        if header == "v":
            try:
                return {"type": "voltage", "voltage": float(body), "raw": text}
            except ValueError:
                return {"type": "unknown", "raw": text}
        if header == "w":
            parts = body.split(",")
            if len(parts) >= 2:
                try:
                    return {
                        "type": "wheel",
                        "rpm_left": float(parts[0]),
                        "rpm_right": float(parts[1]),
                        "raw": text,
                    }
                except ValueError:
                    pass
            return {"type": "unknown", "raw": text}
        if header == "s":
            try:
                return {"type": "sonar", "distance_cm": float(body), "raw": text}
            except ValueError:
                return {"type": "unknown", "raw": text}
        if header == "b":
            return {"type": "bumper", "collision_id": body, "raw": text}
        if header == "f":
            return {"type": "features", "features": body, "raw": text}
        return {"type": "unknown", "raw": text}

    @staticmethod
    def apply_message(telemetry: Telemetry, message: Dict[str, object], now_s: float = 0.0) -> Telemetry:
        kind = message.get("type")
        if kind == "voltage":
            telemetry.voltage = float(message["voltage"])  # type: ignore[arg-type]
        elif kind == "wheel":
            telemetry.rpm_left = float(message["rpm_left"])  # type: ignore[arg-type]
            telemetry.rpm_right = float(message["rpm_right"])  # type: ignore[arg-type]
        elif kind == "sonar":
            telemetry.sonar_cm = float(message["distance_cm"])  # type: ignore[arg-type]
        elif kind == "bumper":
            telemetry.bumper = str(message["collision_id"])
        elif kind == "features":
            telemetry.features = str(message["features"])
        telemetry.updated_at_s = now_s
        return telemetry

    @staticmethod
    def rpm_to_speed(rpm: float, wheel_radius_m: float) -> float:
        return (float(rpm) / 60.0) * 2.0 * math.pi * wheel_radius_m


@dataclass
class RecordingLink:
    """In-memory robot link: records drive commands, holds typed-in telemetry."""

    telemetry: Telemetry = field(default_factory=Telemetry)
    commands: List[Dict[str, object]] = field(default_factory=list)

    def drive(self, left: float, right: float) -> None:
        self.commands.append(
            {
                "type": "drive",
                "left": OpenBotProtocol.clamp_speed(left),
                "right": OpenBotProtocol.clamp_speed(right),
                "at_s": time.time(),
            }
        )

    def stop(self) -> None:
        self.commands.append({"type": "stop", "left": 0.0, "right": 0.0, "at_s": time.time()})

    @property
    def last_command(self) -> Optional[Dict[str, object]]:
        return self.commands[-1] if self.commands else None
