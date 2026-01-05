# OpenBene 架构重新设计方案

## 📋 执行摘要

### 当前问题分析

1. **架构混乱**：
   - `openbot-mobile-control` App：手机作为**客户端**，连接到PC的WebSocket服务器，仅发送视频和传感器，**无法接收控制指令**
   - `openbene_app` + `openbene_sdk`：手机作为**服务器**，PC连接到手机，可以控制但无视频和传感器
   - 两个架构方向相反，无法直接整合

2. **功能缺失**：
   - `openbot-mobile-control`：连接后只能查看数据，PC无法控制机器人
   - `openbene_app`：基础但缺少视频流和传感器数据显示

3. **协议不一致**：
   - `openbot-mobile-control`：WebSocket + JSON，手机→PC单向数据流
   - `openbene_app`：TCP + JSON，PC→手机双向控制

4. **用户需求**：
   - ✅ 手机USB连接硬件小车
   - ✅ 手机WiFi连接PC
   - ✅ PC→手机：发送运动控制指令
   - ✅ 手机→PC：回传视频流和传感器数据
   - ✅ 手机UI：显示连接状态、指令、数据
   - ✅ PC SDK：支持用户DIY扩展
   - ✅ 开源架构：低耦合、易扩展

---

## 🎯 整改方案总体设计

### 核心理念

**"Phone as Body, PC as Brain"**

- **手机 = 躯体**：负责硬件I/O（USB控制小车、采集传感器/视频）
- **PC = 大脑**：负责高级逻辑（AI算法、计算机视觉、路径规划）

### 最终架构

```
┌─────────────────────────────────────────────────────────────┐
│                     统一的OpenBene生态                        │
└─────────────────────────────────────────────────────────────┘

         手机端（Android）              PC端（Python）
    ┌──────────────────────┐      ┌────────────────────┐
    │   OpenBene App       │      │  OpenBene SDK      │
    │  (Flutter/Dart)      │      │  (Python 3.8+)     │
    └──────────────────────┘      └────────────────────┘
             │                              │
             │  WebSocket (双向通信)        │
             │  ws://手机IP:8765            │
             │                              │
             │◄─────────────────────────────┤
             │  1. PC发送控制指令           │
             │     {"cmd": "drive", ...}    │
             │                              │
             ├─────────────────────────────►│
             │  2. 手机回传数据             │
             │     - 视频流 (JPEG/Base64)   │
             │     - 传感器 (JSON)          │
             │     - 心跳 (ping/pong)       │
             │                              │
             ▼                              ▲
    ┌──────────────────────┐       用户Python脚本
    │   硬件层（USB OTG）   │       ┌───────────────┐
    │   - Arduino控制器    │       │ from openbene │
    │   - 电机驱动         │       │ bot = ...     │
    │   - 传感器          │       │ bot.forward() │
    │   - 摄像头          │       │ frame = ...   │
    └──────────────────────┘       └───────────────┘
```

---

## 📱 手机端App架构设计

### 1. 职责定义

| 模块 | 职责 | 实现方式 |
|------|------|----------|
| **硬件控制** | USB连接Arduino，发送PWM指令 | `usb_serial` package |
| **传感器采集** | 读取加速度、陀螺仪、电池、磁力计 | `sensors_plus`, `battery_plus` |
| **视频采集** | 相机拍摄，编码为JPEG | `camera` package |
| **WebSocket服务器** | 监听8765端口，接收PC指令，发送数据 | `web_socket_channel` |
| **UI显示** | 连接状态、数据统计、控制日志 | Flutter Material Design |

### 2. 文件结构

