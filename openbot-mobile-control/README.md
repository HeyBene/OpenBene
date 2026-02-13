# OpenBot Mobile Control

> 📱 **下载最新 APK**: [`releases/`](releases/) 文件夹  
> 📱 **Download APK**: [`releases/`](releases/) folder

[![Version](https://img.shields.io/badge/version-1.0.6-blue.svg)](releases/)
[![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B.svg)](https://flutter.dev/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## ⚠️ 重要提示 / Important Notice

**请确保从 [`releases/`](releases/) 文件夹下载 APK！**  
**Make sure to download APK from [`releases/`](releases/) folder!**

**当前版本 / Current Version:** v1.0.6  
**主要功能 / Key Feature:** ✅ UDP 自动发现支持 / UDP Auto-Discovery Support

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

### 1. 安装 APK / Install APK

从 [`releases/`](releases/) 下载最新 APK 并安装到手机。

Download latest APK from [`releases/`](releases/) and install on phone.

### 2. 使用自动发现 / Use Auto-Discovery

手机和电脑连接到同一 WiFi 后：  
After connecting phone and PC to same WiFi:

**手机端 / Phone:**
1. 打开 App / Open app
2. 授予相机权限 / Grant camera permission
3. 看到 "Waiting for PC..." 状态 / See "Waiting for PC..." status

**电脑端 / PC:**
```python
from openbene import OpenBene

# 自动发现并连接 / Auto-discover and connect
bot = OpenBene.auto_connect()
print(f"✓ Connected to {bot.ip}")

# 控制 / Control
bot.forward(0.5)
```

**完成！/ Done!** 🎉

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
