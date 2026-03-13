# OpenBot Mobile Control

> 📱 **下载最新 APK**: [`releases/`](releases/) 文件夹  
> 📱 **Download APK**: [`releases/`](releases/) folder

[![Version](https://img.shields.io/badge/version-1.0.8+9-blue.svg)](releases/)
[![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B.svg)](https://flutter.dev/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## ⚠️ 重要提示 / Important Notice

**请确保从 [`releases/`](releases/) 文件夹下载 APK！**  
**Make sure to download APK from [`releases/`](releases/) folder!**

**当前版本 / Current Version:** v1.0.8+9  
**主要功能 / Key Feature:** ✅ iOS Local Network fixes + UDP auto-discovery + interface diagnostics

---

## 🎯 主要功能 / Key Features

- ✅ **UDP 自动发现** - PC 端自动找到手机，无需手动输入 IP
- ✅ **UDP Auto-Discovery** - PC automatically finds phone without manual IP input
- ✅ **实时视频流** - 手机摄像头实时传输到 PC
- ✅ **Real-time Video Streaming** - Phone camera streams to PC
- ✅ **传感器数据** - 加速度计、陀螺仪、电池状态
- ✅ **Sensor Data** - Accelerometer, gyroscope, battery
- ✅ **WebSocket 通信** - 稳定可靠的数据传输
- ✅ **WebSocket Communication** - Stable and reliable data transfer
- ✅ **多语言支持** - 中文/English
- ✅ **Multi-language Support** - Chinese/English

---

## 🚀 快速开始 / Quick Start

### 1. 安装 App / Install App

Android:
1. 从 [`releases/`](releases/) 下载最新 APK（当前 `v1.0.8+9`）
2. 安装并打开 App
3. 授予相机权限

iOS:
1. 使用 `flutter run` 或 Xcode 从源码运行此目录工程
2. 首次运行后在系统设置确认 Local Network 权限为 ON

### 2. 手机端准备 / Phone-side checklist

保持 App 在连接页，确认可见:
- `Waiting for PC...`
- `Server Address: ws://<phone_ip>:8765`

注意:
- PC 连接时请使用此处显示的地址/IP
- 不要手动猜 IP

### 3. PC 端连接（推荐先跑 `full_demo.py`）

PowerShell:

```powershell
cd ..\openbene_sdk
pip install -e .
cd examples
python full_demo.py
```

macOS/Linux Terminal:

```bash
cd ../openbene_sdk
pip install -e .
cd examples
python full_demo.py
```

`full_demo.py` 会引导你:
1. 自动发现连接
2. 失败后手动输入手机 IP
3. 菜单式测试控制、视频、传感器、录制

### 4. 按功能运行（PC）

```bash
python basic_control.py
python interactive_control.py
python video_display.py
python video_recording_demo.py
python data_collection.py
```

### 5. 连接失败排查 / Troubleshooting

```powershell
Test-NetConnection -ComputerName <phone_ip> -Port 8765
```

若 `PingSucceeded=True` 但 `TcpTestSucceeded=False`:
- 关闭 VPN/代理/TUN 后重试
- 更换 WiFi/热点（部分网络会隔离客户端）
- iOS 检查 Local Network 权限

---

OpenBot Mobile Control is a Flutter-based mobile application that transforms your smartphone into a robot control hub with real-time video streaming and sensor data transmission.

## Quick Links

- **[Full Documentation](docs/README.md)** - Complete user guide and technical details
- **[Quick Start Guide](docs/QUICK_START.md)** - Get started in 5 minutes
- **[Changelog](docs/CHANGELOG.md)** - Version history and updates
- **[Latest Release](releases/)** - Download APK files

## Project Structure

```
openbot-mobile-control/
├── lib/                    # Flutter application source code
│   ├── models/            # Data models
│   ├── screens/           # UI screens
│   ├── services/          # Business logic services
│   └── widgets/           # Reusable UI components
├── docs/                  # Documentation
├── releases/              # APK release files
├── android/               # Android platform code
├── ios/                   # iOS platform code
└── test/                  # Unit tests

../openbene_sdk/           # Python SDK (separate project)
├── src/                   # SDK source code
├── examples/              # Usage examples
└── README.md              # SDK documentation
```

## Requirements

### Mobile Device
- Android 5.0 (Lollipop) or higher
- Camera support
- WiFi capability

### PC (Python SDK)
- Python 3.8+
- Network connectivity
- Any OS (Windows, macOS, Linux)

## Python SDK Integration

This mobile app works with the OpenBene Python SDK located at [`../openbene_sdk/`](../openbene_sdk/).

### Install Python SDK

```bash
# Navigate to SDK directory
cd ../openbene_sdk

# Install the SDK
pip install -e .
```

### Use with Auto-Discovery

```python
from openbene import OpenBene

# Auto-discover and connect to phone
bot = OpenBene.auto_connect()
print(f"Connected to {bot.ip}")

# Control the robot
bot.forward(0.5)
bot.stop()
bot.disconnect()
```

For detailed SDK documentation, see [openbene_sdk/README.md](../openbene_sdk/README.md).

## Development

### Setup

```bash
# Install Flutter dependencies
flutter pub get

# Run on connected device
flutter run

# Build release APK
flutter build apk --release
```

### Architecture

- **State Management**: Provider pattern
- **Networking**: WebSocket (web_socket_channel)
- **Camera**: camera plugin
- **Sensors**: sensors_plus plugin
- **Localization**: Custom LocalizationService

## License

MIT License - see LICENSE file for details

## Support

- Report issues: [GitHub Issues](https://github.com/yourusername/openbot-mobile-control/issues)
- Documentation: [docs/README.md](docs/README.md)

---

Made with Flutter 💙
