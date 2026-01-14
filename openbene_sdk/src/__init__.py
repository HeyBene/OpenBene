"""
OpenBene SDK - Python SDK for controlling OpenBene robots.

通过WebSocket连接到手机App，控制机器人。

使用方法:
    # 方式1: 使用主类（推荐）
    from openbene import OpenBene

    with OpenBene("192.168.1.100") as bot:
        bot.forward(0.5)
        bot.stop()

    # 方式2: 使用工厂函数
    import openbene

    bot = openbene.openbot_rtr_tt("my_robot")
    bot.move_forward()
    bot.disconnect()

    # 方式3: 直接使用各模块
    from openbene.connection import WebSocketConnection
    from openbene.motor import MotorController

    conn = WebSocketConnection("192.168.1.100")
    conn.connect()
    motor = MotorController(conn)
    motor.forward(0.5)
    motor.stop()
"""

# 主类和工厂函数
from .openbene import (
    OpenBene,
    RobotType,
    openbot_rtr_tt,
    openbot_rtr_520,
)

# 连接模块
from .connection import (
    WebSocketConnection,
    ConnectionError,
)

# 电机模块
from .motor import MotorController

# 视频模块
from .video import VideoReceiver

# 传感器模块
from .sensors import SensorManager

# 数据采集模块
from .recording import DataRecorder

# 设备发现模块
from .discovery import Discovery

__version__ = '2.2.0'  # 模块化版本

__all__ = [
    # 主类
    'OpenBene',
    'RobotType',
    'openbot_rtr_tt',
    'openbot_rtr_520',
    # 连接
    'WebSocketConnection',
    'ConnectionError',
    # 各模块
    'MotorController',
    'VideoReceiver',
    'SensorManager',
    'DataRecorder',
    'Discovery',
]