```
openbene_app/
├── lib/
│   ├── main.dart                          # App入口
│   │
│   ├── models/                            # 数据模型层
│   │   ├── sensor_data.dart              # 传感器数据模型
│   │   ├── connection_state.dart         # 连接状态模型
│   │   └── control_command.dart          # 控制指令模型
│   │
│   ├── services/                          # 服务层（核心业务逻辑）
│   │   ├── hardware/                     # 硬件层
│   │   │   ├── usb_controller.dart      # USB串口控制
│   │   │   ├── camera_service.dart      # 相机采集
│   │   │   └── sensor_service.dart      # 传感器读取
│   │   │
│   │   ├── network/                      # 网络层
│   │   │   ├── websocket_server.dart    # WebSocket服务器
│   │   │   └── protocol_handler.dart    # 协议解析
│   │   │
│   │   └── app_state.dart               # 全局状态管理
│   │
│   ├── screens/                          # UI界面层
│   │   ├── home_screen.dart             # 主界面（启动/停止）
│   │   ├── status_screen.dart           # 状态监控界面
│   │   └── settings_screen.dart         # 设置界面
│   │
│   └── widgets/                          # 可复用组件
│       ├── connection_indicator.dart     # 连接状态指示器
│       ├── sensor_dashboard.dart         # 传感器仪表盘
│       └── command_log.dart             # 指令日志
│
├── pubspec.yaml                          # 依赖配置
└── android/                             # Android配置（权限、USB）
```

### 3. 关键技术点

#### A. WebSocket服务器（手机端）

**监听PC连接，双向通信**

```dart
class WebSocketServer {
  ServerSocket? _serverSocket;
  WebSocket? _client;

  Future<void> start(int port) async {
    _serverSocket = await ServerSocket.bind('0.0.0.0', port);
    _serverSocket!.listen((socket) async {
      _client = await WebSocketTransformer.upgrade(socket);
      _handleClient(_client!);
    });
  }

  void _handleClient(WebSocket ws) {
    ws.listen((message) {
      // 接收PC发来的控制指令
      final data = jsonDecode(message);
      if (data['cmd'] == 'drive') {
        _usbController.drive(data['val'][0], data['val'][1]);
      }
    });
  }

  void sendVideoFrame(Uint8List jpegData) {
    if (_client != null) {
      _client!.add(jsonEncode({
        'type': 'video_frame',
        'data': base64Encode(jpegData),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      }));
    }
  }
}
```

#### B. USB控制器

**发送PWM指令到Arduino**

```dart
class UsbController {
  UsbPort? _port;

  Future<void> connect() async {
    final devices = await UsbSerial.listDevices();
    _port = await devices.first.create();
    await _port!.open();
    await _port!.setDTR(true);
    await _port!.setRTS(true);
  }

  void drive(double left, double right) {
    int leftPWM = (left * 255).clamp(-255, 255).toInt();
    int rightPWM = (right * 255).clamp(-255, 255).toInt();
    String command = 'c$leftPWM,$rightPWM\n';
    _port!.write(Uint8List.fromList(command.codeUnits));
  }
}
```

#### C. 相机采集

**实时编码为JPEG发送**

```dart
class CameraService {
  CameraController? _controller;

  Future<void> startStreaming(Function(Uint8List) onFrame) async {
    await _controller!.startImageStream((CameraImage image) async {
      final jpeg = await _convertToJpeg(image);
      onFrame(jpeg);
    });
  }
}
```

---

## 🖥️ PC端SDK架构设计

### 1. 职责定义

| 模块 | 职责 | 实现方式 |
|------|------|----------|
| **连接管理** | 发现手机、建立WebSocket连接 | `websockets` library |
| **命令发送** | 封装高级API（如`move_forward()`） | Python类方法 |
| **数据接收** | 接收视频流、传感器数据 | 异步回调 |
| **扩展接口** | 提供钩子函数，支持用户DIY | 装饰器、回调 |

### 2. 文件结构

```
openbene_sdk/
├── src/
│   ├── __init__.py                    # 包入口，导出主要类
│   ├── openbene.py                    # 主控制类
│   ├── discovery.py                   # 设备发现
│   ├── protocol.py                    # 协议定义
│   └── extensions/                    # 扩展模块（插件化）
│       ├── __init__.py
│       ├── vision.py                 # 计算机视觉扩展
│       └── mapping.py                # 地图构建扩展
│
├── examples/                          # 示例脚本
│   ├── basic_control.py              # 基础控制
│   ├── video_stream.py               # 视频流处理
│   ├── autonomous_drive.py           # 自主驾驶
│   └── custom_extension.py           # 自定义扩展示例
│
├── setup.py                          # 安装配置
├── README.md                         # 文档
└── tests/                            # 单元测试
```

### 3. 核心API设计

#### A. 主类设计

