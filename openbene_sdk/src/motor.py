"""
OpenBene Motor Module - 电机控制

提供机器人电机控制功能。

使用方法:
    from openbene.connection import WebSocketConnection
    from openbene.motor import MotorController

    conn = WebSocketConnection("192.168.1.100")
    conn.connect()

    motor = MotorController(conn)
    motor.forward(0.5)
    motor.stop()
"""

import time
import logging
from typing import Optional, List

from .connection import WebSocketConnection

logger = logging.getLogger(__name__)


class MotorController:
    """
    电机控制器

    负责发送电机控制命令到机器人。

    Attributes:
        connection: WebSocket连接实例
    """

    def __init__(self, connection: WebSocketConnection):
        """
        初始化电机控制器

        Args:
            connection: WebSocket连接实例
        """
        self.connection = connection
        self._last_command = ("stop", [0.0, 0.0])

    def _send_command(self, cmd: str, val: Optional[List[float]] = None) -> bool:
        """
        发送控制命令

        Args:
            cmd: 命令名称
            val: 参数值列表
        """
        message = {"cmd": cmd}
        if val is not None:
            message["val"] = val

        self.connection.send(message)
        self._last_command = (cmd, val or [])
        logger.debug(f"命令: {cmd}, 值: {val}")
        return True

    # ==================== 基础控制 ====================

    def drive(self, left: float, right: float) -> bool:
        """
        控制电机速度

        Args:
            left: 左轮速度 (-1.0 到 1.0)
            right: 右轮速度 (-1.0 到 1.0)

        Example:
            motor.drive(0.5, 0.5)  # 前进
            motor.drive(-0.3, 0.3)  # 左转
        """
        if not (-1.0 <= left <= 1.0) or not (-1.0 <= right <= 1.0):
            raise ValueError("速度必须在 -1.0 到 1.0 之间")

        return self._send_command("drive", [left, right])

    def forward(self, speed: float = 0.5) -> bool:
        """前进"""
        return self.drive(speed, speed)

    def backward(self, speed: float = 0.5) -> bool:
        """后退"""
        return self.drive(-speed, -speed)

    def turn_left(self, speed: float = 0.5) -> bool:
        """左转"""
        return self.drive(-speed, speed)

    def turn_right(self, speed: float = 0.5) -> bool:
        """右转"""
        return self.drive(speed, -speed)

    def stop(self) -> bool:
        """停止"""
        return self._send_command("stop")

    # ==================== 带持续时间的控制 ====================

    def move_forward(self, speed: float = 0.5, duration: float = 1.0) -> bool:
        """
        前进指定时间后自动停止

        Args:
            speed: 速度 (0.0 到 1.0)
            duration: 持续时间（秒），默认1秒

        Example:
            motor.move_forward()           # 以0.5速度前进1秒
            motor.move_forward(0.8, 2.0)   # 以0.8速度前进2秒
        """
        self.forward(speed)
        time.sleep(duration)
        self.stop()
        return True

    def move_backward(self, speed: float = 0.5, duration: float = 1.0) -> bool:
        """
        后退指定时间后自动停止

        Args:
            speed: 速度 (0.0 到 1.0)
            duration: 持续时间（秒），默认1秒
        """
        self.backward(speed)
        time.sleep(duration)
        self.stop()
        return True

    def rotate_left(self, speed: float = 0.5, duration: float = 1.0) -> bool:
        """
        左转指定时间后自动停止

        Args:
            speed: 速度 (0.0 到 1.0)
            duration: 持续时间（秒），默认1秒
        """
        self.turn_left(speed)
        time.sleep(duration)
        self.stop()
        return True

    def rotate_right(self, speed: float = 0.5, duration: float = 1.0) -> bool:
        """
        右转指定时间后自动停止

        Args:
            speed: 速度 (0.0 到 1.0)
            duration: 持续时间（秒），默认1秒
        """
        self.turn_right(speed)
        time.sleep(duration)
        self.stop()
        return True

    def move(self, left: float, right: float, duration: float = 1.0) -> bool:
        """
        双轮独立控制，指定时间后自动停止

        Args:
            left: 左轮速度 (-1.0 到 1.0)
            right: 右轮速度 (-1.0 到 1.0)
            duration: 持续时间（秒），默认1秒

        Example:
            motor.move(0.3, 0.5)        # 左轮0.3，右轮0.5，持续1秒
            motor.move(0.5, 0.5, 2.0)   # 前进2秒
        """
        self.drive(left, right)
        time.sleep(duration)
        self.stop()
        return True

    # ==================== 状态 ====================

    @property
    def last_command(self):
        """获取最后发送的命令"""
        return self._last_command

    def __repr__(self):
        return f"MotorController(last_cmd={self._last_command[0]})"
