# OpenBene

> ⚠️ **重要提示 / Important Notice**
> 
> **请从 [`openbot-mobile-control/releases/`](openbot-mobile-control/releases/) 文件夹下载最新 APK！**  
> **Download latest APK from [`openbot-mobile-control/releases/`](openbot-mobile-control/releases/) folder!**
> 
> 最新版本 / Latest: **v1.0.8+9** (iOS local network fixes + improved diagnostics)

---

![Python Version](https://img.shields.io/badge/python-3.8%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
[![GitHub Discussions](https://img.shields.io/github/discussions/HeyBene/OpenBene)](https://github.com/HeyBene/OpenBene/discussions)

**Phone as Body, PC as Brain** - Control OpenBot robots with Python

[English](#english) | [中文](#中文)

[![💬 Join Discussion](https://img.shields.io/badge/💬_Join_Discussion-GitHub_Discussions-blue?style=for-the-badge)](https://github.com/HeyBene/OpenBene/discussions)

---

## 🚀 快速开始 / Quick Start

这部分按真实使用顺序写，目标是新用户 10 分钟内跑通:
- 手机安装并启动 App
- PC 端运行 `full_demo.py`
- 控制运动、查看视频、采集数据

### 1️⃣ 手机端安装 App

1. 打开 `openbot-mobile-control/releases/`
2. Android 下载并安装最新 APK（当前 `v1.0.8+9`）
3. 打开 App，授权相机权限
4. 确认界面显示:
- `Waiting for PC...`
- `Server Address: ws://<手机IP>:8765`

注意:
- iOS 目前需要从源码运行 `openbot-mobile-control`（Xcode/Flutter），不是直接安装 APK
- 后续在 PC 端连接时，请以 App 显示的 `Server Address` 为准

### 2️⃣ PC 端安装 SDK

PowerShell:

```powershell
cd openbene_sdk
pip install -e .
```

macOS/Linux Terminal:

```bash
cd openbene_sdk
pip install -e .
```

### 3️⃣ 先跑完整示例（推荐）

PowerShell:

```powershell
cd openbene_sdk\examples
python full_demo.py
```

macOS/Linux Terminal:

```bash
cd openbene_sdk/examples
python full_demo.py
```

`full_demo.py` 会引导你选择:
- 手动输入手机 IP 连接
- 自动发现连接（UDP + 子网扫描）

连上后可在菜单里体验:
- 小车运动控制
- 视频流接收
- 传感器读取
- 数据采集与保存

### 4️⃣ 按功能单独运行示例

运动控制:

```bash
python basic_control.py
python interactive_control.py
```

视频传输:

```bash
python video_display.py
python video_recording_demo.py
```

数据采集:

```bash
python data_collection.py
```

自动发现与诊断:

```bash
python test_udp_discovery.py
python diagnose.py <phone_ip>
```

### 5️⃣ 常见失败场景（必须看）

1. 先检查端口是否可达（Windows）:

```powershell
Test-NetConnection -ComputerName <phone_ip> -Port 8765
```

2. 若 `PingSucceeded=True` 且 `TcpTestSucceeded=False`:
- 关闭 VPN/代理/TUN（例如 Clash）再试
- 更换不会隔离客户端的 WiFi/热点

3. iOS 需要确认:
- `Settings -> Privacy & Security -> Local Network -> OpenBene = ON`

4. 手机有多网卡时:
- 不要凭感觉输入 IP，始终使用 App 页面显示的 `Server Address`

---

## English

### Project Overview

OpenBene is a geek development platform based on OpenBot hardware, enabling you to easily control robots with Python.

### Architecture

```
PC (Python) → WebSocket → Phone App → USB → Arduino → Motors
```

### Quick Start

#### 1. Install Phone App

**✅ Correct Download Location:**

Visit: [`openbot-mobile-control/releases/`](openbot-mobile-control/releases/)

Download: `openbot-mobile-control-v1.0.8+9.apk` (see `openbot-mobile-control/releases/`)

**❌ Do NOT download from elsewhere!**

#### 2. Install Python SDK

```bash
cd openbene_sdk
pip install -e .
```

#### 3. Auto-Connect (Recommended)

```python
from openbene import OpenBene

# Auto-discover and connect (no IP input needed)
bot = OpenBene.auto_connect()

print(f"✓ Connected to {bot.ip}")

# Control the robot
bot.forward(0.5)
import time
time.sleep(2)
bot.stop()

bot.disconnect()
```

If auto-discovery fails, run diagnostics first:

```bash
cd openbene_sdk/examples
python diagnose.py <phone_ip>
```

#### 4. Verify App Version

**Correct Version UI:**
- ✅ "Server Address: ws://192.168.x.x:8765"
- ✅ "Waiting for PC..."
- ✅ Shows phone IP (not an input field)
- ✅ Version text: `v1.0.8 build 2026-03-12`

**Wrong Version UI:**
- ❌ "PC IP Address" input field
- ❌ "Connection Settings"
- ❌ "Enter your PC's IP address"

**If you see the wrong UI, please re-download and install the correct version.**

#### 5. Quick Troubleshooting

1. Ensure phone and PC are on the same subnet.
2. On Windows, test the server port first:

```powershell
Test-NetConnection -ComputerName <phone_ip> -Port 8765
```

3. If `PingSucceeded=True` but `TcpTestSucceeded=False`:
  - Disable VPN/Proxy/TUN (for example Clash) and retry
  - Avoid enterprise WiFi or hotspot networks that isolate clients
4. On iOS, confirm permission:
  - Settings -> Privacy & Security -> Local Network -> OpenBene = ON
5. When multiple network interfaces exist, always use the App's displayed `Server Address`.

---

#### Old Method: Manual IP Connection

1. Ensure phone and computer are on the same WiFi network
2. Open phone App, note the displayed IP address
3. Run Python script:

```python
from openbene import OpenBene

with OpenBene("192.168.1.100") as bot:  # Replace with your phone IP
    bot.forward(0.5)   # Move forward
    bot.turn_left(0.5) # Turn left
    bot.stop()         # Stop
```

### Control Examples

#### Basic Control

```bash
python examples/basic_control.py
```

#### Interactive Console

```bash
python examples/interactive_control.py
```

#### Racing Style Control (Realtime Keyboard)

```bash
pip install -e ".[keyboard]"
python examples/racing_control.py
```

Controls:

- **W/S** - Forward/Backward
- **A/D** - Turn (arc)
- **W+A/D** - Move while turning
- **Shift+A/D** - Drift
- **ESC** - Exit

#### Video Display

```bash
python examples/video_display.py
```

### Project Structure

```
OpenBene/
├── .github/                     # GitHub config (Issue/PR templates, Actions workflows)
├── openbene_sdk/                # Python SDK
│   ├── src/                     # Core code
│   └── examples/                # Example scripts
├── openbot-mobile-control/      # Flutter phone App (controller)
├── openbot.ino                  # Arduino firmware (MCU motor control)
├── .gitignore                   # Git ignore rules
├── LICENSE                      # Open source license (MIT)
├── PROJECT_CONTEXT.md           # Project background/design/architecture context
└── README.md                    # Project overview and quick start
```

### Documentation

- [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) - Technical architecture details
- [openbene_sdk/README.md](openbene_sdk/README.md) - SDK detailed documentation
- [CHANGELOG.md](CHANGELOG.md) - Version changelog

### Contributing

We welcome all contributions!

- 🐛 [Report Bug](https://github.com/HeyBene/OpenBene/issues/new?template=bug_report.yml)
- 💡 [Feature Request](https://github.com/HeyBene/OpenBene/issues/new?template=feature_request.yml)
- 📖 Read [Contributing Guide](CONTRIBUTING.md)
- 💬 Join [Community Discussion](https://github.com/HeyBene/OpenBene/discussions)

### Acknowledgments

This project is based on the following open source projects:

- **[OpenBot](https://github.com/isl-org/OpenBot)** - Open source robot platform by Intel ISL
  - Arduino firmware (`openbot.ino`) from OpenBot project
  - Original authors: Matthias Mueller and contributors
  - License: MIT License

Thanks to the OpenBot team for their excellent work!

### License

MIT License - See [LICENSE](LICENSE) file

---

## 中文

### 项目简介

OpenBene 是一个基于 OpenBot 硬件的极客开发平台，让你可以用 Python 轻松控制机器人。

### 架构

```
PC (Python) → WebSocket → 手机 App → USB → Arduino → 电机
```

### 快速开始

#### 1. 安装手机 App

从 [GitHub Releases](https://github.com/HeyBene/OpenBene/releases) 下载 APK 并安装到 Android 手机。

#### 2. 安装 Python SDK

```bash
cd openbene_sdk
pip install -e .
```

#### 3. 连接并控制

1. 确保手机和电脑在同一 WiFi 网络
2. 打开手机 App，记下显示的 IP 地址
3. 运行 Python 脚本：

```python
from openbene import OpenBene

with OpenBene("192.168.1.100") as bot:  # 替换为手机 IP
    bot.forward(0.5)   # 前进
    bot.turn_left(0.5) # 左转
    bot.stop()         # 停止
```

### 控制示例

#### 基础控制

```bash
python examples/basic_control.py
```

#### 交互式控制台

```bash
python examples/interactive_control.py
```

#### 赛车风格控制（实时键盘）

```bash
pip install -e ".[keyboard]"
python examples/racing_control.py
```

控制方式：
- **W/S** - 前进/后退
- **A/D** - 转向（圆弧）
- **W+A/D** - 边走边转
- **Shift+A/D** - 漂移
- **ESC** - 退出

#### 视频显示

```bash
python examples/video_display.py
```

### 项目结构

```
OpenBene/
├── .github/                     # GitHub 配置（Issue/PR 模板、Actions 工作流等）
├── openbene_sdk/                # Python SDK
│   ├── src/                     # 核心代码
│   └── examples/                # 示例脚本
├── openbot-mobile-control/      # Flutter 手机 App（控制端）
├── openbot.ino                  # Arduino 固件（MCU 端控制电机等）
├── .gitignore                   # Git 忽略规则（不提交缓存/构建产物等）
├── LICENSE                      # 开源许可证（MIT）
├── PROJECT_CONTEXT.md           # 项目背景/设计说明/架构上下文（给开发者理解用）
└── README.md                    # 项目总览与快速开始（入口文档）
```

### 文档

- [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) - 技术架构详情
- [openbene_sdk/README.md](openbene_sdk/README.md) - SDK 详细文档
- [CHANGELOG.md](CHANGELOG.md) - 版本更新日志

### 参与贡献

我们欢迎任何形式的贡献！

- 🐛 [报告 Bug](https://github.com/HeyBene/OpenBene/issues/new?template=bug_report_CN.yml)
- 💡 [提出建议](https://github.com/HeyBene/OpenBene/issues/new?template=feature_request_CN.yml)
- 📖 阅读 [贡献指南](CONTRIBUTING.md)
- 💬 参与 [社区讨论](https://github.com/HeyBene/OpenBene/discussions)

### 致谢

本项目基于以下开源项目：

- **[OpenBot](https://github.com/isl-org/OpenBot)** - Intel ISL 开发的开源机器人平台
  - Arduino 固件 (`openbot.ino`) 来自 OpenBot 项目
  - 原作者：Matthias Mueller 及贡献者
  - 许可证：MIT License

感谢 OpenBot 团队的出色工作！

### 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件