```python
class OpenBene:
    """OpenBene机器人控制器"""

    def __init__(self, ip: str, port: int = 8765):
        self.ip = ip
        self.port = port
        self.ws = None
        self._extensions = []

    async def connect(self):
        """连接到手机WebSocket服务器"""
        uri = f"ws://{self.ip}:{self.port}"
        self.ws = await websockets.connect(uri)
        asyncio.create_task(self._receive_loop())

    async def _receive_loop(self):
        """接收数据循环"""
        async for message in self.ws:
            data = json.loads(message)
            if data['type'] == 'video_frame':
                self._handle_video_frame(data)
            elif data['type'] == 'sensor_data':
                self._handle_sensor_data(data)

    # ========== 控制API ==========

    def forward(self, speed: float = 0.5):
        """向前移动"""
        self._send_command('drive', [speed, speed])

    def backward(self, speed: float = 0.5):
        """向后移动"""
        self._send_command('drive', [-speed, -speed])

    def turn_left(self, speed: float = 0.5):
        """左转"""
        self._send_command('drive', [-speed, speed])

    def turn_right(self, speed: float = 0.5):
        """右转"""
        self._send_command('drive', [speed, -speed])

    def stop(self):
        """停止"""
        self._send_command('stop')

    # ========== 视频API ==========

    def start_video(self, display: bool = True):
        """
        开始接收视频流

        Args:
            display: 是否在OpenCV窗口中显示视频
        """
        self._video_display = display
        self._video_running = True

    def stop_video(self):
        """停止视频流"""
        self._video_running = False
        cv2.destroyAllWindows()

    def get_frame(self) -> np.ndarray:
        """获取最新视频帧（OpenCV格式，numpy数组）"""
        return self._latest_frame

    # ========== 传感器API ==========

    def get_sensors(self) -> dict:
        """
        获取最新传感器数据

        Returns:
            dict: {
                'accel': {'x': float, 'y': float, 'z': float},
                'gyro': {'x': float, 'y': float, 'z': float},
                'battery': int  # 0-100
            }
        """
        return self._latest_sensor

    # ========== 数据采集API ==========

    def start_recording(self, output_dir: str = "./dataset/",
                        video: bool = True, sensors: bool = True):
        """
        开始数据采集模式（用于训练模型）

        Args:
            output_dir: 输出目录
            video: 是否采集视频帧
            sensors: 是否采集传感器数据

        输出格式:
            dataset/
            ├── images/
            │   ├── 000001.jpg
            │   ├── 000002.jpg
            │   └── ...
            └── labels.csv

        labels.csv格式:
            image,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,command,speed_left,speed_right
            000001.jpg,0.1,0.2,9.8,0.0,0.0,0.0,forward,0.5,0.5
        """
        self._recording = True
        self._output_dir = output_dir
        self._record_video = video
        self._record_sensors = sensors
        self._frame_counter = 0
        self._labels = []

        # 创建输出目录
        os.makedirs(f"{output_dir}/images", exist_ok=True)

    def stop_recording(self):
        """
        停止数据采集并保存labels.csv
        """
        self._recording = False

        # 保存labels.csv
        import csv
        with open(f"{self._output_dir}/labels.csv", 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['image', 'accel_x', 'accel_y', 'accel_z',
                           'gyro_x', 'gyro_y', 'gyro_z',
                           'command', 'speed_left', 'speed_right'])
            writer.writerows(self._labels)

        print(f"Dataset saved to {self._output_dir}")
        print(f"  - Images: {self._frame_counter}")
        print(f"  - Labels: labels.csv")

    # ========== 回调API ==========

    def on_frame(self, callback: Callable):
        """注册视频帧回调"""
        self._frame_callback = callback

    def on_sensor(self, callback: Callable):
        """注册传感器回调"""
        self._sensor_callback = callback

    # ========== 扩展API ==========

    def register_extension(self, extension):
        """注册扩展模块"""
        self._extensions.append(extension)
        extension.attach(self)
```

#### B. 扩展插件系统

**设计理念**：用户可以编写自己的扩展模块，挂载到SDK上

```python
# openbene_sdk/src/extensions/base.py
class Extension:
    """扩展基类"""
    def attach(self, bot: 'OpenBene'):
        self.bot = bot

    def on_frame(self, frame: np.ndarray):
        """处理视频帧"""
        pass

    def on_sensor(self, data: dict):
        """处理传感器数据"""
        pass

# 用户自定义扩展示例
class ObjectDetectionExtension(Extension):
    """物体检测扩展"""
    def __init__(self):
        self.model = load_yolo_model()

    def on_frame(self, frame):
        detections = self.model.detect(frame)
        if 'person' in detections:
            self.bot.stop()  # 检测到人，停车

# 使用方式
bot = OpenBene('192.168.1.100')
bot.register_extension(ObjectDetectionExtension())
bot.connect()
```

