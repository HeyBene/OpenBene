# OpenBene SDK

![Python Version](https://img.shields.io/badge/python-3.8%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)

**Phone as Body, PC as Brain** - Transform your Android phone into a powerful robot controller.

OpenBene SDK is a Python library that enables PC-based control of mobile robots using the OpenBot hardware platform. Offload complex AI computations, computer vision, and control algorithms to your powerful PC while your phone handles sensor data collection and motor control.

---

## ✨ Features

- 🔌 **Automatic Discovery**: Zero-config connection via UDP broadcast
- 🎮 **Intuitive API**: Control your robot with simple Python commands
- 🚀 **High Performance**: TCP socket communication for real-time control
- 📱 **Phone as Body**: Phone handles hardware I/O and sensor data
- 🧠 **PC as Brain**: Run AI models and complex algorithms on your PC
- 🛠️ **Extensible**: Built for future vision and sensor integration

---

## 📦 Installation

```bash
pip install openbene
```

**Note:** Package will be published to PyPI soon. For now, install from source:

```bash
git clone https://github.com/yourusername/openbene.git
cd openbene/openbene_sdk
pip install -e .
```

---

## 🚀 Quick Start

Control your robot in just 3 lines of code:

```python
from openbene import OpenBene

bot = OpenBene.connect_auto()  # Auto-discover and connect
bot.move_forward(0.5)           # Move forward at 50% speed
bot.stop()                      # Stop the robot
```

---

## 🔧 Hardware Requirements

### Required Components

1. **Android Phone** (Android 6.0+)
   - WiFi connectivity
   - USB OTG support

2. **OpenBot Robot Chassis**
   - Arduino-based motor controller
   - USB Type-C connection to phone
   - Compatible with [OpenBot DIY kit](https://www.openbot.org/)

3. **PC/Laptop**
   - Python 3.8 or higher
   - Same WiFi network as the phone

### Setup

1. Install the OpenBene App on your Android phone (APK available in `openbene_app/`)
2. Connect the phone to the robot chassis via USB Type-C
3. Connect both phone and PC to the same WiFi network
4. Launch the app and click "Start Robot"
5. Run your Python script on the PC

---

## 📖 Usage Examples

### Basic Movement

```python
from openbene import OpenBene
import time

# Connect to robot
bot = OpenBene.connect_auto()

# Move forward
bot.move_forward(0.7)
time.sleep(2)

# Turn right
bot.turn_right(0.5)
time.sleep(1)

# Move backward
bot.move_backward(0.5)
time.sleep(2)

# Stop
bot.stop()

# Disconnect
bot.disconnect()
```

### Manual Discovery

```python
from openbene import Discovery, OpenBene

def on_robot_found(robot_info):
    print(f"Found: {robot_info['name']} at {robot_info['ip']}")

# Listen for robots
discovery = Discovery(port=12345)
discovery.start(on_discovery=on_robot_found)

# Connect manually
bot = OpenBene("192.168.1.100")
bot.connect()
bot.move_forward(0.5)
```

### Context Manager

```python
from openbene import OpenBene

with OpenBene.connect_auto() as bot:
    bot.move_forward(0.8)
    # Auto-disconnect on exit
```

---

## 🎮 Advanced Examples

Check out the `examples/` directory for more:

- **[connect_demo.py](examples/connect_demo.py)** - Discovery and connection
- **[control_demo.py](examples/control_demo.py)** - Movement sequences
- **[keyboard_drive.py](examples/keyboard_drive.py)** - WASD keyboard control

---

## 📡 Communication Protocol

### Discovery (UDP Broadcast)
- **Port:** 12345
- **Format:** `{"type": "discovery", "name": "OpenBene_Bot", "ip": "<PHONE_IP>"}`

### Control Commands (TCP)
- **Port:** 8888
- **Format:** JSON over TCP, UTF-8 encoded, newline-terminated

**Drive Command:**
```json
{"cmd": "drive", "val": [left_speed, right_speed]}
```
- Speed range: -1.0 (full reverse) to 1.0 (full forward)

**Stop Command:**
```json
{"cmd": "stop"}
```

---

## 🛣️ Roadmap

- ✅ **Milestone 1**: Basic communication and motor control
- 🚧 **Milestone 2**: Camera streaming and computer vision
- 🔜 **Milestone 3**: IMU data and sensor fusion
- 🔜 **Milestone 4**: AI integration (object detection, navigation)

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'feat: add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](../LICENSE) file for details.

---

## 🙏 Acknowledgments

- Built on the [OpenBot](https://www.openbot.org/) hardware platform
- Inspired by the "Phone as Body, PC as Brain" philosophy

---

## 📞 Support

- 📫 Issues: [GitHub Issues](https://github.com/yourusername/openbene/issues)
- 💬 Discussions: [GitHub Discussions](https://github.com/yourusername/openbene/discussions)
- 📖 Documentation: [Wiki](https://github.com/yourusername/openbene/wiki)

---

**Made with ❤️ for robotics enthusiasts and geeks**
