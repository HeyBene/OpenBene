# OpenBot Mobile Control App

<div align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/version-1.0.0-blue.svg" alt="Version">
</div>

Official mobile control application for OpenBot robots. Stream real-time video and sensor data from your smartphone to your PC for robot control and monitoring.

## 📱 Features

- **Real-time Video Streaming**: High-quality JPEG video streaming from phone camera
- **Sensor Monitoring**: IMU (accelerometer, gyroscope, magnetometer) and battery data
- **Network Communication**: WebSocket-based communication with automatic reconnection
- **Cross-platform**: Supports Android (iOS coming soon)
- **Python SDK**: Easy-to-use Python SDK for PC-side development
- **Visual Dashboard**: Real-time sensor data visualization

## 🚀 Quick Start

### For Mobile App Users

1. **Download the App**
   - Download the latest APK from [Releases](https://github.com/your-repo/openbot-app/releases)
   - Install on your Android device
   - Grant camera and network permissions

2. **Connect to PC**
   - Ensure your phone and PC are on the same Wi-Fi network
   - Enter your PC's IP address (e.g., `192.168.1.100`)
   - Default port is `8765`
   - Tap "Connect"

3. **Start Streaming**
   - Once connected, video and sensor data will stream automatically
   - View sensor data on the dashboard

### For PC Users (Python SDK)

> ⚠️ **注意 / Note**: Python SDK 现在位于独立项目 `openbene_sdk/`  
> ⚠️ **Note**: Python SDK is now in separate project `openbene_sdk/`

1. **Install OpenBene SDK**
   ```bash
   # 导航到 SDK 目录
   cd ../../openbene_sdk
   
   # 安装 SDK
   pip install -e .
   ```

2. **Auto-Connect (Recommended)**
   ```python
   from openbene import OpenBene
   
   # 自动发现并连接手机
   bot = OpenBene.auto_connect()
   print(f"Connected to {bot.ip}")
   
   # 控制机器人
   bot.forward(0.5)
   bot.stop()
   bot.disconnect()
   ```

3. **Manual Connection**
   ```python
   from openbene import OpenBene
   
   # 手动输入手机IP
   bot = OpenBene("192.168.1.15", port=8765)
   bot.connect()
   
   # 控制
   bot.forward(0.5)
   bot.stop()
   bot.disconnect()
   ```

4. **查看更多示例**
   ```bash
   cd ../../openbene_sdk/examples
   python basic_control.py
   python sdk_demo.py
   ```

详细的 SDK 文档请查看: [openbene_sdk/README.md](../../openbene_sdk/README.md)

## 📖 Documentation

### Mobile App

**Permissions Required:**
- Camera: For video streaming
- Internet: For network communication
- Network State: To detect connection status
- WiFi State: For UDP discovery broadcast

**Connection Guide:**
1. 手机和电脑连接到同一 WiFi
2. 打开手机 App，看到 "Waiting for PC..." 状态
3. 运行 `OpenBene.auto_connect()` 即可自动连接
4. 或者记下手机显示的 IP，手动连接

### Python SDK

**详细文档 / Detailed Documentation:**
请查看 [openbene_sdk/README.md](../../openbene_sdk/README.md)

**快速参考 / Quick Reference:**

```python
from openbene import OpenBene

# 自动发现 / Auto-discovery
bot = OpenBene.auto_connect(timeout=10)

# 手动连接 / Manual connection
bot = OpenBene("192.168.1.15", port=8765)
bot.connect()

# 运动控制 / Motion control
bot.forward(speed)    # 前进
bot.backward(speed)   # 后退
bot.left(speed)       # 左转
bot.right(speed)      # 右转
bot.stop()            # 停止

# 断开连接 / Disconnect
bot.disconnect()
```

## 🛠️ Development

### Build from Source

**Requirements:**
- Flutter SDK 3.10+
- Android SDK
- Dart 3.0+

**Build Steps:**
```bash
# Install dependencies
flutter pub get
# Run in debug mode
flutter run

# Build APK
flutter build apk --release

# Build App Bundle
flutter build appbundle
```

### Project Structure

```
├── lib/
│   ├── models/          # Data models
│   ├── services/        # Core services (camera, sensors, network)
│   ├── screens/         # UI screens
│   └── widgets/         # Reusable widgets
├── python_sdk/
│   ├── openbot_sdk/     # SDK source code
│   └── examples/        # Example scripts
├── android/             # Android platform code
└── ios/                 # iOS platform code
```

## 🐛 Troubleshooting

**Connection Issues:**
- Verify both devices are on the same network
- Check firewall settings on PC (allow port 8765)
- Ensure correct IP address is entered

**No Video:**
- Grant camera permission in app settings
- Restart the app

**High Latency:**
- Use 5GHz Wi-Fi if available
- Reduce video quality in settings
- Check network bandwidth

**App Crashes:**
- Update to latest version
- Clear app data and reinstall
- Check logs for error messages

## 📋 Roadmap

- [x] Core video streaming
- [x] Sensor data transmission
- [x] Python SDK
- [x] Android app
- [ ] iOS app support
- [ ] Settings page (video quality, frame rate)
- [ ] Robot control commands
- [ ] Recording functionality
- [ ] Google Play Store release
- [ ] App Store release

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- OpenCV contributors
- The OpenBot community

## 📞 Support

- Report bugs: [GitHub Issues](https://github.com/your-repo/openbot-app/issues)
- Documentation: [Wiki](https://github.com/your-repo/openbot-app/wiki)
- Email: support@openbot.org

---

Made with ❤️ by the OpenBot Team