#### C. 使用示例

**基础控制**
```python
from openbene import OpenBene

# 连接机器人
bot = OpenBene("192.168.1.100")
bot.connect()

# 基础控制
bot.forward(speed=0.5)
time.sleep(2)
bot.turn_left(speed=0.3)
time.sleep(1)
bot.stop()

# 断开连接
bot.disconnect()
```

**实时视频显示（OpenCV窗口）**
```python
from openbene import OpenBene

bot = OpenBene("192.168.1.100")
bot.connect()

# 开启视频显示
bot.start_video(display=True)

# 主循环
while True:
    frame = bot.get_frame()
    if frame is not None:
        # 用户可以在这里处理帧，比如目标检测
        # detections = my_model.detect(frame)
        pass

    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

bot.stop_video()
bot.disconnect()
```

**数据采集（用于训练模型）**
```python
from openbene import OpenBene

bot = OpenBene("192.168.1.100")
bot.connect()

# 开始数据采集
bot.start_recording(output_dir="./my_dataset/")

# 采集过程：手动或自动控制机器人
print("开始采集数据，按Ctrl+C停止...")
try:
    while True:
        # 控制机器人移动，同时自动记录图像和传感器
        bot.forward(0.3)
        time.sleep(0.5)
        bot.turn_right(0.2)
        time.sleep(0.3)
except KeyboardInterrupt:
    pass

# 停止采集，自动保存labels.csv
bot.stop_recording()
bot.disconnect()

# 输出结果:
# my_dataset/
# ├── images/
# │   ├── 000001.jpg
# │   ├── 000002.jpg
# │   └── ...
# └── labels.csv
```

**使用训练好的模型进行自动驾驶**
```python
from openbene import OpenBene
import torch

bot = OpenBene("192.168.1.100")
bot.connect()

# 加载用户训练好的模型
model = torch.load("my_autopilot_model.pth")
model.eval()

bot.start_video(display=True)

while True:
    frame = bot.get_frame()
    sensors = bot.get_sensors()

    if frame is not None:
        # 模型预测控制指令
        prediction = model.predict(frame, sensors)
        left_speed, right_speed = prediction

        # 执行控制
        bot._send_command('drive', [left_speed, right_speed])

    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

bot.stop()
bot.disconnect()
```

---

## 🔗 通信协议规范

### WebSocket协议（Port 8765）

#### 1. PC → 手机（控制指令）

**驱动指令**
```json
{
  "cmd": "drive",
  "val": [0.5, 0.5]  // [左轮速度, 右轮速度] -1.0~1.0
}
```

**停止指令**
```json
{
  "cmd": "stop"
}
```

**心跳（可选）**
```json
{
  "type": "ping",
  "timestamp": 1704441600000
}
```

#### 2. 手机 → PC（数据回传）

**视频帧**
```json
{
  "type": "video_frame",
  "data": "<base64编码的JPEG>",
  "timestamp": 1704441600000,
  "width": 640,
  "height": 480
}
```

**传感器数据**
```json
{
  "type": "sensor_data",
  "data": {
    "accelerometer": {"x": 0.1, "y": 0.2, "z": 9.8},
    "gyroscope": {"x": 0.01, "y": -0.02, "z": 0.0},
    "magnetometer": {"x": 20.5, "y": -10.3, "z": 45.2},
    "battery_level": 0.85,
    "timestamp": "2024-01-05T10:30:00.000Z"
  }
}
```

**心跳响应**
```json
{
  "type": "pong",
  "timestamp": 1704441600000
}
```

**状态更新**
```json
{
  "type": "status",
  "connected": true,
  "usb_connected": true,
  "camera_active": true
}
```

---

## 📊 UI设计规范

### 手机端App界面

