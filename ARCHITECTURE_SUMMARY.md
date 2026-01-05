# OpenBene 统一架构设计总结

## 设计决策记录

基于讨论确定的设计决策：

| 决策项 | 选择 | 理由 |
|--------|------|------|
| PC端形态 | Python SDK库 | 用户通过写脚本调用，无需独立客户端软件 |
| 视频显示 | OpenCV窗口 | 简单直接，`cv2.imshow()` |
| 视频存储 | 默认不存储 | 大部分场景只需实时查看 |
| 数据采集 | 专用模式 | 训练模型时使用，输出images/+labels.csv |
| 连接模式 | 1对1 | 一台PC连接一个手机 |

---

## 核心架构

```
手机（WebSocket Server :8765） ←→ PC（Python SDK）

PC → 手机: {"cmd": "drive", "val": [0.5, 0.5]}
手机 → PC: {"type": "video_frame", "data": "<base64>"}
手机 → PC: {"type": "sensor_data", "data": {...}}
```

---

## SDK API 设计

### 基础使用

```python
from openbene import OpenBene

bot = OpenBene("192.168.1.100")
bot.connect()

# 控制
bot.forward(speed=0.5)
bot.backward(speed=0.5)
bot.turn_left(speed=0.3)
bot.turn_right(speed=0.3)
bot.stop()

# 视频（OpenCV窗口显示）
bot.start_video(display=True)
frame = bot.get_frame()        # numpy数组

# 传感器
sensors = bot.get_sensors()    # dict

bot.disconnect()
```

### 数据采集模式（用于训练模型）

```python
# 开始采集
bot.start_recording(output_dir="./dataset/")

# 控制机器人移动，自动记录数据
bot.forward(0.5)
time.sleep(2)
bot.turn_left(0.3)
# ...

# 停止采集
bot.stop_recording()
```

**输出格式：**

```
dataset/
├── images/
│   ├── 000001.jpg
│   ├── 000002.jpg
│   └── ...
└── labels.csv
```

**labels.csv内容：**

```csv
image,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,command,speed_left,speed_right
000001.jpg,0.1,0.2,9.8,0.0,0.0,0.0,forward,0.5,0.5
000002.jpg,0.1,0.3,9.8,0.0,0.1,0.0,turn_left,0.3,0.5
```

**特点：**
- 每行对应一张图片
- 图片和传感器数据已自动对齐
- 用户直接用于训练：`df = pd.read_csv("labels.csv")`

---

## 用户场景示例

### 场景1：手动控制 + 实时视频

```python
bot = OpenBene("192.168.1.100")
bot.connect()
bot.start_video(display=True)

bot.forward(0.5)
time.sleep(3)
bot.stop()

bot.disconnect()
```

### 场景2：采集数据 → 训练模型 → 自动驾驶

```python
# 步骤1: 采集数据
bot.start_recording("./training_data/")
# 手动控制机器人行驶...
bot.stop_recording()

# 步骤2: 训练模型（用户自己的代码）
import pandas as pd
df = pd.read_csv("./training_data/labels.csv")
# 训练...

# 步骤3: 使用模型自动驾驶
model = load_my_model()
while True:
    frame = bot.get_frame()
    action = model.predict(frame)
    bot._send_command('drive', action)
```

### 场景3：目标追踪（人/车/狗）

```python
import cv2

bot = OpenBene("192.168.1.100")
bot.connect()
bot.start_video(display=True)

detector = load_yolo()  # 用户的检测模型

while True:
    frame = bot.get_frame()
    if frame is None:
        continue

    detections = detector.detect(frame)

    if "person" in detections:
        person = detections["person"]
        if person.x < frame.shape[1] / 3:
            bot.turn_left(0.2)
        elif person.x > frame.shape[1] * 2 / 3:
            bot.turn_right(0.2)
        else:
            bot.forward(0.3)
    else:
        bot.stop()

    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

bot.disconnect()
```

---

## 文件结构

### PC SDK (openbene_sdk/)

```
openbene_sdk/
├── src/
│   ├── __init__.py
│   ├── openbene.py          # 主类
│   ├── connection.py        # WebSocket连接
│   ├── video.py             # 视频处理
│   ├── recording.py         # 数据采集
│   └── utils.py             # 工具函数
│
├── examples/
│   ├── basic_control.py     # 基础控制
│   ├── video_display.py     # 视频显示
│   ├── data_collection.py   # 数据采集
│   └── autopilot.py         # 自动驾驶示例
│
├── setup.py
└── README.md
```

### 手机App (openbene_app/)

```
openbene_app/lib/
├── main.dart
├── models/
│   ├── sensor_data.dart
│   └── connection_state.dart
├── services/
│   ├── hardware/
│   │   ├── usb_controller.dart
│   │   ├── camera_service.dart
│   │   └── sensor_service.dart
│   └── network/
│       ├── websocket_server.dart
│       └── protocol_handler.dart
├── screens/
│   ├── home_screen.dart
│   └── status_screen.dart
└── widgets/
    ├── sensor_dashboard.dart
    └── command_log.dart
```

---

## 技术参数

| 参数 | 值 |
|------|------|
| 通信协议 | WebSocket (ws://) |
| 端口 | 8765 |
| 视频分辨率 | 640x480 |
| 视频编码 | JPEG + Base64 |
| 视频帧率 | 15-30 fps |
| 传感器采样率 | 10 Hz (100ms) |
| 预计带宽 | < 1 Mbps |

---

## 相关文档

- [ARCHITECTURE_REDESIGN_PLAN.md](ARCHITECTURE_REDESIGN_PLAN.md) - 完整架构设计方案
- [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) - 项目背景

---

## 下一步

1. 确认此架构设计
2. 开始实施阶段1：清理代码
3. 实施阶段2：重构手机App
4. 实施阶段3：重构PC SDK
5. 集成测试
