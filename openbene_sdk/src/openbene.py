"""
OpenBene SDK - PC端Python控制库

通过WebSocket连接到手机App，实现：
- 发送控制命令（drive, stop等）
- 接收视频流（JPEG帧）
- 接收传感器数据
- 数据采集模式

架构：手机是WebSocket Server，PC是Client

使用方法:
    # 方式1: 使用上下文管理器（推荐）
    from openbene import OpenBene

    with OpenBene("192.168.1.100") as bot:
        bot.forward(0.5)
        bot.stop()

    # 方式2: 手动连接
    bot = OpenBene("192.168.1.100")
    bot.connect()
    bot.forward(0.5)
    bot.stop()
    bot.disconnect()

    # 方式3: 直接访问模块
    bot.motor.drive(0.3, 0.5)
    bot.video.get_frame()
    bot.sensors.get_accelerometer()
"""

import socket
import json
import time
import logging
from typing import Optional, Dict, Any

# 导入各模块
from .connection import WebSocketConnection, ConnectionError
from .motor import MotorController
from .video import VideoReceiver
from .sensors import SensorManager
from .recording import DataRecorder

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class RobotType:
    """机器人硬件类型"""
    RTR_TT = "RTR_TT"      # Arduino Nano, TT电机
    RTR_520 = "RTR_520"    # ESP32, 520电机


class OpenBene:
    """
    OpenBene机器人控制器

    整合所有模块的主类，提供统一的API接口。

    使用方法：
        # 方式1: 手动指定IP
        bot = OpenBene("192.168.1.100")
        bot.connect()

        # 方式2: 自动发现（推荐）
        bot = OpenBene.auto_connect()

        bot.forward(0.5)
        time.sleep(2)
        bot.stop()

        bot.disconnect()

    属性:
        motor: 电机控制器
        video: 视频接收器
        sensors: 传感器管理器
        recorder: 数据采集器
    """

    DEFAULT_PORT = 8765
    DISCOVERY_PORT = 12345
    TIMEOUT = 5.0

    @staticmethod
    def discover(timeout: float = 5.0) -> Optional[Dict[str, Any]]:
        """
        自动发现网络中的OpenBene机器人

        通过监听UDP广播消息来发现手机App

        Args:
            timeout: 发现超时时间（秒）

        Returns:
            发现的机器人信息字典，包含 'name', 'ip', 'port'
            如果未发现则返回 None
        """
        logger.info(f"正在搜索OpenBene机器人... (超时: {timeout}秒)")

        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(('', OpenBene.DISCOVERY_PORT))
            sock.settimeout(1.0)  # 每次接收超时1秒

            start_time = time.time()

            try:
                # 持续监听直到超时或收到有效消息
                while time.time() - start_time < timeout:
                    try:
                        data, addr = sock.recvfrom(1024)
                        message = json.loads(data.decode('utf-8'))

                        if message.get('type') == 'discovery':
                            robot_info = {
                                'name': message.get('name', 'Unknown'),
                                'ip': message.get('ip', addr[0]),
                                'port': message.get('port', OpenBene.DEFAULT_PORT),
                            }
                            logger.info(f"发现机器人: {robot_info['name']} @ {robot_info['ip']}:{robot_info['port']}")
                            return robot_info

                    except socket.timeout:
                        # 1秒内没收到，继续等待
                        continue
                    except json.JSONDecodeError:
                        # 忽略无效的JSON
                        continue

                # 超时仍未找到
                logger.warning("发现超时，未找到机器人")
                return None

            finally:
                sock.close()

        except Exception as e:
            logger.error(f"发现服务错误: {e}")
            return None

    @classmethod
    def auto_connect(cls, timeout: float = 10.0, retries: int = 3) -> 'OpenBene':
        """
        自动发现并连接到机器人

        Args:
            timeout: 发现和连接的总超时时间（秒）
            retries: 发现失败时的重试次数

        Returns:
            已连接的 OpenBene 实例

        Raises:
            ConnectionError: 未找到机器人或连接失败
        """
        discover_timeout = timeout / 2 / retries
        robot = None

        for attempt in range(retries):
            logger.info(f"发现尝试 {attempt + 1}/{retries}...")
            robot = cls.discover(timeout=discover_timeout)
            if robot is not None:
                break
            if attempt < retries - 1:
                time.sleep(0.5)

        if robot is None:
            raise ConnectionError("未发现OpenBene机器人，请确保手机App已启动并连接到同一网络")

        bot = cls(robot['ip'], robot['port'])
        bot.connect(timeout=timeout / 2)
        return bot

    def __init__(self, ip: str, port: int = DEFAULT_PORT):
        """
        初始化控制器

        Args:
            ip: 手机IP地址
            port: WebSocket端口，默认8765
        """
        self.ip = ip
        self.port = port
        self.name = "OpenBot"  # 机器人名称
        self.robot_type = None  # 硬件类型

        # 创建连接
        self._conn = WebSocketConnection(ip, port)

        # 创建各模块（延迟初始化，连接后才能使用）
        self._motor: Optional[MotorController] = None
        self._video: Optional[VideoReceiver] = None
        self._sensors: Optional[SensorManager] = None
        self._recorder: Optional[DataRecorder] = None

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
        result = self._conn.connect(timeout)

        # 初始化各模块
        self._motor = MotorController(self._conn)
        self._video = VideoReceiver(self._conn)
        self._sensors = SensorManager(self._conn)
        self._recorder = DataRecorder(self._video, self._sensors)

        return result

    def disconnect(self):
        """断开连接"""
        if self._recorder and self._recorder.is_recording:
            self._recorder.stop()

        if self._video:
            self._video.stop_display()

        self._conn.disconnect()

    @property
    def connected(self) -> bool:
        """是否已连接"""
        return self._conn.connected

    # ==================== 模块访问 ====================

    @property
    def motor(self) -> MotorController:
        """电机控制器"""
        if self._motor is None:
            raise ConnectionError("未连接，请先调用 connect()")
        return self._motor

    @property
    def video(self) -> VideoReceiver:
        """视频接收器"""
        if self._video is None:
            raise ConnectionError("未连接，请先调用 connect()")
        return self._video

    @property
    def sensors(self) -> SensorManager:
        """传感器管理器"""
        if self._sensors is None:
            raise ConnectionError("未连接，请先调用 connect()")
        return self._sensors

    @property
    def recorder(self) -> DataRecorder:
        """数据采集器"""
        if self._recorder is None:
            raise ConnectionError("未连接，请先调用 connect()")
        return self._recorder

    # ==================== 电机控制（代理到motor模块）====================

    def drive(self, left: float, right: float) -> bool:
        """控制电机速度"""
        return self.motor.drive(left, right)

    def forward(self, speed: float = 0.5) -> bool:
        """前进"""
        return self.motor.forward(speed)

    def backward(self, speed: float = 0.5) -> bool:
        """后退"""
        return self.motor.backward(speed)

    def turn_left(self, speed: float = 0.5) -> bool:
        """左转"""
        return self.motor.turn_left(speed)

    def turn_right(self, speed: float = 0.5) -> bool:
        """右转"""
        return self.motor.turn_right(speed)

    def stop(self) -> bool:
        """停止"""
        return self.motor.stop()

    # ==================== 带持续时间的控制 ====================

    def move_forward(self, speed: float = 0.5, duration: float = 1.0) -> bool:
        """前进指定时间后自动停止"""
        return self.motor.move_forward(speed, duration)

    def move_backward(self, speed: float = 0.5, duration: float = 1.0) -> bool:
        """后退指定时间后自动停止"""
        return self.motor.move_backward(speed, duration)

    def rotate_left(self, speed: float = 0.5, duration: float = 1.0) -> bool:
        """左转指定时间后自动停止"""
        return self.motor.rotate_left(speed, duration)

    def rotate_right(self, speed: float = 0.5, duration: float = 1.0) -> bool:
        """右转指定时间后自动停止"""
        return self.motor.rotate_right(speed, duration)

    def move(self, left: float, right: float, duration: float = 1.0) -> bool:
        """双轮独立控制，指定时间后自动停止"""
        return self.motor.move(left, right, duration)

    # ==================== 视频（代理到video模块）====================

    def get_frame(self):
        """获取最新视频帧"""
        return self.video.get_frame()

    def start_video(self, display: bool = True, callback=None):
        """开始接收视频"""
        if callback:
            self.video.set_callback(callback)
        if display:
            self.video.start_display()

    def stop_video(self):
        """停止视频显示"""
        self.video.stop_display()

    def video_stream(self):
        """返回视频帧生成器"""
        return self.video.stream()

    # ==================== 传感器（代理到sensors模块）====================

    def get_sensors(self) -> Dict[str, Any]:
        """获取所有传感器数据"""
        return self.sensors.get_all()

    def get_accelerometer(self):
        """获取加速度计数据"""
        return self.sensors.get_accelerometer()

    def get_gyroscope(self):
        """获取陀螺仪数据"""
        return self.sensors.get_gyroscope()

    # ==================== 数据采集（代理到recorder模块）====================

    def start_recording(self, output_dir: str = "./dataset"):
        """开始数据采集"""
        self.recorder.start(output_dir)

    def stop_recording(self):
        """停止数据采集"""
        self.recorder.stop()

    # ==================== 上下文管理器 ====================

    def __enter__(self):
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.disconnect()

    def __repr__(self):
        status = "已连接" if self.connected else "未连接"
        return f"OpenBene({self.ip}:{self.port}, {status})"


