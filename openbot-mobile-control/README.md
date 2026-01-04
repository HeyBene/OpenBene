# OpenBot Mobile Control

[![Version](https://img.shields.io/badge/version-1.0.5-blue.svg)](releases/)
[![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B.svg)](https://flutter.dev/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

OpenBot Mobile Control is a Flutter-based mobile application that transforms your smartphone into a robot control hub with real-time video streaming and sensor data transmission.

## Features

- Real-time video streaming from smartphone camera
- Sensor data transmission (accelerometer, gyroscope, battery)
- WebSocket-based communication with automatic reconnection
- Multi-language support (English/Chinese)
- Modern, polished UI with Material Design 3

## Quick Links

- **[Full Documentation](docs/README.md)** - Complete user guide and technical details
- **[Quick Start Guide](docs/QUICK_START.md)** - Get started in 5 minutes
- **[Changelog](docs/CHANGELOG.md)** - Version history and updates
- **[Latest Release](releases/)** - Download APK files

## Project Structure

```
my_app/
├── lib/                    # Flutter application source code
│   ├── models/            # Data models
│   ├── screens/           # UI screens
│   ├── services/          # Business logic services
│   └── widgets/           # Reusable UI components
├── server/                # Server-side components
│   ├── test_server.py    # WebSocket test server
│   └── python_sdk/       # Python SDK for PC integration
├── docs/                  # Documentation
├── releases/              # APK release files
├── android/               # Android platform code
├── ios/                   # iOS platform code
└── test/                  # Unit tests
```

## Requirements

### Mobile Device
- Android 5.0 (Lollipop) or higher
- Camera support
- WiFi capability

### PC (Server)
- Python 3.7+
- Network connectivity
- Any OS (Windows, macOS, Linux)

## Quick Start

### 1. Install the App

Download the latest APK from [releases/](releases/) and install on your Android device.

### 2. Start the Server

```bash
cd server
pip3 install -r python_sdk/requirements.txt
python3 test_server.py
```

The server will display your PC's IP address.

### 3. Connect

1. Open the app on your phone
2. Enter your PC's IP address and port (default: 8765)
3. Tap "Connect to PC"
4. Start streaming!

For detailed instructions, see [Quick Start Guide](docs/QUICK_START.md).

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
