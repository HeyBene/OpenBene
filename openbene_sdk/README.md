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

## 目录

- [安装](#安装)
- [零基础快速上手](#零基础快速上手)
- [功能详解](#功能详解)
- [API 参考](#api-参考)
- [示例代码](#示例代码)
- [常见问题](#常见问题)

---

## 安装

### 方式1：pip 安装（推荐）

```bash
pip install openbene
```

### 方式2：从源码安装

```bash
git clone https://github.com/HeyBene/OpenBene.git
cd OpenBene/openbene_sdk
pip install -e .
```

### 依赖库

SDK 会自动安装依赖，如需手动安装：

```bash
pip install websockets opencv-python numpy pynput
```

---

## 零基础快速上手

### 第一步：准备工作

1. **硬件准备**
   - OpenBot 机器人（已组装）
   - 安卓手机（安装 OpenBene App）
   - 电脑（安装 Python 3.8+）

2. **网络连接**
   - 确保手机和电脑连接到**同一个 WiFi 网络**

3. **启动手机 App**
   - 打开 OpenBene App
   - 点击 "Start Server"
   - 记下屏幕上显示的 **IP 地址**（如 `192.168.1.100`）

### 第二步：测试连接

打开电脑的命令行（终端），进入 SDK 目录：

```bash
cd OpenBene/openbene_sdk
```

启动 Python：

```bash
python
```

输入以下代码测试连接（将 IP 替换为你手机显示的地址）：

```python
from openbene import OpenBene

# 创建连接（替换为你的手机 IP）
bot = OpenBene("192.168.1.100")

# 连接到手机
bot.connect()

# 如果看到 "已连接" 说明成功了！
print(bot.connected)  # 应该输出 True
```

### 第三步：控制机器人移动

```python
# 前进 2 秒
bot.forward(0.5)
import time
time.sleep(2)

# 停止
bot.stop()

# 左转 1 秒
bot.turn_left(0.5)
time.sleep(1)
bot.stop()

# 断开连接
bot.disconnect()
```

### 第四步：实时键盘控制（推荐）

这是最直观的控制方式，像玩游戏一样用键盘控制机器人：

```python
from openbene import OpenBene

bot = OpenBene("192.168.1.100")
bot.connect()

# 启动实时控制
bot.realtime_control()
```

**键盘操作：**

| 按键 | 功能 |
|------|------|
| `W` | 前进 |
| `S` | 后退 |
| `A` | 左转 |
| `D` | 右转 |
| `W+A` | 前进同时左转（圆弧） |
| `W+D` | 前进同时右转（圆弧） |
| `Shift+A` | 漂移左转（急转） |
| `Shift+D` | 漂移右转（急转） |
| `+` / `=` | 加速 |
| `-` | 减速 |
| `R` | 开始/停止录制数据 |
| `ESC` | 退出控制 |

---

## 功能详解

### 1. 视频显示

边看视频边控制机器人：

```python
from openbene import OpenBene

bot = OpenBene("192.168.1.100")
bot.connect()

# 打开视频窗口
bot.start_video()

# 启动键盘控制（视频窗口会保持显示）
bot.realtime_control()

# 退出后关闭视频
bot.stop_video()
bot.disconnect()
```

### 2. 数据采集

采集训练数据用于 AI 模型：

**方式1：在实时控制中采集**

```python
bot.connect()
bot.start_video()
bot.realtime_control()  # 按 R 键开始/停止录制
```

**方式2：编程控制采集**

```python
bot.connect()

# 开始采集
bot.start_recording("./my_dataset")

# 控制机器人，数据会自动记录
bot.forward(0.5)
time.sleep(5)
bot.turn_left(0.3)
time.sleep(2)
bot.stop()

# 停止采集
bot.stop_recording()
bot.disconnect()
```

**采集的数据格式：**

```
my_dataset/
├── images/           # 视频帧图片
│   ├── 000001.jpg
│   ├── 000002.jpg
│   └── ...
└── labels.csv        # 标签文件
```

**labels.csv 内容示例：**

| image | timestamp | accel_x | accel_y | accel_z | gyro_x | gyro_y | gyro_z | command | speed_left | speed_right |
|-------|-----------|---------|---------|---------|--------|--------|--------|---------|------------|-------------|
| 000001.jpg | 2024-01-05T10:30:00 | 0.1 | 0.2 | 9.8 | 0.0 | 0.0 | 0.0 | drive | 0.5 | 0.5 |
| 000002.jpg | 2024-01-05T10:30:01 | 0.1 | 0.3 | 9.8 | 0.0 | 0.1 | 0.0 | drive | 0.3 | 0.5 |

### 3. 传感器数据

读取手机传感器：

```python
bot.connect()

# 获取加速度计
accel = bot.get_accelerometer()
print(f"加速度: x={accel['x']}, y={accel['y']}, z={accel['z']}")

# 获取陀螺仪
gyro = bot.get_gyroscope()
print(f"角速度: x={gyro['x']}, y={gyro['y']}, z={gyro['z']}")

# 获取所有传感器
sensors = bot.get_sensors()
print(sensors)
```

### 4. 精确控制

带时间的移动命令：

```python
# 前进 2 秒后自动停止
bot.move_forward(speed=0.5, duration=2.0)

# 后退 1 秒
bot.move_backward(speed=0.5, duration=1.0)

# 左转 0.5 秒
bot.rotate_left(speed=0.5, duration=0.5)

# 右转 0.5 秒
bot.rotate_right(speed=0.5, duration=0.5)

# 自定义双轮速度，持续 1 秒
bot.move(left=0.3, right=0.7, duration=1.0)
```

### 5. 直接访问模块

高级用户可以直接访问底层模块：

```python
bot.connect()

# 电机模块
bot.motor.drive(0.5, 0.3)

# 视频模块
frame = bot.video.get_frame()

# 传感器模块
accel = bot.sensors.get_accelerometer()

# 录制模块
bot.recorder.start("./data")
```

---

## API 参考

### 连接管理

| 方法 | 说明 |
|------|------|
| `OpenBene(ip, port=8765)` | 创建控制器实例 |
| `connect(timeout=5.0)` | 连接到手机 |
| `disconnect()` | 断开连接 |
| `connected` | 属性：是否已连接 |

### 基础控制

| 方法 | 说明 |
|------|------|
| `drive(left, right)` | 设置左右轮速度 (-1.0 到 1.0) |
| `forward(speed=0.5)` | 前进 |
| `backward(speed=0.5)` | 后退 |
| `turn_left(speed=0.5)` | 左转 |
| `turn_right(speed=0.5)` | 右转 |
| `stop()` | 停止 |

### 带时间的控制

| 方法 | 说明 |
|------|------|
| `move_forward(speed, duration)` | 前进指定时间后停止 |
| `move_backward(speed, duration)` | 后退指定时间后停止 |
| `rotate_left(speed, duration)` | 左转指定时间后停止 |
| `rotate_right(speed, duration)` | 右转指定时间后停止 |
| `move(left, right, duration)` | 双轮控制指定时间后停止 |

### 实时控制

| 方法 | 说明 |
|------|------|
| `realtime_control(base_speed=0.7)` | 启动键盘实时控制 |

### 视频

| 方法 | 说明 |
|------|------|
| `start_video(display=True)` | 开始视频（可选 OpenCV 窗口） |
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
| `start_recording(output_dir="./dataset")` | 开始采集数据 |
| `stop_recording()` | 停止采集 |

---

## 示例代码

查看 `examples/` 目录：

| 文件 | 说明 |
|------|------|
| `basic_control.py` | 基础控制示例 |
| `video_display.py` | 视频显示示例 |
| `data_collection.py` | 数据采集示例 |
| `racing_control.py` | 实时键盘控制示例 |
| `autopilot.py` | 自动驾驶示例（颜色追踪） |
| `main.py` | 交互式控制面板 |

运行示例：

```bash
cd openbene_sdk
python examples/basic_control.py
```

---

## 常见问题

### Q: 连接失败怎么办？

1. 确保手机和电脑在**同一个 WiFi** 网络
2. 确保手机 App 已启动并显示 "Server Running"
3. 检查 IP 地址是否正确
4. 关闭电脑防火墙或允许 Python 通过

### Q: 机器人不动怎么办？

1. 检查机器人电池是否有电
2. 检查手机和机器人的 USB 连接
3. 在手机 App 上测试控制是否正常

### Q: 视频卡顿怎么办？

1. 确保 WiFi 信号良好
2. 降低视频分辨率（在 App 设置中）
3. 减少同时运行的程序

### Q: 键盘控制没反应？

1. 确保终端窗口处于焦点状态
2. 首次使用会自动安装 `pynput`，等待安装完成
3. 在 macOS 上需要授予终端"辅助功能"权限

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
    "gyroscope": {"x": 0.01, "y": -0.02, "z": 0.0}
  }
}
```

---

## License

MIT License
