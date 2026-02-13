"""
OpenBene Recording Module - 数据采集

提供训练数据录制功能。

使用方法:
    # DataRecorder: 保存为 JPEG 图片
    from openbene.connection import WebSocketConnection
    from openbene.video import VideoReceiver
    from openbene.sensors import SensorManager
    from openbene.recording import DataRecorder

    conn = WebSocketConnection("192.168.1.100")
    conn.connect()

    video = VideoReceiver(conn)
    sensors = SensorManager(conn)
    recorder = DataRecorder(video, sensors)

    recorder.start("./my_dataset")
    # ... 控制机器人采集数据 ...
    recorder.stop()

    # DataLogger: 灵活选择图片或视频
    from openbene import OpenBene, DataLogger

    with OpenBene("192.168.1.100") as bot:
        # 保存为图片
        logger = DataLogger(bot.video, bot.sensors, save_format='images')
        logger.start("./training_images")
        # ... 控制机器人 ...
        logger.stop()

        # 保存为视频
        logger = DataLogger(bot.video, bot.sensors, save_format='video', fps=30.0)
        logger.start("./training_video")
        # ... 控制机器人 ...
        logger.stop()
"""

import os
import csv
import time
import logging
from datetime import datetime
from typing import Optional, Tuple, List

# Try importing OpenCV for video support
try:
    import cv2
    import numpy as np
    VIDEO_SUPPORT = True
except ImportError:
    VIDEO_SUPPORT = False
    cv2 = None
    np = None

from .video import VideoReceiver
from .sensors import SensorManager

logger = logging.getLogger(__name__)


