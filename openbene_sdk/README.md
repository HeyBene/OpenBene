# OpenBene SDK

![Python Version](https://img.shields.io/badge/python-3.8%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)

**Phone as Body, PC as Brain** - 用手机控制机器人，用PC运行AI算法。

OpenBene SDK 是一个 Python 库，让你可以：
- 通过 WebSocket 连接到手机 App
- 发送控制命令（前进、后退、转向）
- 接收实时视频流
- 获取传感器数据
- 采集训练数据

---

## 安装

```bash
pip install openbene
```

或从源码安装：

```bash
git clone https://github.com/yourusername/openbene.git
cd openbene/openbene_sdk
pip install -e .
```

**依赖：**
```bash
pip install websockets opencv-python numpy
```

---

## 快速开始

### 基础控制

```python
from openbene import OpenBene
import time

# 连接到手机（替换为你手机的IP）
bot = OpenBene("192.168.1.100")
bot.connect()

# 控制机器人
bot.forward(0.5)    # 前进
time.sleep(2)
bot.turn_left(0.3)  # 左转
time.sleep(1)
bot.stop()          # 停止

bot.disconnect()
```

### 使用上下文管理器

```python
with OpenBene("192.168.1.100") as bot:
    bot.forward(0.5)
    time.sleep(2)
    bot.stop()
```

### 视频显示

```python
with OpenBene("192.168.1.100") as bot:
    # 启动OpenCV窗口显示视频
    bot.start_video(display=True)

    # 按 'q' 退出
    while bot.connected:
        time.sleep(1)
```

### 获取传感器数据

```python
with OpenBene("192.168.1.100") as bot:
    sensors = bot.get_sensors()
    print(f"加速度: {sensors['accelerometer']}")
    print(f"陀螺仪: {sensors['gyroscope']}")
    print(f"电池: {sensors['battery_level']}")
```

### 数据采集（用于训练模型）

```python
with OpenBene("192.168.1.100") as bot:
    # 开始采集
    bot.start_recording(output_dir="./training_data")

    # 控制机器人，数据会自动记录
    bot.forward(0.5)
    time.sleep(5)
    bot.turn_left(0.3)
    time.sleep(2)

    # 停止采集
    bot.stop_recording()
```

**输出格式：**
```
training_data/
├── images/
│   ├── 000001.jpg
│   ├── 000002.jpg
│   └── ...
└── labels.csv
```

**labels.csv 内容：**
```csv
image,timestamp,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,command,speed_left,speed_right
000001.jpg,2024-01-05T10:30:00,0.1,0.2,9.8,0.0,0.0,0.0,forward,0.5,0.5
000002.jpg,2024-01-05T10:30:01,0.1,0.3,9.8,0.0,0.1,0.0,turn_left,0.3,-0.3
```

---

## API 参考

### 连接

| 方法 | 说明 |
|------|------|
| `OpenBene(ip, port=8765)` | 创建控制器实例 |
| `connect(timeout=5.0)` | 连接到手机 |
| `disconnect()` | 断开连接 |

### 控制

| 方法 | 说明 |
|------|------|
| `drive(left, right)` | 设置左右轮速度 (-1.0 到 1.0) |
| `forward(speed=0.5)` | 前进 |
| `backward(speed=0.5)` | 后退 |
| `turn_left(speed=0.5)` | 左转 |
| `turn_right(speed=0.5)` | 右转 |
| `stop()` | 停止 |

### 视频

| 方法 | 说明 |
|------|------|
| `start_video(display=True)` | 开始视频（可选OpenCV窗口） |
| `stop_video()` | 停止视频 |
| `get_frame()` | 获取最新帧 (numpy BGR) |

### 传感器

| 方法 | 说明 |
|------|------|
| `get_sensors()` | 获取所有传感器数据 |
| `get_accelerometer()` | 获取加速度计 (m/s²) |
| `get_gyroscope()` | 获取陀螺仪 (rad/s) |

### 数据采集

| 方法 | 说明 |
|------|------|
| `start_recording(output_dir)` | 开始采集数据 |
| `stop_recording()` | 停止采集 |

---

## 通信协议

### 连接方式

- **协议:** WebSocket
- **端口:** 8765
- **手机:** Server（等待连接）
- **PC:** Client（主动连接）

### 消息格式

**PC → 手机（控制命令）：**
```json
{"cmd": "drive", "val": [0.5, 0.5]}
{"cmd": "stop"}
```

**手机 → PC（视频帧）：**
```json
{
  "type": "video_frame",
  "data": "<base64编码的JPEG>",
  "timestamp": 1704441600000
}
```

**手机 → PC（传感器数据）：**
```json
{
  "type": "sensor_data",
  "data": {
    "accelerometer": {"x": 0.1, "y": 0.2, "z": 9.8},
    "gyroscope": {"x": 0.01, "y": -0.02, "z": 0.0},
    "battery_level": 0.85
  }
}
```

---

## 示例

查看 `examples/` 目录：

- **basic_control.py** - 基础控制示例
- **video_display.py** - 视频显示示例
- **data_collection.py** - 数据采集示例
- **autopilot.py** - 自动驾驶示例（颜色追踪）

---

## 使用流程

1. **手机端：** 打开 OpenBene App，点击 "Start Server"
2. **PC端：** 运行 Python 脚本，使用手机显示的 IP 地址连接
3. **控制：** 使用 SDK API 控制机器人

---

## License

MIT License