#### 主界面（Home Screen）
```
┌─────────────────────────────────┐
│  🤖 OpenBene                    │
│                                 │
│  ┌───────────────────────────┐  │
│  │   连接状态                │  │
│  │   ● 已连接到PC           │  │
│  │   IP: 192.168.1.100       │  │
│  │   ● USB: Arduino已连接    │  │
│  │   ● 相机: 运行中          │  │
│  └───────────────────────────┘  │
│                                 │
│  [    启动WebSocket服务器    ]  │
│  [       停止服务器          ]  │
│                                 │
│  ┌───────────────────────────┐  │
│  │   数据统计                │  │
│  │   📹 视频帧: 1234         │  │
│  │   📊 传感器: 5678         │  │
│  │   ⚡ 电池: 85%           │  │
│  └───────────────────────────┘  │
│                                 │
│  [      查看详细数据        ]  │
│  [        设置             ]  │
└─────────────────────────────────┘
```

#### 状态界面（Status Screen）
```
┌─────────────────────────────────┐
│  ← 返回                         │
│                                 │
│  📊 传感器数据                  │
│  ┌───────────────────────────┐  │
│  │ 加速度计                  │  │
│  │  X: 0.12 m/s²            │  │
│  │  Y: -0.34 m/s²           │  │
│  │  Z: 9.81 m/s²            │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │ 最近指令                  │  │
│  │  10:30:45 drive(0.5,0.5) │  │
│  │  10:30:50 stop()         │  │
│  │  10:30:55 drive(0.3,0.7) │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
```

### PC端示例UI（可选）

用户可以用Tkinter/PyQt编写PC端GUI，SDK提供数据接口

```python
import tkinter as tk
from openbene import OpenBene

class RobotControlGUI:
    def __init__(self):
        self.root = tk.Tk()
        self.bot = OpenBene('192.168.1.100')

        # 视频显示区域
        self.video_canvas = tk.Canvas(width=640, height=480)

        # 控制按钮
        tk.Button(text="Forward", command=lambda: self.bot.move_forward()).pack()

        # 传感器数据显示
        self.sensor_label = tk.Label(text="Battery: --")

        # 注册回调
        self.bot.on_frame(self.update_video)
        self.bot.on_sensor(self.update_sensor)
```

---

## 🔧 实施计划

### 阶段1：清理与准备（1-2天）

1. **删除冗余代码**
   - 删除 `openbene_app/` 中的 `main.dart`、`network_service.dart`（之前合并的错误版本）
   - 保留 `usb_controller.dart` 作为参考

2. **保留核心资源**
   - `openbot-mobile-control/` 的UI组件（`sensor_dashboard.dart`等）
   - `openbene_sdk/` 的所有代码

### 阶段2：手机App重构（3-5天）

#### 任务清单

- [ ] **创建新的App结构**（参考上面的文件结构）
- [ ] **实现WebSocket服务器**（监听8765端口）
- [ ] **整合USB控制器**（从`openbene_app`移植）
- [ ] **整合相机服务**（从`openbot-mobile-control`移植）
- [ ] **整合传感器服务**（从`openbot-mobile-control`移植）
- [ ] **协议处理器**（接收PC指令，发送数据）
- [ ] **UI界面**（主界面、状态界面）
- [ ] **测试**（USB连接、WebSocket通信）

#### 关键代码文件

| 文件 | 来源 | 需要修改 |
|------|------|----------|
| `usb_controller.dart` | openbene_app | ✅ 保持不变 |
| `camera_service.dart` | openbot-mobile-control | ✅ 保持不变 |
| `sensor_service.dart` | openbot-mobile-control | ✅ 保持不变 |
| `websocket_server.dart` | **新建** | ⚠️ 重点开发 |
| `protocol_handler.dart` | **新建** | ⚠️ 重点开发 |
| `main.dart` | **重写** | ⚠️ 全新UI |

### 阶段3：PC SDK重构（2-3天）

#### 任务清单

- [ ] **修改`openbene.py`**（从PC作为服务器改为PC作为客户端）
- [ ] **实现WebSocket客户端**（连接到手机8765端口）
- [ ] **视频流解码**（base64 → JPEG → OpenCV格式）
- [ ] **传感器数据解析**
- [ ] **扩展系统设计**（Extension基类）
- [ ] **示例代码**（basic_control.py, video_stream.py等）
- [ ] **文档更新**（README.md, API文档）

#### 关键修改

