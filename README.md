# OpenBene

**Phone as Body, PC as Brain** - 用 Python 控制 OpenBot 机器人

## 项目简介

OpenBene 是一个基于 OpenBot 硬件的极客开发平台，让你可以用 Python 轻松控制机器人。

### 架构

```
PC (Python) → WebSocket → 手机 App → USB → Arduino → 电机
```

## 快速开始

### 1. 安装手机 App

从 [GitHub Releases](https://github.com/HeyBene/OpenBene/releases) 下载 APK 并安装到 Android 手机。

### 2. 安装 Python SDK

```bash
cd openbene_sdk
pip install -e .
```

### 3. 连接并控制

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

## 控制示例

### 基础控制

```bash
python examples/basic_control.py
```

### 交互式控制台

```bash
python examples/interactive_control.py
```

### 赛车风格控制（实时键盘）

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

### 视频显示

```bash
python examples/video_display.py
```

## 项目结构

```
OpenBene/
├── openbene_sdk/          # Python SDK
│   ├── src/               # 核心代码
│   └── examples/          # 示例脚本
├── openbot-mobile-control/ # Flutter 手机 App
└── openbot.ino            # Arduino 固件
```

## 文档

- [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) - 技术架构详情
- [openbene_sdk/README.md](openbene_sdk/README.md) - SDK 详细文档

## 许可证

MIT License
