"""
OpenBene Recording Module - 数据采集

提供训练数据录制功能。

使用方法:
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
"""

import os
import csv
import logging
from datetime import datetime
from typing import Optional, Tuple

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

    def start(self, output_dir: str = "./dataset"):
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

        # 设置视频帧回调
        self.video.set_callback(self._save_frame)

        logger.info(f"开始数据采集: {output_dir}")

    def stop(self):
        """停止数据采集"""
        self._recording = False

        # 移除视频帧回调
        self.video.set_callback(None)

        if self._record_file:
            self._record_file.close()
            self._record_file = None
            self._record_writer = None

        logger.info(f"数据采集完成，共 {self._frame_counter} 帧")

    def set_command(self, cmd: str, values: list):
        """
        设置当前控制命令（用于标签）

        Args:
            cmd: 命令名称
            values: 命令参数
        """
        self._last_command = (cmd, values)

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
        """是否正在录制"""
        return self._recording

    @property
    def frame_count(self) -> int:
        """已录制的帧数"""
        return self._frame_counter

    def __repr__(self):
        status = f"录制中 ({self._frame_counter} 帧)" if self._recording else "未录制"
        return f"DataRecorder({status})"
