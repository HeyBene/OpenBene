"""OpenBene sensor and telemetry helpers."""

from __future__ import annotations

import logging
import threading
from typing import Any, Dict, Optional

from .connection import WebSocketConnection

logger = logging.getLogger(__name__)


class SensorManager:
    """Store the latest sensor and status values received from the phone app."""

    def __init__(self, connection: WebSocketConnection):
        self.connection = connection

        self._sensor_lock = threading.Lock()
        self._accelerometer: Optional[Dict[str, float]] = None
        self._gyroscope: Optional[Dict[str, float]] = None
        self._magnetometer: Optional[Dict[str, float]] = None
        self._battery_level: Optional[float] = None
        self._voltage: Optional[float] = None
        self._distance: Optional[float] = None

        connection.on_message(self._handle_message)

    def _handle_message(self, message: Dict[str, Any]) -> None:
        if not isinstance(message, dict):
            return

        message_type = message.get("type")
        if message_type not in {"sensor_data", "status"}:
            return

        self._handle_sensor_message(message)

    def _handle_sensor_message(self, message: Dict[str, Any]) -> None:
        try:
            payload = message.get("data")
            if not isinstance(payload, dict):
                payload = message
            if not isinstance(payload, dict):
                return

            with self._sensor_lock:
                self._set_vector("accelerometer", payload)
                self._set_vector("gyroscope", payload)
                self._set_vector("magnetometer", payload)

                battery = self._extract_battery_level(payload)
                if battery is not None:
                    self._battery_level = battery

                if "voltage" in payload:
                    self._voltage = self._coerce_optional_float(payload.get("voltage"))
                if "distance" in payload:
                    self._distance = self._coerce_optional_float(payload.get("distance"))

        except Exception as exc:
            logger.error("Sensor data processing error: %s", exc)

    def _set_vector(self, field: str, payload: Dict[str, Any]) -> None:
        if field not in payload:
            return

        value = payload.get(field)
        if value is None:
            setattr(self, f"_{field}", None)
            return
        if isinstance(value, dict):
            setattr(self, f"_{field}", dict(value))

    def _extract_battery_level(self, payload: Dict[str, Any]) -> Optional[float]:
        if "battery_level" in payload:
            return self._coerce_optional_float(payload.get("battery_level"))
        if "battery" in payload:
            return self._coerce_optional_float(payload.get("battery"))
        return None

    @staticmethod
    def _coerce_optional_float(value: Any) -> Optional[float]:
        if value is None:
            return None
        if isinstance(value, (int, float)):
            return float(value)
        try:
            return float(value)
        except (TypeError, ValueError):
            return None

    def get_all(self) -> Dict[str, Any]:
        with self._sensor_lock:
            return {
                "accelerometer": self._accelerometer.copy() if self._accelerometer else None,
                "gyroscope": self._gyroscope.copy() if self._gyroscope else None,
                "magnetometer": self._magnetometer.copy() if self._magnetometer else None,
                "battery_level": self._battery_level,
                "voltage": self._voltage,
                "distance": self._distance,
            }

    def get_accelerometer(self) -> Optional[Dict[str, float]]:
        with self._sensor_lock:
            return self._accelerometer.copy() if self._accelerometer else None

    def get_gyroscope(self) -> Optional[Dict[str, float]]:
        with self._sensor_lock:
            return self._gyroscope.copy() if self._gyroscope else None

    def get_magnetometer(self) -> Optional[Dict[str, float]]:
        with self._sensor_lock:
            return self._magnetometer.copy() if self._magnetometer else None

    def get_battery_level(self) -> Optional[float]:
        with self._sensor_lock:
            return self._battery_level

    def get_voltage(self) -> Optional[float]:
        with self._sensor_lock:
            return self._voltage

    def get_distance(self) -> Optional[float]:
        with self._sensor_lock:
            return self._distance

    @property
    def has_data(self) -> bool:
        with self._sensor_lock:
            return any(
                value is not None
                for value in (
                    self._accelerometer,
                    self._gyroscope,
                    self._magnetometer,
                    self._battery_level,
                    self._voltage,
                    self._distance,
                )
            )

    def __repr__(self) -> str:
        return f"SensorManager({'has data' if self.has_data else 'no data'})"
