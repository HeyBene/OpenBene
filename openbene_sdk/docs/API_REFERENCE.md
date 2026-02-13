# OpenBene SDK API Reference

OpenBene SDK v2.5.0 - Python SDK for controlling OpenBot robots.

## 目录

- [OpenBene](#openbene) - 主控制器
- [WebSocketConnection](#websocketconnection) - WebSocket 连接
- [MQTTConnection](#mqttconnection) - MQTT 连接
- [MotorController](#motorcontroller) - 电机控制
- [VideoReceiver](#videoreceiver) - 视频接收
- [SensorManager](#sensormanager) - 传感器管理
- [DataRecorder](#datarecorder) - 数据采集
- [DataLogger](#datalogger) - 灵活数据录制
- [Discovery](#discovery) - 设备发现
- [ImageProcessor](#imageprocessor) - 图像处理器
- [MQTTTopics](#mqtttopics) - MQTT 主题工具

---

## OpenBene

主控制器类，整合所有模块的统一 API 接口。

### 导入

```python
from openbene import OpenBene
```

### 构造函数

```python
OpenBene(ip: str, port: int = 8765)
```

**参数:**
- `ip`: 手机 IP 地址
- `port`: WebSocket 端口，默认 8765

### 类方法

#### `discover(timeout: float = 5.0) -> Optional[Dict[str, Any]]`

自动发现网络中的 OpenBene 机器人。

**参数:**
- `timeout`: 发现超时时间（秒）

**返回:** 发现的机器人信息字典 `{'name', 'ip', 'port'}` 或 `None`

#### `auto_connect(timeout: float = 10.0, retries: int = 3) -> OpenBene`

自动发现并连接到机器人。

**参数:**
- `timeout`: 发现和连接的总超时时间（秒）
- `retries`: 发现失败时的重试次数

**返回:** 已连接的 `OpenBene` 实例

**异常:** `ConnectionError` - 未找到机器人或连接失败

### 实例方法

#### 连接管理

| 方法 | 返回类型 | 描述 |
|------|----------|------|
| `connect(timeout=5.0)` | `bool` | 连接到手机 |
| `disconnect()` | `None` | 断开连接 |

#### 电机控制

| 方法 | 参数 | 返回类型 | 描述 |
|------|------|----------|------|
| `drive(left, right)` | `float, float` | `bool` | 控制左右电机速度 (-1.0 到 1.0) |
| `forward(speed=0.5)` | `float` | `bool` | 前进 |
| `backward(speed=0.5)` | `float` | `bool` | 后退 |
| `turn_left(speed=0.5)` | `float` | `bool` | 原地左转 |
| `turn_right(speed=0.5)` | `float` | `bool` | 原地右转 |
| `stop()` | - | `bool` | 停止所有电机 |

#### 带持续时间的控制

| 方法 | 参数 | 返回类型 | 描述 |
|------|------|----------|------|
| `move_forward(speed=0.5, duration=1.0)` | `float, float` | `bool` | 前进指定时间后停止 |
| `move_backward(speed=0.5, duration=1.0)` | `float, float` | `bool` | 后退指定时间后停止 |
| `rotate_left(speed=0.5, duration=1.0)` | `float, float` | `bool` | 左转指定时间后停止 |
| `rotate_right(speed=0.5, duration=1.0)` | `float, float` | `bool` | 右转指定时间后停止 |
| `move(left, right, duration=1.0)` | `float, float, float` | `bool` | 双轮独立控制 |

#### 视频

| 方法 | 参数 | 返回类型 | 描述 |
|------|------|----------|------|
| `get_frame()` | - | `Optional[np.ndarray]` | 获取最新视频帧 |
| `start_video(display=True, callback=None)` | `bool, Callable` | `None` | 开始视频显示 |
| `stop_video()` | - | `None` | 停止视频显示 |
| `video_stream()` | - | `Generator` | 视频帧生成器 |

#### 传感器

| 方法 | 返回类型 | 描述 |
|------|----------|------|
| `get_sensors()` | `Dict[str, Any]` | 获取所有传感器数据 |
| `get_accelerometer()` | `Optional[Dict[str, float]]` | 获取加速度计数据 |
| `get_gyroscope()` | `Optional[Dict[str, float]]` | 获取陀螺仪数据 |

#### 数据采集

| 方法 | 参数 | 返回类型 | 描述 |
|------|------|----------|------|
| `start_recording(output_dir="./dataset")` | `str` | `None` | 开始数据采集 |
| `stop_recording()` | - | `None` | 停止数据采集 |

#### 实时控制

```python
realtime_control(base_speed: float = 0.7) -> None
```

启动实时键盘控制。按 ESC 退出。

**控制键:**
- W/S: 前进/后退
- A/D: 左转/右转
- Shift+A/D: 漂移急转
- +/-: 调速
- R: 切换录制
- ESC: 退出

### 属性

| 属性 | 类型 | 描述 |
|------|------|------|
| `connected` | `bool` | 是否已连接 |
| `motor` | `MotorController` | 电机控制器模块 |
| `video` | `VideoReceiver` | 视频接收器模块 |
| `sensors` | `SensorManager` | 传感器管理器模块 |
| `recorder` | `DataRecorder` | 数据采集器模块 |

### 使用示例

```python
# 方式 1: 上下文管理器（推荐）
with OpenBene("192.168.1.100") as bot:
    bot.forward(0.5)
    time.sleep(1)
    bot.stop()

# 方式 2: 自动发现
bot = OpenBene.auto_connect()
bot.move_forward(0.5, 2.0)  # 前进 2 秒
bot.disconnect()

# 方式 3: 直接访问模块
bot.motor.drive(0.3, 0.5)
frame = bot.video.get_frame()
accel = bot.sensors.get_accelerometer()
```

---

## WebSocketConnection

WebSocket 连接管理器，负责与手机 App 建立和维护连接。

### 导入

```python
from openbene import WebSocketConnection
```

### 构造函数

```python
WebSocketConnection(ip: str, port: int = 8765)
```

### 方法

| 方法 | 参数 | 返回类型 | 描述 |
|------|------|----------|------|
| `connect(timeout=5.0)` | `float` | `bool` | 连接到手机 |
| `disconnect()` | - | `None` | 断开连接 |
| `send(message)` | `dict` | `bool` | 发送消息 |
| `on_message(callback)` | `Callable` | `None` | 注册消息回调 |
| `remove_callback(callback)` | `Callable` | `None` | 移除回调 |

### 属性

| 属性 | 类型 | 描述 |
|------|------|------|
| `connected` | `bool` | 是否已连接 |
| `is_connected` | `bool` | 是否已连接（属性） |

---

## MQTTConnection

MQTT 连接管理器，支持智能家居设备通信。

### 导入

```python
from openbene import MQTTConnection, MQTTTopics
```

### 构造函数

```python
MQTTConnection(
    broker: str,
    port: int = 1883,
    client_id: str = None,
    username: str = None,
    password: str = None,
    keepalive: int = 60,
    use_tls: bool = False
)
```

**参数:**
- `broker`: MQTT Broker 地址
- `port`: 端口号（普通 1883，TLS 8883）
- `client_id`: 客户端 ID，None 时自动生成
- `username`: 用户名（可选）
- `password`: 密码（可选）
- `keepalive`: 心跳间隔（秒）
- `use_tls`: 是否使用 TLS 加密

### 方法

| 方法 | 参数 | 返回类型 | 描述 |
|------|------|----------|------|
| `connect(timeout=5.0)` | `float` | `bool` | 连接到 Broker |
| `disconnect()` | - | `None` | 断开连接 |
| `publish(topic, message, qos=0, retain=False)` | `str, dict, int, bool` | `bool` | 发布消息 |
| `subscribe(topic, qos=0, callback=None)` | `str, int, Callable` | `bool` | 订阅主题 |
| `unsubscribe(topic)` | `str` | `bool` | 取消订阅 |
| `on_message(callback)` | `Callable` | `None` | 注册全局回调 |
| `set_will(topic, message, qos=0, retain=False)` | `str, dict, int, bool` | `None` | 设置遗嘱消息 |

### 属性

| 属性 | 类型 | 描述 |
|------|------|------|
| `is_connected` | `bool` | 是否已连接 |
| `subscribed_topics` | `List[str]` | 已订阅的主题列表 |

### 使用示例

```python
from openbene import MQTTConnection, MQTTTopics

# 连接到 Broker
with MQTTConnection("test.mosquitto.org") as mqtt:
    # 订阅传感器数据
    mqtt.subscribe(MQTTTopics.sensors("bot1"), callback=handle_data)

    # 发布控制命令
    mqtt.publish(
        MQTTTopics.control("bot1"),
        {"cmd": "drive", "val": [0.5, 0.5]},
        qos=1
    )
```

---

## MotorController

电机控制器，负责发送电机控制命令。

### 导入

```python
from openbene import MotorController
```

### 方法

与 OpenBene 类的电机控制方法相同。

### 属性

| 属性 | 类型 | 描述 |
|------|------|------|
| `last_command` | `Tuple[str, List[float]]` | 最后发送的命令 |

---

## VideoReceiver

视频帧接收器，处理从手机 App 发来的视频帧。

### 导入

```python
from openbene import VideoReceiver
```

### 方法

| 方法 | 参数 | 返回类型 | 描述 |
|------|------|----------|------|
| `get_frame()` | - | `Optional[np.ndarray]` | 获取最新帧（BGR 格式） |
| `get_frame_bytes()` | - | `Optional[bytes]` | 获取原始 JPEG 字节 |
| `start_display(window_name="OpenBene Camera")` | `str` | `None` | 开始 OpenCV 显示 |
| `stop_display()` | - | `None` | 停止显示 |
| `stream()` | - | `Generator` | 视频帧生成器 |
| `set_callback(callback)` | `Callable` | `None` | 设置帧回调 |

### 属性

| 属性 | 类型 | 描述 |
|------|------|------|
| `has_frame` | `bool` | 是否有可用帧 |

---

## SensorManager

传感器管理器，接收和处理手机传感器数据。

### 导入

```python
from openbene import SensorManager
```

### 方法

| 方法 | 返回类型 | 描述 |
|------|----------|------|
| `get_all()` | `Dict[str, Any]` | 获取所有传感器数据 |
| `get_accelerometer()` | `Optional[Dict[str, float]]` | 获取加速度计 (m/s²) |
| `get_gyroscope()` | `Optional[Dict[str, float]]` | 获取陀螺仪 (rad/s) |
| `get_magnetometer()` | `Optional[Dict[str, float]]` | 获取磁力计 (µT) |
| `get_battery_level()` | `Optional[float]` | 获取电池电量 (0-100) |

### 属性

| 属性 | 类型 | 描述 |
|------|------|------|
| `has_data` | `bool` | 是否有传感器数据 |

---

## DataRecorder

数据采集器，录制训练数据（视频帧 + 传感器 + 控制命令）。

### 导入

```python
from openbene import DataRecorder
```

### 方法

| 方法 | 参数 | 返回类型 | 描述 |
|------|------|----------|------|
| `start(output_dir="./dataset")` | `str` | `None` | 开始数据采集 |
| `stop()` | - | `None` | 停止数据采集 |
| `set_command(cmd, values)` | `str, List[float]` | `None` | 设置当前控制命令 |

### 属性

| 属性 | 类型 | 描述 |
|------|------|------|
| `is_recording` | `bool` | 是否正在录制 |
| `frame_count` | `int` | 已录制的帧数 |

### 输出格式

```
output_dir/
├── images/
│   ├── 000001.jpg
│   └── ...
└── labels.csv
```

---

## DataLogger

灵活的数据记录器，支持图片或视频保存。相比 DataRecorder，提供更精确的时间戳和灵活的保存格式。

### 导入

```python
from openbene import DataLogger
```

### 构造函数

```python
DataLogger(
    video: VideoReceiver,
    sensors: SensorManager,
    save_format: str = 'images',
    fps: float = 30.0,
    codec: str = 'mp4v'
)
```

**参数:**
- `video`: 视频接收器实例
- `sensors`: 传感器管理器实例
- `save_format`: 保存格式，'images' 保存为 JPEG 图片，'video' 保存为 MP4 视频
- `fps`: 视频帧率（仅 video 模式有效），默认 30.0
- `codec`: 视频编码器（仅 video 模式有效），默认 'mp4v'

### 方法

| 方法 | 参数 | 返回类型 | 描述 |
|------|------|----------|------|
| `start(output_dir="./recordings")` | `str` | `None` | 开始录制 |
| `stop()` | - | `None` | 停止录制 |
| `set_command(cmd, values)` | `str, List[float]` | `None` | 设置当前控制命令 |

### 属性

| 属性 | 类型 | 描述 |
|------|------|------|
| `is_recording` | `bool` | 是否正在录制 |
| `frame_count` | `int` | 已录制的帧数 |
| `elapsed_time` | `float` | 已录制的时长（秒） |
| `save_format` | `str` | 保存格式 ('images' 或 'video') |

### 输出格式

**图片模式 (save_format='images')**:
```
output_dir/
├── images/
│   ├── 000001.jpg
│   ├── 000002.jpg
│   └── ...
└── sensor_data.csv
```

**视频模式 (save_format='video')**:
```
output_dir/
├── video.mp4
└── sensor_data.csv
```

### CSV 格式

**图片模式**:
```
frame_id,image_file,timestamp,relative_time,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,battery,command,speed_left,speed_right
```

**视频模式**:
```
frame_id,timestamp,relative_time,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,battery,command,speed_left,speed_right
```

- `frame_id`: 帧序号 (1, 2, 3...)
- `timestamp`: Unix 时间戳 (浮点秒)
- `relative_time`: 相对于开始的时间 (秒)
- `battery`: 电池百分比 (0-100)

### 使用示例

```python
from openbene import OpenBene, DataLogger

# 模式 1: 保存为图片
with OpenBene("192.168.1.100") as bot:
    logger = DataLogger(bot.video, bot.sensors, save_format='images')
    logger.start("./training_images")

    # 控制机器人
    bot.forward(0.5)
    time.sleep(2)
    bot.stop()

    logger.stop()

# 模式 2: 保存为视频
with OpenBene("192.168.1.100") as bot:
    logger = DataLogger(bot.video, bot.sensors, save_format='video', fps=30.0)
    logger.start("./training_video")

    # 控制机器人
    bot.forward(0.5)
    time.sleep(2)
    bot.stop()

    logger.stop()
```

---

## Discovery

UDP 发现服务，用于在局域网中查找 OpenBene 机器人。

### 导入

```python
from openbene import Discovery
```

### 构造函数

```python
Discovery(port: int = 12345)
```

### 方法

| 方法 | 参数 | 返回类型 | 描述 |
|------|------|----------|------|
| `start(on_discovery=None)` | `Callable` | `None` | 开始监听广播 |
| `stop()` | - | `None` | 停止发现服务 |

---

## ImageProcessor

图像处理器抽象基类，让学生可以方便地插入自己的 CV 算法。

### 导入

```python
from openbene import ImageProcessor, PassthroughProcessor
```

### 构造函数

```python
ImageProcessor(name: str = "ImageProcessor")
```

**参数:**
- `name`: 处理器名称，默认 "ImageProcessor"

### 抽象方法

#### `process(frame: np.ndarray) -> np.ndarray`

处理单帧图像（子类必须实现）。

**参数:**
- `frame`: BGR 格式的输入图像 (numpy.ndarray)

**返回:** 处理后的图像 (numpy.ndarray)

### 内置处理器

#### PassthroughProcessor

透传处理器，不做任何处理直接返回原图。

```python
processor = PassthroughProcessor()
output = processor.process(input_frame)  # output 与 input_frame 相同
```

### 使用示例

```python
from openbene import OpenBene, ImageProcessor
import cv2

# 自定义灰度图处理器
class GrayscaleProcessor(ImageProcessor):
    def __init__(self):
        super().__init__(name="Grayscale")

    def process(self, frame):
        return cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

# 使用处理器
with OpenBene("192.168.1.100") as bot:
    processor = GrayscaleProcessor()
    for frame in bot.video_stream():
        result = processor.process(frame)
        cv2.imshow("Processed", result)
        if cv2.waitKey(1) == ord('q'):
            break
```

### 高级示例

```python
# 边缘检测处理器
class EdgeDetectionProcessor(ImageProcessor):
    def __init__(self, low_threshold=50, high_threshold=150):
        super().__init__(name="EdgeDetection")
        self.low_threshold = low_threshold
        self.high_threshold = high_threshold

    def process(self, frame):
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        edges = cv2.Canny(gray, self.low_threshold, self.high_threshold)
        return edges

# 使用
processor = EdgeDetectionProcessor(low_threshold=100, high_threshold=200)
```

---

## MQTTTopics

MQTT 主题命名规范工具类。

### 导入

```python
from openbene import MQTTTopics
```

### 静态方法

| 方法 | 参数 | 返回格式 |
|------|------|----------|
| `control(device_id)` | `str` | `openbene/{device_id}/control` |
| `status(device_id)` | `str` | `openbene/{device_id}/status` |
| `sensors(device_id)` | `str` | `openbene/{device_id}/sensors` |
| `video(device_id)` | `str` | `openbene/{device_id}/video` |
| `lwt(device_id)` | `str` | `openbene/{device_id}/lwt` |
| `smarthome_set(room, device)` | `str, str` | `smarthome/{room}/{device}/set` |
| `smarthome_state(room, device)` | `str, str` | `smarthome/{room}/{device}/state` |

---

## 工厂函数

### openbot_rtr_tt

```python
openbot_rtr_tt(name: str = "OpenBot", ip: str = None, port: int = 8765) -> OpenBene
```

创建并连接到 RTR_TT 版本的 OpenBot（Arduino Nano, TT 电机）。

### openbot_rtr_520

```python
openbot_rtr_520(name: str = "OpenBot", ip: str = None, port: int = 8765) -> OpenBene
```

创建并连接到 RTR_520 版本的 OpenBot（ESP32, 520 电机）。

---

## 异常类

### ConnectionError

```python
from openbene import ConnectionError
```

WebSocket 连接失败时抛出。

### MQTTConnectionError

```python
from openbene import MQTTConnectionError
```

MQTT 连接失败时抛出。

---

## 依赖

**核心依赖:**
- `websockets>=10.0`
- `opencv-python>=4.5.0`
- `numpy>=1.19.0`
- `paho-mqtt>=1.6.0`

**可选依赖:**
- `[keyboard]`: pynput (键盘控制)
- `[vision]`: pillow (图像处理)
- `[dev]`: pytest, black, flake8, mypy

---

*Generated for OpenBene SDK v2.5.0*