# ==================== 工厂函数 ====================

def openbot_rtr_tt(name: str = "OpenBot", ip: str = None, port: int = 8765) -> OpenBene:
    """
    创建并连接到RTR_TT版本的OpenBot

    RTR_TT: Arduino Nano, TT电机

    Args:
        name: 机器人名称
        ip: 手机IP地址，如果为None则自动发现
        port: WebSocket端口，默认8765

    Returns:
        已连接的 OpenBene 实例

    Example:
        # 自动发现连接
        bot = openbot_rtr_tt("my_robot")

        # 指定IP连接
        bot = openbot_rtr_tt("my_robot", ip="192.168.123.125")

        bot.move_forward()
        bot.disconnect()
    """
    if ip is None:
        bot = OpenBene.auto_connect()
    else:
        bot = OpenBene(ip, port)
        bot.connect()

    bot.name = name
    bot.robot_type = RobotType.RTR_TT
    return bot


def openbot_rtr_520(name: str = "OpenBot", ip: str = None, port: int = 8765) -> OpenBene:
    """
    创建并连接到RTR_520版本的OpenBot

    RTR_520: ESP32, 520电机

    Args:
        name: 机器人名称
        ip: 手机IP地址，如果为None则自动发现
        port: WebSocket端口，默认8765

    Returns:
        已连接的 OpenBene 实例

    Example:
        # 自动发现连接
        bot = openbot_rtr_520("my_robot")

        # 指定IP连接
        bot = openbot_rtr_520("my_robot", ip="192.168.123.125")

        bot.move_forward()
        bot.disconnect()
    """
    if ip is None:
        bot = OpenBene.auto_connect()
    else:
        bot = OpenBene(ip, port)
        bot.connect()

    bot.name = name
    bot.robot_type = RobotType.RTR_520
    return bot
