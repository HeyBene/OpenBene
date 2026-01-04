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

1. **Install Python SDK**
   ```bash
   cd python_sdk
   pip install -r requirements.txt
   ```

2. **Run Test Client**
   ```bash
   cd python_sdk/examples
   python test_client.py
   ```

3. **Use in Your Code**
   ```python
   from openbot_sdk import OpenBotClient

   # Create and start client
   client = OpenBotClient(host="0.0.0.0", port=8765)
   client.start()

   # Get latest data
   video_frame = client.get_video_frame()  # JPEG bytes
   sensor_data = client.get_sensor_data()  # Dict with sensor readings
   ```

## 📖 Documentation

### Mobile App

**Permissions Required:**
- Camera: For video streaming
- Internet: For network communication
- Network State: To detect connection status

**Connection Guide:**
1. Find your PC's local IP address
   - Windows: Run `ipconfig` in Command Prompt
   - macOS/Linux: Run `ifconfig` or `ip addr`
2. Ensure firewall allows port 8765
3. Use the same Wi-Fi network for both devices

### Python SDK

**Installation:**
```bash
pip install -e python_sdk
```

**API Reference:**

```python
client = OpenBotClient(host="0.0.0.0", port=8765)
client.start()                          # Start server
client.stop()                           # Stop server
client.get_video_frame()                # Get latest JPEG frame (bytes)
client.get_sensor_data()                # Get latest sensor data (dict)
client.set_video_frame_callback(func)   # Set callback for frames
client.set_sensor_data_callback(func)   # Set callback for sensor data
client.is_connected()                   # Check connection status
client.get_statistics()                 # Get statistics
```

**Sensor Data Format:**
```python
{
    'accelerometer': {'x': 0.1, 'y': 0.2, 'z': 9.8},  # m/s²
    'gyroscope': {'x': 0.0, 'y': 0.0, 'z': 0.0},      # rad/s
    'magnetometer': {'x': 30.0, 'y': -20.0, 'z': 40.0},  # μT
    'battery_level': 0.85,                             # 0.0-1.0
    'voltage': 12.6,                                   # V
    'timestamp': '2025-12-30T12:00:00.000Z'
}
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
