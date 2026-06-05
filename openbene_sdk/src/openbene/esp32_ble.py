"""Helpers for talking to OpenBot ESP32 firmware over BLE."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable, Optional

try:
    from bleak import BleakClient
    from bleak import BleakScanner
except ImportError:  # pragma: no cover - exercised indirectly in environments without bleak
    BleakClient = None  # type: ignore[assignment]
    BleakScanner = None  # type: ignore[assignment]


SERVICE_UUID = "61653dc3-4021-4d1e-ba83-8b4eec61d613"
CHAR_RX_UUID = "06386c14-86ea-4d71-811c-48f97c58f8c9"
CHAR_TX_UUID = "9bf1103b-834c-47cf-b149-c9e4bcf778a7"
MAX_PWM = 255


MessageCallback = Callable[[dict[str, object]], None]


def ensure_bleak_available() -> None:
    if BleakClient is None or BleakScanner is None:
        raise RuntimeError(
            "BLE support requires the 'bleak' package. Install it with: python -m pip install bleak"
        )


def clamp_pwm(value: int, *, max_pwm: int = MAX_PWM) -> int:
    if max_pwm <= 0:
        raise ValueError("max_pwm must be positive.")
    return max(-max_pwm, min(max_pwm, int(value)))


def make_ctrl_cmd(left: int, right: int) -> bytes:
    return f"c{clamp_pwm(left)},{clamp_pwm(right)}\n".encode("ascii")


def make_heartbeat_cmd(interval_ms: int) -> bytes:
    if interval_ms <= 0:
        raise ValueError("interval_ms must be positive.")
    return f"h{int(interval_ms)}\n".encode("ascii")


def make_feature_cmd() -> bytes:
    return b"f\n"


def make_sensor_stream_cmd(header: str, interval_ms: int) -> bytes:
    if len(header) != 1:
        raise ValueError("header must be a single ASCII character.")
    if interval_ms <= 0:
        raise ValueError("interval_ms must be positive.")
    return f"{header}{int(interval_ms)}\n".encode("ascii")


def is_openbot_device_name(name: str | None) -> bool:
    if not name:
        return False
    lowered = name.lower()
    return "openbot" in lowered or "rtr_520" in lowered or "rtr 520" in lowered


def parse_esp_message(raw: str) -> dict[str, object]:
    line = raw.strip()
    if not line:
        return {}

    header = line[0]
    body = line[1:]

    if header == "v":
        try:
            return {"type": "voltage", "voltage": float(body), "raw": line}
        except ValueError:
            return {"type": "unknown", "raw": line}

    if header == "w":
        parts = body.split(",")
        if len(parts) >= 2:
            try:
                return {
                    "type": "wheel",
                    "rpm_left": float(parts[0]),
                    "rpm_right": float(parts[1]),
                    "raw": line,
                }
            except ValueError:
                pass
        return {"type": "unknown", "raw": line}

    if header == "s":
        try:
            return {"type": "sonar", "distance_cm": int(body), "raw": line}
        except ValueError:
            return {"type": "unknown", "raw": line}

    if header == "b":
        return {"type": "bumper", "collision_id": body, "raw": line}

    if header == "f":
        split_idx = body.find(":")
        robot_type = body[:split_idx] if split_idx != -1 else body
        capabilities = body[split_idx + 1 :].rstrip(":").split(":") if split_idx != -1 else []
        capabilities = [cap for cap in capabilities if cap]
        return {
            "type": "features",
            "robot_type": robot_type,
            "capabilities": capabilities,
            "raw": line,
        }

    return {"type": "unknown", "raw": line}


async def scan_openbot_devices(timeout: float = 6.0) -> list[Any]:
    ensure_bleak_available()
    devices = await BleakScanner.discover(timeout=timeout)
    return [device for device in devices if is_openbot_device_name(getattr(device, "name", None))]


@dataclass
class OpenBotBleClient:
    address: str
    service_uuid: str = SERVICE_UUID
    rx_uuid: str = CHAR_RX_UUID
    tx_uuid: str = CHAR_TX_UUID

    def __post_init__(self) -> None:
        self._client: Any | None = None
        self._line_buffer = ""
        self.received_lines: list[str] = []
        self._callbacks: list[MessageCallback] = []

    @property
    def connected(self) -> bool:
        return bool(self._client and getattr(self._client, "is_connected", False))

    def add_message_callback(self, callback: MessageCallback) -> None:
        self._callbacks.append(callback)

    async def connect(self) -> None:
        ensure_bleak_available()
        self._client = BleakClient(self.address)
        await self._client.connect()

    async def disconnect(self) -> None:
        if self._client is None:
            return
        try:
            if self.connected:
                await self._client.disconnect()
        finally:
            self._client = None

    async def start_notify(self) -> None:
        self._require_connected()
        await self._client.start_notify(self.tx_uuid, self._handle_notification)

    async def stop_notify(self) -> None:
        if self._client is None or not self.connected:
            return
        await self._client.stop_notify(self.tx_uuid)

    async def write_raw(self, payload: bytes) -> None:
        self._require_connected()
        await self._client.write_gatt_char(self.rx_uuid, payload, response=False)

    async def send_drive(self, left: int, right: int) -> None:
        await self.write_raw(make_ctrl_cmd(left, right))

    async def send_stop(self) -> None:
        await self.send_drive(0, 0)

    async def send_heartbeat(self, interval_ms: int) -> None:
        await self.write_raw(make_heartbeat_cmd(interval_ms))

    async def request_features(self) -> None:
        await self.write_raw(make_feature_cmd())

    async def enable_basic_telemetry(self, interval_ms: int = 500) -> None:
        await self.write_raw(make_sensor_stream_cmd("v", interval_ms))
        await self.write_raw(make_sensor_stream_cmd("w", interval_ms))
        await self.write_raw(make_sensor_stream_cmd("s", interval_ms))

    def _require_connected(self) -> None:
        if self._client is None or not self.connected:
            raise RuntimeError("BLE client is not connected.")

    def _handle_notification(self, _sender: object, data: bytearray) -> None:
        text = bytes(data).decode(errors="replace").replace("\x00", "")
        self._line_buffer += text
        while "\n" in self._line_buffer:
            line, self._line_buffer = self._line_buffer.split("\n", 1)
            line = line.strip()
            if not line:
                continue
            self.received_lines.append(line)
            parsed = parse_esp_message(line)
            for callback in list(self._callbacks):
                callback(parsed)

        if self._line_buffer:
            # BLE notifications from the firmware arrive as complete payloads and do not
            # include trailing newlines, so flush the remaining chunk as one message.
            line = self._line_buffer.strip()
            self._line_buffer = ""
            if not line:
                return
            self.received_lines.append(line)
            parsed = parse_esp_message(line)
            for callback in list(self._callbacks):
                callback(parsed)
