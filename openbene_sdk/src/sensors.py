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
import numpy as np

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
        self._lidar_depth: Optional[Dict[str, Any]] = None

        # 注册消息回调
        connection.on_message(self._handle_message)

    def _handle_message(self, message: Dict[str, Any]):
        """处理收到的消息"""
        if message.get('type') == 'sensor_data':
            self._handle_sensor_data(message)

    def _handle_sensor_data(self, message: Dict[str, Any]):
        """处理传感器数据"""
        try:
            data = message.get('data', {})

            with self._sensor_lock:
                self._accelerometer = data.get('accelerometer')
                self._gyroscope = data.get('gyroscope')
                self._magnetometer = data.get('magnetometer')
                self._battery_level = data.get('battery_level')
                self._lidar_depth = data.get('lidar')

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
                'battery_level': float,
                'lidar': {'depth_map': List[float], 'width': int, 'height': int, ...}
            }
        """
        with self._sensor_lock:
            return {
                'accelerometer': self._accelerometer,
                'gyroscope': self._gyroscope,
                'magnetometer': self._magnetometer,
                'battery_level': self._battery_level,
                'lidar': self._lidar_depth,
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

    def get_lidar_depth(self) -> Optional[Dict[str, Any]]:
        """
        Get LiDAR depth map data
        
        Returns:
            dict: {
                'depth_map': List[float],  # Flattened depth values
                'width': int,
                'height': int,
                'min_depth': float,  # meters
                'max_depth': float,  # meters
                'timestamp': str
            } or None
        """
        with self._sensor_lock:
            # Return defensive copy to prevent external modification
            # Note: The depth_map list itself is not deep-copied for performance
            return self._lidar_depth.copy() if self._lidar_depth else None
    
    def get_depth_image(self) -> Optional[np.ndarray]:
        """
        Get LiDAR depth as numpy array for visualization
        
        Returns:
            np.ndarray: 2D array of depth values (height x width)
        """
        lidar = self.get_lidar_depth()
        if not lidar:
            return None
        
        depth_map = np.array(lidar['depth_map'])
        return depth_map.reshape(lidar['height'], lidar['width'])

    @property
    def has_data(self) -> bool:
        """是否有传感器数据"""
        with self._sensor_lock:
            return self._accelerometer is not None or self._gyroscope is not None

    def __repr__(self):
        has_data = "有数据" if self.has_data else "无数据"
        return f"SensorManager({has_data})"
