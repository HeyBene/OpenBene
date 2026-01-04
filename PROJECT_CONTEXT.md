# OpenBene Project Context

## 1. 项目愿景 (Vision)
OpenBene 是一个基于 OpenBot 硬件生态的**极客开发平台**。
* **核心理念：** "Phone as Body, PC as Brain"（手机作为躯体，电脑作为大脑）。
* **目标：** 解耦算力与控制。手机 App (Flutter) 仅负责透传传感器数据和执行底层驱动指令；复杂的逻辑、AI 运算和控制算法全部在 PC 端 (Python SDK) 完成。

## 2. 技术架构 (Architecture)
项目采用 **C/S 架构**，分为两部分：

### A. 移动端 (Client: Robot Body)
* **仓库路径：** `openbene_app/`
* **技术栈：** Flutter (Dart)
* **职责：**
    1.  **局域网发现：** 发送 UDP 广播，让 PC 发现自己。
    2.  **指令执行：** 建立 TCP Server，接收 JSON 指令，通过蓝牙/OTG 驱动底盘电机。
    3.  **数据采集：** (Milestone 2) 采集摄像头视频流和 IMU 数据回传给 PC。

### B. PC 端 (Server/Controller: Robot Brain)
* **仓库路径：** `openbene_sdk/`
* **技术栈：** Python 3.x
* **职责：**
    1.  **SDK 封装：** 提供优雅的 Python API (如 `bot.move_forward()`)。
    2.  **连接管理：** 自动扫描局域网设备并建立连接。
    3.  **逻辑控制：** 运行用户编写的 Python 脚本。

## 3. 通信协议 (Protocol Contract) - 必须严格遵守

### 3.1 握手与发现 (Discovery)
* **机制：** UDP Broadcast (Port: 12345)
* **App 发送：** `{"type": "discovery", "name": "OpenBene_Bot", "ip": "<DEVICE_IP>"}`
* **连接方式：** PC 收到广播后，解析 IP，主动向 App 的 TCP Port 8888 发起连接。

### 3.2 控制指令 (PC -> App)
通过 TCP Socket 发送 JSON 字符串（UTF-8 编码，以 `\n` 结尾）：
* **移动：** `{"cmd": "drive", "val": [left_speed, right_speed]}`
    * 范围：-1.0 到 1.0 (浮点数)
* **停止：** `{"cmd": "stop"}`

## 4. 当前阶段目标 (Current Phase: Milestone 1)
**Focus:** 基础通信与控制链路 (The "First Version")
我们要完成以下任务，其他功能（如视频流）暂不考虑：
1.  **App 端：** 实现 UDP 广播和 TCP 监听，简单的 UI 显示 IP 和连接状态。实现收到 JSON 后驱动底盘（Mock 或 真实驱动）。
2.  **SDK 端：** 实现 `Discovery` 类（监听 UDP）和 `OpenBene` 类（TCP 客户端）。
3.  **联调：** 实现 Python 脚本运行后，自动连接 App，并能发送指令让 App 打印日志或动起来。

## 5. 开发规范 (Coding Guidelines)
* **Python:** 遵循 PEP 8，代码必须有 Docstring。
* **Flutter:** 代码结构清晰，逻辑与 UI 分离。
* **Git:** 提交信息要简洁明确 (e.g., "feat: implement udp broadcast").
