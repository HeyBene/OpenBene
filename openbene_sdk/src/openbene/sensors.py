"""
OpenBene Sensors Module - 传感器数据

提供手机传感器数据访问功能。

使用方法:
    from openbene.connection import WebSocketConnection
    from openbene.sensors import SensorManager

    conn = WebSocketConnection("192.168.1.100")
    conn.connect()

    sensors = SensorManager(conn)
    accel = sensors.get_accelerometer()
    print(f"加速度: {accel}")
"""

import logging
import threading
from typing import Optional, Dict, Any

from .connection import WebSocketConnection

logger = logging.getLogger(__name__)


class SensorManager:
    """
    传感器管理器

    负责接收和处理手机传感器数据。

    Attributes:
        connection: WebSocket连接实例
    """

    def __init__(self, connection: WebSocketConnection):
        """
        初始化传感器管理器

        Args:
            connection: WebSocket连接实例
        """
        self.connection = connection

        # 传感器数据
        self._sensor_lock = threading.Lock()
        self._accelerometer: Optional[Dict[str, float]] = None
        self._gyroscope: Optional[Dict[str, float]] = None
        self._magnetometer: Optional[Dict[str, float]] = None
        self._battery_level: Optional[float] = None

        # 注册消息回调
        connection.on_message(self._handle_message)

    def _handle_message(self, message: Dict[str, Any]) -> None:
        """处理收到的 WebSocket 消息。

        筛选传感器数据类型的消息并转发处理。

        Args:
            message: 解析后的消息字典。
        """
        if message.get('type') == 'sensor_data':
            self._handle_sensor_data(message)

    def _handle_sensor_data(self, message: Dict[str, Any]) -> None:
        """处理传感器数据消息。

        解析并存储各类传感器数据。

        Args:
            message: 包含传感器数据的消息字典。
        """
        try:
            data = message.get('data', {})

            with self._sensor_lock:
                self._accelerometer = data.get('accelerometer')
                self._gyroscope = data.get('gyroscope')
                self._magnetometer = data.get('magnetometer')
                self._battery_level = data.get('battery_level')

        except Exception as e:
            logger.error(f"传感器数据处理错误: {e}")

    def get_all(self) -> Dict[str, Any]:
        """
        获取所有传感器数据

        Returns:
            dict: {
                'accelerometer': {'x': float, 'y': float, 'z': float},
                'gyroscope': {'x': float, 'y': float, 'z': float},
                'magnetometer': {'x': float, 'y': float, 'z': float},
                'battery_level': float
            }
        """
        with self._sensor_lock:
            return {
                'accelerometer': self._accelerometer,
                'gyroscope': self._gyroscope,
                'magnetometer': self._magnetometer,
                'battery_level': self._battery_level,
            }

    def get_accelerometer(self) -> Optional[Dict[str, float]]:
        """
        获取加速度计数据 (m/s²)

        Returns:
            dict: {'x': float, 'y': float, 'z': float} 或 None
        """
        with self._sensor_lock:
            return self._accelerometer.copy() if self._accelerometer else None

    def get_gyroscope(self) -> Optional[Dict[str, float]]:
        """
        获取陀螺仪数据 (rad/s)

        Returns:
            dict: {'x': float, 'y': float, 'z': float} 或 None
        """
        with self._sensor_lock:
            return self._gyroscope.copy() if self._gyroscope else None

    def get_magnetometer(self) -> Optional[Dict[str, float]]:
        """
        获取磁力计数据 (µT)

        Returns:
            dict: {'x': float, 'y': float, 'z': float} 或 None
        """
        with self._sensor_lock:
            return self._magnetometer.copy() if self._magnetometer else None

    def get_battery_level(self) -> Optional[float]:
        """
        获取电池电量 (0-100)

        Returns:
            float: 电池百分比 或 None
        """
        with self._sensor_lock:
            return self._battery_level

    @property
    def has_data(self) -> bool:
        """检查是否有可用的传感器数据。

        Returns:
            如果有加速度计或陀螺仪数据返回 True，否则返回 False。
        """
        with self._sensor_lock:
            return self._accelerometer is not None or self._gyroscope is not None

    def __repr__(self) -> str:
        """返回对象的字符串表示。

        Returns:
            格式化的字符串，包含数据状态信息。
        """
        has_data = "有数据" if self.has_data else "无数据"
        return f"SensorManager({has_data})"
