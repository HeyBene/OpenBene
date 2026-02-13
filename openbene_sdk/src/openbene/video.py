"""
OpenBene Video Module - 视频接收

提供视频帧接收和显示功能。

使用方法:
    from openbene.connection import WebSocketConnection
    from openbene.video import VideoReceiver

    conn = WebSocketConnection("192.168.1.100")
    conn.connect()

    video = VideoReceiver(conn)
    for frame in video.stream():
        cv2.imshow("Camera", frame)
        if cv2.waitKey(1) == ord('q'):
            break
"""

import base64
import logging
import threading
import time
from typing import Optional, Callable, Any, Dict, Generator

# Try importing OpenCV for video support
try:
    import cv2
    import numpy as np
    VIDEO_SUPPORT = True
except ImportError:
    VIDEO_SUPPORT = False
    cv2 = None
    np = None

from .connection import WebSocketConnection

logger = logging.getLogger(__name__)


class VideoReceiver:
    """
    视频帧接收器

    负责接收和处理从手机App发来的视频帧。

    Attributes:
        connection: WebSocket连接实例
    """

    def __init__(self, connection: WebSocketConnection):
        """
        初始化视频接收器

        Args:
            connection: WebSocket连接实例
        """
        self.connection = connection

        # 视频帧
        self._frame_lock = threading.Lock()
        self._latest_frame: Optional[bytes] = None
        self._frame_callback: Optional[Callable[[bytes], None]] = None

        # OpenCV窗口
        self._display_active = False
        self._display_thread: Optional[threading.Thread] = None

        # 注册消息回调
        connection.on_message(self._handle_message)

    def _handle_message(self, message: Dict[str, Any]) -> None:
        """处理收到的 WebSocket 消息。

        筛选视频帧类型的消息并转发处理。

        Args:
            message: 解析后的消息字典。
        """
        if message.get('type') == 'video_frame':
            self._handle_video_frame(message)

    def _handle_video_frame(self, message: Dict[str, Any]) -> None:
        """处理视频帧消息。

        解码 Base64 编码的 JPEG 数据并存储，调用用户回调。

        Args:
            message: 包含视频帧数据的消息字典。
        """
        try:
            base64_data = message.get('data', '')
            jpeg_bytes = base64.b64decode(base64_data)

            with self._frame_lock:
                self._latest_frame = jpeg_bytes

            # 用户回调
            if self._frame_callback:
                self._frame_callback(jpeg_bytes)

        except Exception as e:
            logger.error(f"视频帧处理错误: {e}")

    def get_frame(self) -> Optional[Any]:
        """
        获取最新视频帧

        Returns:
            numpy数组 (BGR格式)，如果没有帧则返回None

        Example:
            frame = video.get_frame()
            if frame is not None:
                cv2.imshow("Camera", frame)
        """
        if not VIDEO_SUPPORT:
            logger.warning("需要安装OpenCV: pip install opencv-python")
            return None

        with self._frame_lock:
            if self._latest_frame is None:
                return None

            # 解码JPEG
            nparr = np.frombuffer(self._latest_frame, np.uint8)
            frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            return frame

    def get_frame_bytes(self) -> Optional[bytes]:
        """
        获取最新视频帧的原始JPEG字节

        Returns:
            JPEG字节数据，如果没有帧则返回None
        """
        with self._frame_lock:
            return self._latest_frame

    def start_display(self, window_name: str = "OpenBene Camera") -> None:
        """开始 OpenCV 视频显示窗口。

        在独立线程中运行视频显示循环，按 'q' 键可关闭窗口。

        Args:
            window_name: OpenCV 窗口名称，默认 "OpenBene Camera"。
        """
        if not VIDEO_SUPPORT:
            logger.warning("需要安装OpenCV: pip install opencv-python")
            return

        self._display_active = True
        self._display_thread = threading.Thread(
            target=self._display_loop,
            args=(window_name,),
            daemon=True
        )
        self._display_thread.start()

    def stop_display(self) -> None:
        """停止视频显示窗口并清理资源。"""
        self._display_active = False
        self._frame_callback = None
        if VIDEO_SUPPORT:
            cv2.destroyAllWindows()

    def _display_loop(self, window_name: str) -> None:
        """OpenCV 视频显示循环。

        持续获取帧并显示，直到连接断开或用户按 'q' 键。

        Args:
            window_name: OpenCV 窗口名称。
        """
        while self._display_active and self.connection.connected:
            frame = self.get_frame()
            if frame is not None:
                cv2.imshow(window_name, frame)

            key = cv2.waitKey(30) & 0xFF
            if key == ord('q'):
                self._display_active = False
                break

        cv2.destroyAllWindows()

    def stream(self) -> Generator[Any, None, None]:
        """
        返回视频帧生成器

        Yields:
            numpy数组 (BGR格式) 每帧视频

        Example:
            for frame in video.stream():
                cv2.imshow("Video", frame)
                if cv2.waitKey(1) == ord('q'):
                    break
        """
        if not VIDEO_SUPPORT:
            raise ImportError("需要安装OpenCV: pip install opencv-python")

        try:
            while self.connection.connected:
                frame = self.get_frame()
                if frame is not None:
                    yield frame
                time.sleep(0.033)  # ~30fps
        finally:
            pass

    def set_callback(self, callback: Optional[Callable[[bytes], None]]) -> None:
        """设置帧回调函数。

        每当收到新的视频帧时，会调用此回调函数。

        Args:
            callback: 回调函数，接收 JPEG 字节数据作为参数。
                     传入 None 可清除回调。
        """
        self._frame_callback = callback

    @property
    def has_frame(self) -> bool:
        """检查是否有可用的视频帧。

        Returns:
            如果有可用帧返回 True，否则返回 False。
        """
        with self._frame_lock:
            return self._latest_frame is not None

    def __repr__(self) -> str:
        """返回对象的字符串表示。

        Returns:
            格式化的字符串，包含帧状态信息。
        """
        has_frame = "有帧" if self.has_frame else "无帧"
        return f"VideoReceiver({has_frame})"
