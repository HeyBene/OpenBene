"""
OpenBene Connection Module - WebSocket连接管理

提供与手机App的WebSocket连接功能。

使用方法:
    from openbene.connection import WebSocketConnection

    conn = WebSocketConnection("192.168.1.100")
    conn.connect()
    conn.send({"cmd": "drive", "val": [0.5, 0.5]})
    conn.disconnect()
"""

import json
import logging
import time
import threading
import asyncio
from typing import Optional, Callable, Dict, Any, List

# Try importing WebSocket support
try:
    import websockets
    WEBSOCKET_SUPPORT = True
except ImportError:
    WEBSOCKET_SUPPORT = False
    websockets = None

# Configure logging
logger = logging.getLogger(__name__)


class ConnectionError(Exception):
    """连接失败异常。

    当 WebSocket 连接失败、超时或被拒绝时抛出。
    """
    pass


class WebSocketConnection:
    """
    WebSocket连接管理器

    负责与手机App建立和维护WebSocket连接。

    Attributes:
        ip: 手机IP地址
        port: WebSocket端口
        connected: 是否已连接
    """

    DEFAULT_PORT = 8765
    TIMEOUT = 5.0

    def __init__(self, ip: str, port: int = DEFAULT_PORT):
        """
        初始化连接器

        Args:
            ip: 手机IP地址
            port: WebSocket端口，默认8765
        """
        if not WEBSOCKET_SUPPORT:
            raise ImportError("需要安装websockets库: pip install websockets")

        self.ip = ip
        self.port = port
        self.connected = False

        # WebSocket相关
        self._ws = None
        self._ws_loop: Optional[asyncio.AbstractEventLoop] = None
        self._ws_thread: Optional[threading.Thread] = None
        self._ws_running = False
        self._send_queue: Optional[asyncio.Queue] = None

        # 消息回调
        self._message_callbacks: List[Callable[[Dict[str, Any]], None]] = []

    def connect(self, timeout: float = TIMEOUT) -> bool:
        """
        连接到手机

        Args:
            timeout: 连接超时时间（秒）

        Returns:
            True if 连接成功

        Raises:
            ConnectionError: 连接失败
        """
        logger.info(f"正在连接到 {self.ip}:{self.port}...")

        self._ws_running = True
        self._ws_thread = threading.Thread(target=self._run_ws_loop, daemon=True)
        self._ws_thread.start()

        # 等待连接
        start_time = time.time()
        while not self.connected:
            if time.time() - start_time > timeout:
                self._ws_running = False
                raise ConnectionError(f"连接超时: {self.ip}:{self.port}")
            time.sleep(0.1)

        logger.info(f"已连接到 {self.ip}:{self.port}")
        return True

    def disconnect(self) -> None:
        """断开与手机的 WebSocket 连接。

        停止事件循环线程并清理所有资源。
        """
        self._ws_running = False

        if self._ws_thread and self._ws_thread.is_alive():
            self._ws_thread.join(timeout=2.0)

        self.connected = False
        self._ws = None
        logger.info(f"已断开连接: {self.ip}")

    def send(self, message: dict) -> bool:
        """
        发送消息到手机

        Args:
            message: 要发送的消息字典

        Returns:
            True if 发送成功
        """
        if not self.connected:
            raise ConnectionError("未连接，请先调用 connect()")

        self._queue_message(message)
        logger.debug(f"发送: {message}")
        return True

    def on_message(self, callback: Callable[[Dict[str, Any]], None]) -> None:
        """注册消息回调函数。

        当收到手机发送的消息时，会调用所有注册的回调函数。

        Args:
            callback: 回调函数，接收消息字典作为参数。
        """
        self._message_callbacks.append(callback)

    def remove_callback(self, callback: Callable[[Dict[str, Any]], None]) -> None:
        """移除已注册的消息回调函数。

        Args:
            callback: 要移除的回调函数。
        """
        if callback in self._message_callbacks:
            self._message_callbacks.remove(callback)

    def _run_ws_loop(self) -> None:
        """运行 WebSocket 事件循环。

        在独立的守护线程中运行异步事件循环，处理 WebSocket 连接。
        当连接断开或发生错误时，会自动清理资源。
        """
        try:
            self._ws_loop = asyncio.new_event_loop()
            asyncio.set_event_loop(self._ws_loop)
            self._send_queue = asyncio.Queue()
            self._ws_loop.run_until_complete(self._ws_handler())
        except Exception as e:
            logger.error(f"WebSocket循环错误: {e}")
        finally:
            self.connected = False
            if self._ws_loop:
                self._ws_loop.close()

    async def _ws_handler(self) -> None:
        """处理 WebSocket 连接的主协程。

        建立连接后，并行运行发送和接收任务。
        当任一任务完成时（通常是因为断开连接），会取消另一个任务。

        Raises:
            ConnectionError: 当连接失败时抛出。
        """
        uri = f"ws://{self.ip}:{self.port}"
        try:
            async with websockets.connect(uri) as ws:
                self._ws = ws
                self.connected = True
                logger.debug(f"WebSocket已连接: {uri}")

                # 创建发送和接收任务
                send_task = asyncio.create_task(self._ws_sender())
                recv_task = asyncio.create_task(self._ws_receiver())

                done, pending = await asyncio.wait(
                    [send_task, recv_task],
                    return_when=asyncio.FIRST_COMPLETED
                )

                for task in pending:
                    task.cancel()

        except Exception as e:
            logger.error(f"WebSocket连接错误: {e}")
            raise ConnectionError(f"连接失败: {e}")
        finally:
            self.connected = False
            self._ws = None

    async def _ws_sender(self) -> None:
        """发送消息的异步任务。

        从发送队列中获取消息并通过 WebSocket 发送到手机。
        支持超时机制，避免阻塞。
        """
        while self._ws_running and self._ws:
            try:
                msg = await asyncio.wait_for(self._send_queue.get(), timeout=0.1)
                await self._ws.send(json.dumps(msg))
                logger.debug(f"发送: {msg}")
            except asyncio.TimeoutError:
                continue
            except Exception as e:
                logger.error(f"发送错误: {e}")
                break

    async def _ws_receiver(self) -> None:
        """接收消息的异步任务。

        持续接收手机发送的 WebSocket 消息，解析 JSON 并分发到回调函数。
        """
        while self._ws_running and self._ws:
            try:
                message = await self._ws.recv()
                data = json.loads(message)
                self._dispatch_message(data)
            except json.JSONDecodeError as e:
                logger.warning(f"JSON解析错误: {e}")
            except Exception as e:
                logger.error(f"接收错误: {e}")
                break

    def _dispatch_message(self, message: Dict[str, Any]) -> None:
        """分发收到的消息到所有回调函数。

        自动处理心跳消息，其他消息分发到已注册的回调函数。

        Args:
            message: 解析后的消息字典。
        """
        msg_type = message.get('type')

        # 处理心跳
        if msg_type == 'heartbeat':
            self._queue_message({'type': 'pong', 'timestamp': int(time.time() * 1000)})
            return

        # 调用所有注册的回调
        for callback in self._message_callbacks:
            try:
                callback(message)
            except Exception as e:
                logger.error(f"消息回调错误: {e}")

    def _queue_message(self, message: dict) -> None:
        """将消息添加到发送队列。

        线程安全地将消息放入异步队列，由发送任务处理。

        Args:
            message: 要发送的消息字典。
        """
        if self._ws_loop and self._send_queue:
            asyncio.run_coroutine_threadsafe(
                self._send_queue.put(message),
                self._ws_loop
            )

    @property
    def is_connected(self) -> bool:
        """检查是否已连接到手机。

        Returns:
            如果已连接返回 True，否则返回 False。
        """
        return self.connected

    def __repr__(self) -> str:
        """返回对象的字符串表示。

        Returns:
            格式化的字符串，包含 IP、端口和连接状态。
        """
        status = "已连接" if self.connected else "未连接"
        return f"WebSocketConnection({self.ip}:{self.port}, {status})"

    def __enter__(self) -> 'WebSocketConnection':
        """进入上下文管理器，自动连接。

        Returns:
            已连接的 WebSocketConnection 实例。
        """
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        """退出上下文管理器，自动断开连接。"""
        self.disconnect()
