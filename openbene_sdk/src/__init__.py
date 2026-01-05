"""
OpenBene SDK - Python SDK for controlling OpenBene robots.

通过WebSocket连接到手机App，控制机器人。

使用方法:
    from openbene import OpenBene

    bot = OpenBene("192.168.1.100")
    bot.connect()
    bot.forward(0.5)
    bot.stop()
    bot.disconnect()
"""

from .openbene import OpenBene, ConnectionError

__version__ = '2.0.0'
__all__ = ['OpenBene', 'ConnectionError']