```python
# 之前：PC作为客户端连接到手机TCP服务器（错误）
# 现在：PC作为客户端连接到手机WebSocket服务器（正确）

class OpenBene:
    async def connect(self):
        # 连接到手机的WebSocket服务器
        uri = f"ws://{self.ip}:{self.port}"
        self.ws = await websockets.connect(uri)

    async def _send_command(self, cmd, val=None):
        # 发送控制指令到手机
        message = {'cmd': cmd}
        if val:
            message['val'] = val
        await self.ws.send(json.dumps(message))
```

### 阶段4：集成测试（1-2天）

- [ ] **连接测试**：手机启动服务器，PC连接成功
- [ ] **控制测试**：PC发送指令，手机驱动小车
- [ ] **视频测试**：PC接收视频流，实时显示
- [ ] **传感器测试**：PC接收传感器数据
- [ ] **扩展测试**：验证插件系统可用
- [ ] **压力测试**：长时间运行稳定性

### 阶段5：文档与示例（1天）

- [ ] **用户手册**（如何安装、使用）
- [ ] **API文档**（SDK所有方法）
- [ ] **示例代码**（5-10个常见场景）
- [ ] **开发者指南**（如何编写扩展）
- [ ] **故障排查**（常见问题FAQ）

---

## 📦 最终交付物

### 1. 代码仓库结构

```
OpenBene/
├── openbene_app/                  # 手机App（Flutter）
│   ├── lib/
│   ├── android/
│   ├── pubspec.yaml
│   └── README.md
│
├── openbene_sdk/                  # PC SDK（Python）
│   ├── src/
│   ├── examples/
│   ├── tests/
│   ├── setup.py
│   └── README.md
│
├── docs/                          # 文档
│   ├── USER_GUIDE.md             # 用户手册
│   ├── API_REFERENCE.md          # API文档
│   ├── PROTOCOL.md               # 协议规范
│   └── EXTENSION_GUIDE.md        # 扩展开发指南
│
├── tools/                         # 工具脚本
│   ├── install_app.bat           # 自动安装App
│   └── test_connection.py        # 连接测试工具
│
└── README.md                      # 项目总README
```

### 2. 关键文档

#### A. 用户手册（USER_GUIDE.md）
- 硬件准备
- App安装步骤
- SDK安装步骤
- 首次连接教程
- 示例代码讲解

#### B. API文档（API_REFERENCE.md）
- `OpenBene` 类完整API
- 扩展系统API
- 回调函数规范
- 异常处理

#### C. 协议文档（PROTOCOL.md）
- WebSocket消息格式
- 指令列表
- 数据格式
- 错误码

#### D. 扩展开发指南（EXTENSION_GUIDE.md）
- Extension基类说明
- 示例扩展（目标检测）
- 最佳实践
- 性能优化建议

---

## 🎯 扩展性设计

### 1. 用户DIY场景示例

#### 场景A：添加语音控制

```python
from openbene import OpenBene
from openbene.extensions import Extension
import speech_recognition as sr

class VoiceControlExtension(Extension):
    def __init__(self):
        self.recognizer = sr.Recognizer()

    def attach(self, bot):
        super().attach(bot)
        self.listen_thread = Thread(target=self._listen_loop)
        self.listen_thread.start()

    def _listen_loop(self):
        with sr.Microphone() as source:
            while True:
                audio = self.recognizer.listen(source)
                command = self.recognizer.recognize_google(audio)

                if '前进' in command:
                    self.bot.move_forward()
                elif '停止' in command:
                    self.bot.stop()

# 使用
bot = OpenBene('192.168.1.100')
bot.register_extension(VoiceControlExtension())
```

#### 场景B：自动避障

```python
from openbene.extensions import Extension
import cv2

class ObstacleAvoidanceExtension(Extension):
    def on_frame(self, frame):
        # 使用深度估计检测障碍物
        depth = self.estimate_depth(frame)

        if depth.min() < 0.5:  # 障碍物距离<0.5m
            self.bot.stop()
            self.bot.turn_left(0.5)
            time.sleep(1)
```

#### 场景C：路径记录与重放

```python
class PathRecorderExtension(Extension):
    def __init__(self):
        self.path = []

    def on_sensor(self, data):
        # 记录位置（基于IMU积分）
        self.path.append({
            'timestamp': time.time(),
            'accel': data['accelerometer'],
            'gyro': data['gyroscope']
        })

    def replay(self):
        # 重放路径
        for point in self.path:
            # 根据记录的运动重现
            pass
```