class DataRecorder:
    """
    数据采集器

    负责录制训练数据，包括视频帧和传感器数据。

    输出格式:
        output_dir/
        ├── images/
        │   ├── 000001.jpg
        │   └── ...
        └── labels.csv

    Attributes:
        video: 视频接收器实例
        sensors: 传感器管理器实例
    """

    def __init__(self, video: VideoReceiver, sensors: SensorManager):
        """
        初始化数据采集器

        Args:
            video: 视频接收器实例
            sensors: 传感器管理器实例
        """
        self.video = video
        self.sensors = sensors

        # 录制状态
        self._recording = False
        self._record_dir: Optional[str] = None
        self._record_file = None
        self._record_writer = None
        self._frame_counter = 0
        self._last_command: Tuple[str, list] = ("stop", [0.0, 0.0])

        # 保存原始回调
        self._original_callback = None

    def start(self, output_dir: str = "./dataset") -> None:
        """开始数据采集。

        在指定目录创建 images 子目录和 labels.csv 文件，
        每帧视频会自动保存并记录传感器数据和控制命令。

        Args:
            output_dir: 输出目录路径，默认 "./dataset"。

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

        # 设置视频帧回调
        self.video.set_callback(self._save_frame)

        logger.info(f"开始数据采集: {output_dir}")

    def stop(self) -> None:
        """停止数据采集并关闭文件。

        清理视频回调，关闭 CSV 文件，并记录采集的帧数。
        """
        self._recording = False

        # 移除视频帧回调
        self.video.set_callback(None)

        if self._record_file:
            self._record_file.close()
            self._record_file = None
            self._record_writer = None

        logger.info(f"数据采集完成，共 {self._frame_counter} 帧")

    def set_command(self, cmd: str, values: List[float]) -> None:
        """设置当前控制命令（用于数据标签）。

        录制时会将此命令与每帧视频一起保存到 CSV 文件。

        Args:
            cmd: 命令名称，如 "drive" 或 "stop"。
            values: 命令参数列表，如 [left_speed, right_speed]。
        """
        self._last_command = (cmd, values)

    def _save_frame(self, jpeg_bytes: bytes) -> None:
        """保存一帧视频和相关数据到文件。

        将 JPEG 图像保存到 images 目录，并将传感器数据、
        控制命令等信息写入 CSV 文件。

        Args:
            jpeg_bytes: JPEG 格式的图像字节数据。
        """
        if not self._recording or not self._record_writer:
            return

        self._frame_counter += 1
        filename = f"{self._frame_counter:06d}.jpg"

        # 保存图片
        image_path = os.path.join(self._record_dir, "images", filename)
        with open(image_path, 'wb') as f:
            f.write(jpeg_bytes)

        # 获取传感器数据
        accel = self.sensors.get_accelerometer() or {'x': 0, 'y': 0, 'z': 0}
        gyro = self.sensors.get_gyroscope() or {'x': 0, 'y': 0, 'z': 0}

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

    @property
    def is_recording(self) -> bool:
        """检查是否正在录制。

        Returns:
            如果正在录制返回 True，否则返回 False。
        """
        return self._recording

    @property
    def frame_count(self) -> int:
        """获取已录制的帧数。

        Returns:
            已录制的视频帧数量。
        """
        return self._frame_counter

    def __repr__(self) -> str:
        """返回对象的字符串表示。

        Returns:
            格式化的字符串，包含录制状态和帧数。
        """
        status = f"录制中 ({self._frame_counter} 帧)" if self._recording else "未录制"
        return f"DataRecorder({status})"


class DataLogger:
    """灵活的数据记录器，支持图片或视频保存。

    相比 DataRecorder，DataLogger 提供更精确的时间戳和灵活的保存格式。
    支持将视频保存为 JPEG 图片序列或 MP4 视频文件。

    输出格式 (图片模式):
        output_dir/
        ├── images/
        │   ├── 000001.jpg
        │   └── ...
        └── sensor_data.csv

    输出格式 (视频模式):
        output_dir/
        ├── video.mp4
        └── sensor_data.csv

    Attributes:
        video: 视频接收器实例
        sensors: 传感器管理器实例
        save_format: 保存格式 ('images' 或 'video')
        fps: 视频帧率 (仅视频模式)
    """

    def __init__(
        self,
        video: VideoReceiver,
        sensors: SensorManager,
        save_format: str = 'images',
        fps: float = 30.0,
        codec: str = 'mp4v'
    ):
        """初始化数据记录器。

        Args:
            video: 视频接收器实例。
            sensors: 传感器管理器实例。
            save_format: 保存格式，'images' 保存为 JPEG 图片，
                        'video' 保存为 MP4 视频。默认 'images'。
            fps: 视频帧率（仅 video 模式有效）。默认 30.0。
            codec: 视频编码器（仅 video 模式有效）。默认 'mp4v'。

        Raises:
            ValueError: 当 save_format 不是 'images' 或 'video' 时抛出。
        """
        if save_format not in ('images', 'video'):
            raise ValueError("save_format 必须是 'images' 或 'video'")

        if save_format == 'video' and not VIDEO_SUPPORT:
            raise ImportError("视频模式需要安装 OpenCV: pip install opencv-python")

        self.video = video
        self.sensors = sensors
        self._save_format = save_format
        self._fps = fps
        self._codec = codec

        # 录制状态
        self._recording = False
        self._record_dir: Optional[str] = None
        self._csv_file = None
        self._csv_writer = None
        self._frame_counter = 0
        self._start_time: float = 0.0
        self._last_command: Tuple[str, List[float]] = ("stop", [0.0, 0.0])

        # 视频模式专用
        self._video_writer = None
        self._frame_size: Optional[Tuple[int, int]] = None

    def start(self, output_dir: str = "./recordings") -> None:
        """开始录制。

        创建输出目录和相关文件，开始记录视频帧和传感器数据。
        视频帧与传感器数据使用统一的时间基准，确保时间对齐。

        Args:
            output_dir: 输出目录路径，默认 "./recordings"。
        """
        self._record_dir = output_dir
        os.makedirs(output_dir, exist_ok=True)

        # 图片模式：创建 images 子目录
        if self._save_format == 'images':
            images_dir = os.path.join(output_dir, "images")
            os.makedirs(images_dir, exist_ok=True)

        # 创建 CSV 文件
        csv_path = os.path.join(output_dir, "sensor_data.csv")
        self._csv_file = open(csv_path, 'w', newline='', encoding='utf-8')
        self._csv_writer = csv.writer(self._csv_file)

        # 根据模式选择 CSV 列
        if self._save_format == 'images':
            self._csv_writer.writerow([
                'frame_id', 'image_file', 'timestamp', 'relative_time',
                'accel_x', 'accel_y', 'accel_z',
                'gyro_x', 'gyro_y', 'gyro_z',
                'battery', 'command', 'speed_left', 'speed_right'
            ])
        else:
            self._csv_writer.writerow([
                'frame_id', 'timestamp', 'relative_time',
                'accel_x', 'accel_y', 'accel_z',
                'gyro_x', 'gyro_y', 'gyro_z',
                'battery', 'command', 'speed_left', 'speed_right'
            ])

        self._frame_counter = 0
        self._start_time = time.time()
        self._recording = True

        # 设置视频帧回调
        self.video.set_callback(self._process_frame)

        logger.info(f"开始录制 ({self._save_format} 模式): {output_dir}")

    def stop(self) -> None:
        """停止录制并关闭所有文件。

        清理视频回调，释放视频写入器，关闭 CSV 文件。
        """
        self._recording = False

        # 移除视频帧回调
        self.video.set_callback(None)

        # 关闭视频写入器
        if self._video_writer is not None:
            self._video_writer.release()
            self._video_writer = None

        # 关闭 CSV 文件
        if self._csv_file:
            self._csv_file.close()
            self._csv_file = None
            self._csv_writer = None

        duration = time.time() - self._start_time if self._start_time else 0
        logger.info(f"录制完成，共 {self._frame_counter} 帧，时长 {duration:.1f} 秒")

    def set_command(self, cmd: str, values: List[float]) -> None:
        """设置当前控制命令（用于数据标签）。

        录制时会将此命令与每帧数据一起保存到 CSV 文件。

        Args:
            cmd: 命令名称，如 "drive" 或 "stop"。
            values: 命令参数列表，如 [left_speed, right_speed]。
        """
        self._last_command = (cmd, values)

    def _process_frame(self, jpeg_bytes: bytes) -> None:
        """处理一帧视频并记录相关数据。

        根据保存模式，将帧保存为图片或写入视频文件。
        同时记录传感器数据到 CSV 文件。

        Args:
            jpeg_bytes: JPEG 格式的图像字节数据。
        """
        if not self._recording or not self._csv_writer:
            return

        self._frame_counter += 1
        current_time = time.time()
        relative_time = current_time - self._start_time

        # 获取传感器数据
        accel = self.sensors.get_accelerometer() or {'x': 0, 'y': 0, 'z': 0}
        gyro = self.sensors.get_gyroscope() or {'x': 0, 'y': 0, 'z': 0}
        battery = self.sensors.get_battery_level() or 0.0

        # 获取控制命令
        cmd, vals = self._last_command
        left_speed = vals[0] if len(vals) > 0 else 0.0
        right_speed = vals[1] if len(vals) > 1 else 0.0

        if self._save_format == 'images':
            # 图片模式：保存 JPEG 文件
            filename = f"{self._frame_counter:06d}.jpg"
            image_path = os.path.join(self._record_dir, "images", filename)
            with open(image_path, 'wb') as f:
                f.write(jpeg_bytes)

            # 写入 CSV（包含图片文件名）
            self._csv_writer.writerow([
                self._frame_counter, filename, current_time, f"{relative_time:.6f}",
                accel.get('x', 0), accel.get('y', 0), accel.get('z', 0),
                gyro.get('x', 0), gyro.get('y', 0), gyro.get('z', 0),
                battery, cmd, left_speed, right_speed
            ])
        else:
            # 视频模式：写入 MP4 文件
            # 解码 JPEG 为 numpy 数组
            nparr = np.frombuffer(jpeg_bytes, np.uint8)
            frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

            if frame is not None:
                # 首帧时初始化视频写入器
                if self._video_writer is None:
                    height, width = frame.shape[:2]
                    self._frame_size = (width, height)
                    video_path = os.path.join(self._record_dir, "video.mp4")
                    fourcc = cv2.VideoWriter_fourcc(*self._codec)
                    self._video_writer = cv2.VideoWriter(
                        video_path, fourcc, self._fps, self._frame_size
                    )
                    logger.info(f"视频: {width}x{height} @ {self._fps}fps")

                self._video_writer.write(frame)

            # 写入 CSV（不包含图片文件名）
            self._csv_writer.writerow([
                self._frame_counter, current_time, f"{relative_time:.6f}",
                accel.get('x', 0), accel.get('y', 0), accel.get('z', 0),
                gyro.get('x', 0), gyro.get('y', 0), gyro.get('z', 0),
                battery, cmd, left_speed, right_speed
            ])

    @property
    def is_recording(self) -> bool:
        """检查是否正在录制。

        Returns:
            如果正在录制返回 True，否则返回 False。
        """
        return self._recording

    @property
    def frame_count(self) -> int:
        """获取已录制的帧数。

        Returns:
            已录制的视频帧数量。
        """
        return self._frame_counter

    @property
    def elapsed_time(self) -> float:
        """获取已录制的时长（秒）。

        Returns:
            从开始录制到现在的时间（秒）。未录制时返回 0。
        """
        if self._recording and self._start_time:
            return time.time() - self._start_time
        return 0.0

    @property
    def save_format(self) -> str:
        """获取保存格式。

        Returns:
            'images' 或 'video'。
        """
        return self._save_format

    def __repr__(self) -> str:
        """返回对象的字符串表示。

        Returns:
            格式化的字符串，包含录制状态、模式和帧数。
        """
        if self._recording:
            status = f"录制中 ({self._frame_counter} 帧, {self.elapsed_time:.1f}s)"
        else:
            status = "未录制"
        return f"DataLogger(format={self._save_format}, {status})"
