# OpenBene Project Context

## 1. 项目愿景 (Vision)
OpenBene 是一个基于 OpenBot 硬件生态的**极客开发平台**。
* **核心理念：** "Phone as Body, PC as Brain"（手机作为躯体，电脑作为大脑）。
* **目标：** 解耦算力与控制。手机 App (Flutter) 负责透传传感器数据和执行底层驱动指令；复杂的逻辑、AI 运算和控制算法全部在 PC 端 (Python SDK) 完成。

## 2. 技术架构 (Architecture)

### 整体架构图
```
PC (Python SDK) → WebSocket → 手机 (Flutter App) → USB Serial → Arduino → 电机
```

### A. 移动端 (Robot Body)
* **仓库路径：** `openbot-mobile-control/`
* **技术栈：** Flutter (Dart)
* **职责：**
    1. **WebSocket Server：** 监听 PC 连接（端口 8765）
    2. **指令转发：** 接收 JSON 指令，通过 USB Serial 驱动底盘电机
    3. **视频采集：** 采集摄像头视频流，通过 HTTP MJPEG 回传给 PC
    4. **状态显示：** 显示连接状态、IP 地址、电机状态等

### B. PC 端 (Robot Brain)
* **仓库路径：** `openbene_sdk/`
* **技术栈：** Python 3.8+
* **职责：**
    1. **SDK 封装：** 提供优雅的 Python API（如 `bot.forward()`, `bot.drive(left, right)`）
    2. **WebSocket 客户端：** 连接手机 App 发送控制指令
    3. **视频接收：** 接收 MJPEG 视频流用于 AI 处理
    4. **逻辑控制：** 运行用户编写的 Python 脚本

### C. Arduino 固件 (Motor Driver)
* **文件：** `openbot.ino`
* **技术栈：** Arduino C++
* **职责：**
    1. **串口通信：** 接收手机发送的控制命令
    2. **PWM 控制：** 驱动左右电机
    3. **安全机制：** 心跳超时自动停止

## 3. 通信协议 (Protocol)

### 3.1 WebSocket 连接
* **端口：** 8765
* **连接方式：** PC 主动连接到 `ws://<手机IP>:8765`

### 3.2 控制指令 (PC → App)
通过 WebSocket 发送 JSON 字符串：
* **移动：** `{"cmd": "drive", "val": [left_speed, right_speed]}`
    * 范围：-1.0 到 1.0（浮点数）
* **停止：** `{"cmd": "stop"}`

### 3.3 视频流 (App → PC)
* **协议：** HTTP MJPEG
* **端口：** 8080
* **URL：** `http://<手机IP>:8080/video`

## 4. 开发规范 (Coding Guidelines)
* **Python:** 遵循 PEP 8，代码必须有 Docstring
* **Flutter:** 代码结构清晰，逻辑与 UI 分离
* **Git:** 提交信息要简洁明确（如 "feat: add racing control"）

## 5. 快速开始

### 安装 Python SDK
```bash
cd openbene_sdk
pip install -e .
```

### 基础控制示例
```python
from openbene import OpenBene

with OpenBene("192.168.1.100") as bot:
    bot.forward(0.5)   # 前进
    bot.stop()         # 停止
```

### 赛车风格控制
```bash
pip install -e ".[keyboard]"
python examples/racing_control.py
```
