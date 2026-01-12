"""
OpenBene SDK - Python SDK for controlling OpenBene robots.

通过WebSocket连接到手机App，控制机器人。

使用方法:
    import openbene

    # 方式1: 使用工厂函数（推荐）
    bot = openbene.openbot_rtr_tt("my_robot")
    bot.move_forward()
    bot.disconnect()

    # 方式2: 手动创建
    from openbene import OpenBene
    bot = OpenBene("192.168.1.100")
    bot.connect()
    bot.forward(0.5)
    bot.stop()
    bot.disconnect()
"""

from .openbene import (
    OpenBene,
    ConnectionError,
    RobotType,
    openbot_rtr_tt,
    openbot_rtr_520,
)

__version__ = '2.1.0'
__all__ = [
    'OpenBene',
    'ConnectionError',
    'RobotType',
    'openbot_rtr_tt',
    'openbot_rtr_520',
]