### 2. 插件市场（未来）

可以建立一个插件仓库，用户分享自己的扩展：

```bash
# 安装第三方扩展
pip install openbene-extension-slam  # SLAM建图
pip install openbene-extension-gesture  # 手势识别
pip install openbene-extension-follow  # 人员跟随
```

---

## ⚠️ 风险与注意事项

### 1. 技术风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| WebSocket连接不稳定 | 控制延迟 | 添加重连机制、心跳检测 |
| 视频流带宽占用高 | WiFi卡顿 | 支持压缩质量调节、分辨率选择 |
| 传感器频率过高 | 手机性能消耗 | 限制采样率（如100ms/次） |
| USB连接不稳定 | 小车失控 | 超时自动停车保护 |

### 2. 兼容性

- **Android版本**：最低支持Android 7.0（API 24）
- **Python版本**：3.8+（使用async/await语法）
- **网络要求**：2.4GHz WiFi（5GHz可能存在兼容问题）

### 3. 性能优化

- **视频流**：
  - 默认640x480分辨率
  - JPEG质量75%
  - 最大30fps

- **传感器**：
  - 采样率100ms（10Hz）
  - 批量发送（每100ms一次）

- **指令响应**：
  - 目标延迟<50ms
  - WebSocket直接传输，无缓冲

---

## 📈 后续迭代计划

### 版本规划

- **v1.0**（当前重构目标）：基础通信 + 控制 + 视频 + 传感器
- **v1.5**：添加SLAM建图、目标检测
- **v2.0**：自主导航、路径规划
- **v2.5**：多机器人协同
- **v3.0**：云端控制、远程监控

---

## 🤝 团队协作建议

### 分工

1. **你**：整体架构设计、PC SDK开发、测试
2. **同事**：Flutter App开发、UI设计
3. **协作方式**：
   - 使用Git分支开发
   - 每天sync进度
   - 协议由你定义，双方遵守

### Git工作流

```bash
# 主分支
main          # 稳定版本

# 开发分支
dev/app       # 同事开发App
dev/sdk       # 你开发SDK

# 功能分支
feature/websocket-server
feature/usb-control
feature/extension-system

# 合并策略
feature/* -> dev/* -> main
```

---

## ✅ 成功标准

### 最小可行产品（MVP）

用户能够：
1. ✅ 在手机上启动App，连接USB小车
2. ✅ 在PC上运行Python脚本，连接到手机
3. ✅ 通过`bot.move_forward()`控制小车移动
4. ✅ 在PC上接收并显示手机摄像头视频
5. ✅ 读取传感器数据（加速度、电池等）
6. ✅ 手机UI显示连接状态和数据统计
7. ✅ 编写一个简单的扩展模块（如自动停车）

### 验收测试案例

```python
# 测试脚本：test_mvp.py

from openbene import OpenBene
import cv2

# 1. 自动发现并连接
bot = OpenBene.connect_auto()
assert bot.is_connected()

# 2. 控制测试
bot.move_forward(0.5)
time.sleep(2)
bot.stop()

# 3. 视频流测试
frame = bot.get_latest_frame()
assert frame is not None
cv2.imshow('Video', frame)

# 4. 传感器测试
sensor = bot.get_sensor_data()
assert 'battery_level' in sensor
print(f"Battery: {sensor['battery_level']*100}%")

# 5. 扩展测试
class TestExtension(Extension):
    def on_frame(self, frame):
        print(f"Frame shape: {frame.shape}")

bot.register_extension(TestExtension())

print("✅ All tests passed!")
```

---

## 📞 总结

这个架构设计方案：

1. **解决了当前问题**：统一架构，手机作为WebSocket服务器，PC作为客户端
2. **满足所有需求**：双向通信、视频流、传感器、控制、UI显示
3. **保持低耦合**：清晰的分层架构，模块独立
4. **支持扩展**：Extension插件系统，用户可DIY
5. **开源友好**：清晰的文档、示例、API

### 下一步行动

1. **确认方案**：你review这个设计，提出修改意见
2. **开始实施**：我帮你重构代码
3. **并行开发**：你做SDK，同事做App
4. **集成测试**：联调验证
5. **发布v1.0**：打包发布

你觉得这个方案如何？有什么需要调整的地方吗？
