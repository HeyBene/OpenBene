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
from typing import Optional, Dict, Any, Callable, Generator
import numpy as np

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

    def disconnect(self) -> None:
        """断开与手机的连接。

        清理所有资源，包括停止录制和视频显示。

        Returns:
            None
        """
        if self._recorder and self._recorder.is_recording:
            self._recorder.stop()

        if self._video:
            self._video.stop_display()

        self._conn.disconnect()

    @property
    def connected(self) -> bool:
        """检查是否已连接到手机。

        Returns:
            如果已连接返回 True，否则返回 False。
        """
        return self._conn.connected

    # ==================== 模块访问 ====================

    @property
    def motor(self) -> MotorController:
        """获取电机控制器模块。

        Returns:
            MotorController 实例，用于控制机器人电机。

        Raises:
            ConnectionError: 如果尚未连接到手机。
        """
        if self._motor is None:
            raise ConnectionError("未连接，请先调用 connect()")
        return self._motor

    @property
    def video(self) -> VideoReceiver:
        """获取视频接收器模块。

        Returns:
            VideoReceiver 实例，用于接收和处理视频帧。

        Raises:
            ConnectionError: 如果尚未连接到手机。
        """
        if self._video is None:
            raise ConnectionError("未连接，请先调用 connect()")
        return self._video

    @property
    def sensors(self) -> SensorManager:
        """获取传感器管理器模块。

        Returns:
            SensorManager 实例，用于读取传感器数据。

        Raises:
            ConnectionError: 如果尚未连接到手机。
        """
        if self._sensors is None:
            raise ConnectionError("未连接，请先调用 connect()")
        return self._sensors

    @property
    def recorder(self) -> DataRecorder:
        """获取数据采集器模块。

        Returns:
            DataRecorder 实例，用于录制训练数据。

        Raises:
            ConnectionError: 如果尚未连接到手机。
        """
        if self._recorder is None:
            raise ConnectionError("未连接，请先调用 connect()")
        return self._recorder

    # ==================== 电机控制（代理到motor模块）====================

    def drive(self, left: float, right: float) -> bool:
        """控制左右电机速度。

        Args:
            left: 左轮速度，范围 -1.0 到 1.0。正值前进，负值后退。
            right: 右轮速度，范围 -1.0 到 1.0。正值前进，负值后退。

        Returns:
            发送成功返回 True。

        Example:
            >>> bot.drive(0.5, 0.5)   # 直行
            >>> bot.drive(0.5, -0.5)  # 原地右转
        """
        return self.motor.drive(left, right)

    def forward(self, speed: float = 0.5) -> bool:
        """控制机器人前进。

        Args:
            speed: 前进速度，范围 0.0 到 1.0，默认 0.5。

        Returns:
            发送成功返回 True。
        """
        return self.motor.forward(speed)

    def backward(self, speed: float = 0.5) -> bool:
        """控制机器人后退。

        Args:
            speed: 后退速度，范围 0.0 到 1.0，默认 0.5。

        Returns:
            发送成功返回 True。
        """
        return self.motor.backward(speed)

    def turn_left(self, speed: float = 0.5) -> bool:
        """控制机器人原地左转。

        Args:
            speed: 转弯速度，范围 0.0 到 1.0，默认 0.5。

        Returns:
            发送成功返回 True。
        """
        return self.motor.turn_left(speed)

    def turn_right(self, speed: float = 0.5) -> bool:
        """控制机器人原地右转。

        Args:
            speed: 转弯速度，范围 0.0 到 1.0，默认 0.5。

        Returns:
            发送成功返回 True。
        """
        return self.motor.turn_right(speed)

    def stop(self) -> bool:
        """停止机器人所有电机。

        Returns:
            发送成功返回 True。
        """
        return self.motor.stop()

    # ==================== 带持续时间的控制 ====================

    def move_forward(self, speed: float = 0.5, duration: float = 1.0) -> bool:
        """前进指定时间后自动停止。

        Args:
            speed: 前进速度，范围 0.0 到 1.0，默认 0.5。
            duration: 持续时间（秒），默认 1.0。

        Returns:
            发送成功返回 True。
        """
        return self.motor.move_forward(speed, duration)

    def move_backward(self, speed: float = 0.5, duration: float = 1.0) -> bool:
        """后退指定时间后自动停止。

        Args:
            speed: 后退速度，范围 0.0 到 1.0，默认 0.5。
            duration: 持续时间（秒），默认 1.0。

        Returns:
            发送成功返回 True。
        """
        return self.motor.move_backward(speed, duration)

    def rotate_left(self, speed: float = 0.5, duration: float = 1.0) -> bool:
        """原地左转指定时间后自动停止。

        Args:
            speed: 转弯速度，范围 0.0 到 1.0，默认 0.5。
            duration: 持续时间（秒），默认 1.0。

        Returns:
            发送成功返回 True。
        """
        return self.motor.rotate_left(speed, duration)

    def rotate_right(self, speed: float = 0.5, duration: float = 1.0) -> bool:
        """原地右转指定时间后自动停止。

        Args:
            speed: 转弯速度，范围 0.0 到 1.0，默认 0.5。
            duration: 持续时间（秒），默认 1.0。

        Returns:
            发送成功返回 True。
        """
        return self.motor.rotate_right(speed, duration)

    def move(self, left: float, right: float, duration: float = 1.0) -> bool:
        """双轮独立控制，指定时间后自动停止。

        Args:
            left: 左轮速度，范围 -1.0 到 1.0。
            right: 右轮速度，范围 -1.0 到 1.0。
            duration: 持续时间（秒），默认 1.0。

        Returns:
            发送成功返回 True。
        """
        return self.motor.move(left, right, duration)

    # ==================== 视频（代理到video模块）====================

    def get_frame(self) -> Optional[np.ndarray]:
        """获取最新视频帧。

        Returns:
            numpy 数组格式的图像帧 (BGR格式)，如果没有帧则返回 None。
        """
        return self.video.get_frame()

    def start_video(self, display: bool = True, callback: Optional[Callable[[np.ndarray], None]] = None) -> None:
        """开始接收并显示视频。

        Args:
            display: 是否显示视频窗口，默认 True。
            callback: 每帧回调函数，接收 numpy 数组参数。
        """
        if callback:
            self.video.set_callback(callback)
        if display:
            self.video.start_display()

    def stop_video(self) -> None:
        """停止视频显示窗口。"""
        self.video.stop_display()

    def video_stream(self) -> Generator[np.ndarray, None, None]:
        """获取视频帧生成器。

        Returns:
            生成器，每次迭代返回一帧图像 (numpy 数组)。

        Example:
            >>> for frame in bot.video_stream():
            ...     process(frame)
        """
        return self.video.stream()

    # ==================== 传感器（代理到sensors模块）====================

    def get_sensors(self) -> Dict[str, Any]:
        """获取所有传感器数据。

        Returns:
            包含所有传感器数据的字典，键包括:
            - 'accelerometer': 加速度计数据 {x, y, z}
            - 'gyroscope': 陀螺仪数据 {x, y, z}
            - 'magnetometer': 磁力计数据 {x, y, z}
            - 'battery_level': 电池电量百分比
        """
        return self.sensors.get_all()

    def get_accelerometer(self) -> Optional[Dict[str, float]]:
        """获取加速度计数据。

        Returns:
            包含 x, y, z 轴加速度的字典，单位 m/s²。
            如果没有数据则返回 None。
        """
        return self.sensors.get_accelerometer()

    def get_gyroscope(self) -> Optional[Dict[str, float]]:
        """获取陀螺仪数据。

        Returns:
            包含 x, y, z 轴角速度的字典，单位 rad/s。
            如果没有数据则返回 None。
        """
        return self.sensors.get_gyroscope()

    # ==================== 数据采集（代理到recorder模块）====================

    def start_recording(self, output_dir: str = "./dataset") -> None:
        """开始数据采集。

        将视频帧和传感器数据保存到指定目录。

        Args:
            output_dir: 数据保存目录，默认 "./dataset"。
        """
        self.recorder.start(output_dir)

    def stop_recording(self) -> None:
        """停止数据采集。"""
        self.recorder.stop()

    # ==================== 实时控制 ====================

    def realtime_control(self, base_speed: float = 0.7) -> None:
        """启动实时键盘控制。

        使用键盘控制机器人移动，支持漂移和调速功能。

        控制方式:
            W - 前进
            S - 后退
            A - 左转 (边走边转)
            D - 右转 (边走边转)
            Shift+A/D - 漂移急转
            +/- - 调速
            R - 切换录制
            ESC - 退出

        Args:
            base_speed: 基础速度，范围 0.1-1.0，默认 0.7。

        Note:
            此方法会阻塞直到用户按 ESC 退出。
            首次使用时会自动安装 pynput 库。
        """
        import subprocess
        import sys
        import threading

        # 自动安装 pynput
        try:
            from pynput import keyboard
        except ImportError:
            print("Installing pynput...")
            subprocess.check_call([sys.executable, "-m", "pip", "install", "pynput"])
            from pynput import keyboard
            print("pynput installed!\n")

        # 控制参数
        turn_ratio = 0.15
        drift_ratio = -0.3
        spin_speed = 0.6
        min_motor_speed = 0.35

        pressed_keys = set()
        running = [True]
        current_speed = [base_speed]

        def apply_deadzone(value: float) -> float:
            if abs(value) < 0.01:
                return 0.0
            sign = 1 if value > 0 else -1
            mapped = min_motor_speed + abs(value) * (1.0 - min_motor_speed)
            return sign * mapped

        def calculate_motors() -> tuple:
            keys = pressed_keys
            speed = current_speed[0]

            drift = 'shift' in keys
            fwd = 'w' in keys
            bwd = 's' in keys
            left = 'a' in keys
            right = 'd' in keys

            if not (fwd or bwd or left or right):
                return 0, 0

            base = speed if fwd else (-speed if bwd else 0)
            left_motor = base
            right_motor = base

            if left:
                if drift and base != 0:
                    left_motor = base * drift_ratio
                elif base != 0:
                    left_motor = base * turn_ratio
                else:
                    left_motor = -speed * spin_speed
                    right_motor = speed * spin_speed
            elif right:
                if drift and base != 0:
                    right_motor = base * drift_ratio
                elif base != 0:
                    right_motor = base * turn_ratio
                else:
                    left_motor = speed * spin_speed
                    right_motor = -speed * spin_speed

            left_motor = max(-1.0, min(1.0, apply_deadzone(left_motor)))
            right_motor = max(-1.0, min(1.0, apply_deadzone(right_motor)))

            return left_motor, right_motor

        def update_loop():
            last_left, last_right = 0, 0
            last_print_time = 0

            while running[0]:
                left, right = calculate_motors()

                if (left, right) != (last_left, last_right):
                    if left == 0 and right == 0:
                        self.stop()
                        # 同步到数据采集器
                        if self._recorder and self._recorder.is_recording:
                            self._recorder.set_command("stop", [0.0, 0.0])
                    else:
                        self.drive(left, right)
                        # 同步到数据采集器
                        if self._recorder and self._recorder.is_recording:
                            self._recorder.set_command("drive", [left, right])
                    last_left, last_right = left, right

                    now = time.time()
                    if now - last_print_time > 0.2:
                        if left == 0 and right == 0:
                            status = "STOP"
                        else:
                            status = f"L:{left:+.2f} R:{right:+.2f}"
                            if 'shift' in pressed_keys:
                                status += " [DRIFT]"
                        rec_status = " [REC]" if (self._recorder and self._recorder.is_recording) else ""
                        print(f"\rSpeed {int(current_speed[0] * 100)}% | {status}{rec_status}      ", end='', flush=True)
                        last_print_time = now

                time.sleep(0.03)

        def on_press(key):
            try:
                k = key.char.lower()
                pressed_keys.add(k)
                if k in ['+', '=']:
                    current_speed[0] = min(1.0, current_speed[0] + 0.1)
                    print(f"\rSpeed: {int(current_speed[0] * 100)}%                  ")
                elif k in ['-', '_']:
                    current_speed[0] = max(0.1, current_speed[0] - 0.1)
                    print(f"\rSpeed: {int(current_speed[0] * 100)}%                  ")
                elif k == 'r':
                    # 切换录制状态
                    if self._recorder:
                        if self._recorder.is_recording:
                            self._recorder.stop()
                            print(f"\rRecording stopped                    ")
                        else:
                            self._recorder.start()
                            print(f"\rRecording started                    ")
            except AttributeError:
                if key in [keyboard.Key.shift, keyboard.Key.shift_l, keyboard.Key.shift_r]:
                    pressed_keys.add('shift')
                elif key == keyboard.Key.esc:
                    running[0] = False
                    return False

        def on_release(key):
            try:
                pressed_keys.discard(key.char.lower())
            except AttributeError:
                if key in [keyboard.Key.shift, keyboard.Key.shift_l, keyboard.Key.shift_r]:
                    pressed_keys.discard('shift')

        print("\n" + "=" * 50)
        print("Realtime Control - WASD")
        print("=" * 50)
        print("\n  W - Forward    S - Backward")
        print("  A - Left       D - Right")
        print("  Shift+A/D - Drift")
        print("  +/- - Speed    R - Record")
        print("  ESC - Exit")
        print(f"\nSpeed: {int(current_speed[0] * 100)}%")
        print("=" * 50 + "\n")

        update_thread = threading.Thread(target=update_loop, daemon=True)
        update_thread.start()

        try:
            with keyboard.Listener(on_press=on_press, on_release=on_release) as listener:
                listener.join()
        except KeyboardInterrupt:
            pass
        finally:
            running[0] = False
            self.stop()
            print("\n\nControl stopped")

    # ==================== 上下文管理器 ====================

    def __enter__(self) -> 'OpenBene':
        """进入上下文管理器，自动连接。

        Returns:
            已连接的 OpenBene 实例。
        """
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        """退出上下文管理器，自动断开连接。"""
        self.disconnect()

    def __repr__(self) -> str:
        """返回对象的字符串表示。

        Returns:
            格式化的字符串，包含 IP、端口和连接状态。
        """
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
