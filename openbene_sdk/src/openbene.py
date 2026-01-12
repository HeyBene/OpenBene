"""
OpenBene SDK - PC端Python控制库

通过WebSocket连接到手机App，实现：
- 发送控制命令（drive, stop等）
- 接收视频流（JPEG帧）
- 接收传感器数据
- 数据采集模式

架构：手机是WebSocket Server，PC是Client
"""

import json
import logging
import time
import threading
import asyncio
import base64
import os
import csv
import socket
from datetime import datetime
from typing import Optional, Callable, Dict, Any, List

# Try importing WebSocket support
try:
    import websockets
    WEBSOCKET_SUPPORT = True
except ImportError:
    WEBSOCKET_SUPPORT = False
    websockets = None

# Try importing OpenCV for video support
try:
    import cv2
    import numpy as np
    VIDEO_SUPPORT = True
except ImportError:
    VIDEO_SUPPORT = False
    cv2 = None
    np = None

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class ConnectionError(Exception):
    """连接失败异常"""
    pass


class RobotType:
    """机器人硬件类型"""
    RTR_TT = "RTR_TT"      # Arduino Nano, TT电机
    RTR_520 = "RTR_520"    # ESP32, 520电机


class OpenBene:
    """
    OpenBene机器人控制器

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
        if not WEBSOCKET_SUPPORT:
            raise ImportError("需要安装websockets库: pip install websockets")

        self.ip = ip
        self.port = port
        self.connected = False
        self.name = "OpenBot"  # 机器人名称
        self.robot_type = None  # 硬件类型 (RobotType.RTR_TT 或 RobotType.RTR_520)

        # WebSocket相关
        self._ws = None
        self._ws_loop = None
        self._ws_thread = None
        self._ws_running = False
        self._send_queue: asyncio.Queue = None

        # 传感器数据
        self._sensor_lock = threading.Lock()
        self._accelerometer: Optional[Dict[str, float]] = None
        self._gyroscope: Optional[Dict[str, float]] = None
        self._magnetometer: Optional[Dict[str, float]] = None
        self._battery_level: Optional[float] = None

        # 视频帧
        self._frame_lock = threading.Lock()
        self._latest_frame: Optional[bytes] = None
        self._frame_callback: Optional[Callable[[bytes], None]] = None

        # 数据采集
        self._recording = False
        self._record_dir: Optional[str] = None
        self._record_file = None
        self._record_writer = None
        self._frame_counter = 0
        self._last_command = ("stop", [0.0, 0.0])

        # OpenCV窗口
        self._display_active = False
        self._display_thread = None

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

    def disconnect(self):
        """断开连接"""
        self._ws_running = False
        self._display_active = False

        if self._recording:
            self.stop_recording()

        if self._ws_thread and self._ws_thread.is_alive():
            self._ws_thread.join(timeout=2.0)

        self.connected = False
        self._ws = None
        logger.info(f"已断开连接: {self.ip}")

    def _run_ws_loop(self):
        """WebSocket事件循环（在独立线程中运行）"""
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

    async def _ws_handler(self):
        """WebSocket连接处理"""
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

    async def _ws_sender(self):
        """发送消息到手机"""
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

    async def _ws_receiver(self):
        """接收手机发来的消息"""
        while self._ws_running and self._ws:
            try:
                message = await self._ws.recv()
                data = json.loads(message)
                self._handle_message(data)
            except json.JSONDecodeError as e:
                logger.warning(f"JSON解析错误: {e}")
            except Exception as e:
                logger.error(f"接收错误: {e}")
                break

    def _handle_message(self, message: Dict[str, Any]):
        """处理收到的消息"""
        msg_type = message.get('type')

        if msg_type == 'video_frame':
            self._handle_video_frame(message)
        elif msg_type == 'sensor_data':
            self._handle_sensor_data(message)
        elif msg_type == 'heartbeat':
            # 响应心跳
            self._queue_message({'type': 'pong', 'timestamp': int(time.time() * 1000)})

    def _handle_video_frame(self, message: Dict[str, Any]):
        """处理视频帧"""
        try:
            base64_data = message.get('data', '')
            jpeg_bytes = base64.b64decode(base64_data)

            with self._frame_lock:
                self._latest_frame = jpeg_bytes

            # 数据采集模式：保存帧
            if self._recording:
                self._save_frame(jpeg_bytes)

            # 用户回调
            if self._frame_callback:
                self._frame_callback(jpeg_bytes)

        except Exception as e:
            logger.error(f"视频帧处理错误: {e}")

    def _handle_sensor_data(self, message: Dict[str, Any]):
        """处理传感器数据"""
        try:
            data = message.get('data', {})

            with self._sensor_lock:
                self._accelerometer = data.get('accelerometer')
                self._gyroscope = data.get('gyroscope')
                self._magnetometer = data.get('magnetometer')
                self._battery_level = data.get('battery_level')

        except Exception as e:
            logger.error(f"传感器数据处理错误: {e}")

    def _queue_message(self, message: dict):
        """添加消息到发送队列"""
        if self._ws_loop and self._send_queue:
            asyncio.run_coroutine_threadsafe(
                self._send_queue.put(message),
                self._ws_loop
            )

    def _send_command(self, cmd: str, val: Optional[List[float]] = None) -> bool:
        """
        发送控制命令

        Args:
            cmd: 命令名称
            val: 参数值列表
        """
        if not self.connected:
            raise ConnectionError("未连接，请先调用 connect()")

        message = {"cmd": cmd}
        if val is not None:
            message["val"] = val

        self._queue_message(message)
        self._last_command = (cmd, val or [])
        logger.debug(f"命令: {cmd}, 值: {val}")
        return True

    # ==================== 控制API ====================

    def drive(self, left: float, right: float) -> bool:
        """
        控制电机速度

        Args:
            left: 左轮速度 (-1.0 到 1.0)
            right: 右轮速度 (-1.0 到 1.0)

        Example:
            bot.drive(0.5, 0.5)  # 前进
            bot.drive(-0.3, 0.3)  # 左转
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

    # ==================== 带持续时间的控制API ====================

    def move_forward(self, speed: float = 0.5, duration: float = 1.0) -> bool:
        """
        前进指定时间后自动停止

        Args:
            speed: 速度 (0.0 到 1.0)
            duration: 持续时间（秒），默认1秒

        Example:
            bot.move_forward()           # 以0.5速度前进1秒
            bot.move_forward(0.8, 2.0)   # 以0.8速度前进2秒
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
            bot.move(0.3, 0.5)        # 左轮0.3，右轮0.5，持续1秒
            bot.move(0.5, 0.5, 2.0)   # 前进2秒
        """
        self.drive(left, right)
        time.sleep(duration)
        self.stop()
        return True

    # ==================== 视频API ====================

    def get_frame(self) -> Optional[Any]:
        """
        获取最新视频帧

        Returns:
            numpy数组 (BGR格式)，如果没有帧则返回None

        Example:
            frame = bot.get_frame()
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

    def start_video(self, display: bool = True, callback: Optional[Callable] = None):
        """
        开始接收视频

        Args:
            display: 是否显示OpenCV窗口
            callback: 帧回调函数 callback(jpeg_bytes)
        """
        self._frame_callback = callback

        if display and VIDEO_SUPPORT:
            self._display_active = True
            self._display_thread = threading.Thread(target=self._display_loop, daemon=True)
            self._display_thread.start()

    def stop_video(self):
        """停止视频显示"""
        self._display_active = False
        self._frame_callback = None
        if VIDEO_SUPPORT:
            cv2.destroyAllWindows()

    def video_stream(self):
        """
        返回视频帧生成器

        Yields:
            numpy数组 (BGR格式) 每帧视频

        Example:
            for frame in bot.video_stream():
                cv2.imshow("Video", frame)
                if cv2.waitKey(1) == ord('q'):
                    break
        """
        if not VIDEO_SUPPORT:
            raise ImportError("需要安装OpenCV: pip install opencv-python")

        try:
            while self.connected:
                frame = self.get_frame()
                if frame is not None:
                    yield frame
                time.sleep(0.033)  # ~30fps
        finally:
            pass

    def _display_loop(self):
        """OpenCV显示循环"""
        while self._display_active and self.connected:
            frame = self.get_frame()
            if frame is not None:
                cv2.imshow("OpenBene Camera", frame)

            key = cv2.waitKey(30) & 0xFF
            if key == ord('q'):
                self._display_active = False
                break

        cv2.destroyAllWindows()

    # ==================== 传感器API ====================

    def get_sensors(self) -> Dict[str, Any]:
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
        """获取加速度计数据 (m/s²)"""
        with self._sensor_lock:
            return self._accelerometer.copy() if self._accelerometer else None

    def get_gyroscope(self) -> Optional[Dict[str, float]]:
        """获取陀螺仪数据 (rad/s)"""
        with self._sensor_lock:
            return self._gyroscope.copy() if self._gyroscope else None

    # ==================== 数据采集API ====================

    def start_recording(self, output_dir: str = "./dataset"):
        """
        开始数据采集

        Args:
            output_dir: 输出目录

        输出格式:
            output_dir/
            ├── images/
            │   ├── 000001.jpg
            │   └── ...
            └── labels.csv
        """
        self._record_dir = output_dir
        images_dir = os.path.join(output_dir, "images")
        os.makedirs(images_dir, exist_ok=True)

        # 创建CSV文件
        csv_path = os.path.join(output_dir, "labels.csv")
        self._record_file = open(csv_path, 'w', newline='', encoding='utf-8')
        self._record_writer = csv.writer(self._record_file)
        self._record_writer.writerow([
            'image', 'timestamp',
            'accel_x', 'accel_y', 'accel_z',
            'gyro_x', 'gyro_y', 'gyro_z',
            'command', 'speed_left', 'speed_right'
        ])

        self._frame_counter = 0
        self._recording = True
        logger.info(f"开始数据采集: {output_dir}")

    def stop_recording(self):
        """停止数据采集"""
        self._recording = False

        if self._record_file:
            self._record_file.close()
            self._record_file = None
            self._record_writer = None

        logger.info(f"数据采集完成，共 {self._frame_counter} 帧")

    def _save_frame(self, jpeg_bytes: bytes):
        """保存一帧数据"""
        if not self._recording or not self._record_writer:
            return

        self._frame_counter += 1
        filename = f"{self._frame_counter:06d}.jpg"

        # 保存图片
        image_path = os.path.join(self._record_dir, "images", filename)
        with open(image_path, 'wb') as f:
            f.write(jpeg_bytes)

        # 获取传感器数据
        accel = self._accelerometer or {'x': 0, 'y': 0, 'z': 0}
        gyro = self._gyroscope or {'x': 0, 'y': 0, 'z': 0}

        # 记录到CSV
        cmd, vals = self._last_command
        left_speed = vals[0] if len(vals) > 0 else 0.0
        right_speed = vals[1] if len(vals) > 1 else 0.0

        self._record_writer.writerow([
            filename,
            datetime.now().isoformat(),
            accel.get('x', 0), accel.get('y', 0), accel.get('z', 0),
            gyro.get('x', 0), gyro.get('y', 0), gyro.get('z', 0),
            cmd, left_speed, right_speed
        ])

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
