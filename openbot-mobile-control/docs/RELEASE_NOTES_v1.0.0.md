# OpenBot Mobile Control v1.0.0 - Release Notes

**Release Date:** January 4, 2026

## Overview

OpenBot Mobile Control is the official mobile application for controlling OpenBot robots. Transform your smartphone into a powerful robot control center with real-time video streaming, sensor monitoring, and seamless PC integration.

## What's New in v1.0.0

### Features

#### Mobile App (Android)
- **Real-time Video Streaming**: High-quality JPEG video streaming from your phone's camera to PC
- **Comprehensive Sensor Support**:
  - Accelerometer (m/s²)
  - Gyroscope (rad/s)
  - Battery level monitoring
- **Modern User Interface**:
  - Beautiful gradient backgrounds and card-based layouts
  - Smooth animations and transitions
  - Intuitive connection wizard with step-by-step guide
  - Real-time connection status indicator with visual feedback
  - Polished sensor dashboard with color-coded metrics
- **Robust Network Communication**:
  - WebSocket-based protocol
  - Automatic reconnection (up to 5 attempts)
  - Heartbeat mechanism to detect connection loss
  - 3-second retry delay between reconnection attempts
- **User Experience**:
  - Permission management with clear prompts
  - In-app quick setup guide
  - Live streaming indicator
  - Frame and sensor update counters

#### Python SDK (PC)
- **Easy-to-use Client Library**: Simple API for receiving data from the mobile app
- **Key Functions**:
  - `get_video_frame()` - Retrieve latest JPEG video frame as bytes
  - `get_sensor_data()` - Get current sensor readings as dict
  - `set_video_frame_callback()` - Register callback for video frames
  - `set_sensor_data_callback()` - Register callback for sensor data
  - `is_connected()` - Check connection status
  - `get_statistics()` - Retrieve performance statistics
- **Automatic Server Management**: Built-in WebSocket server handling
- **Example Scripts**: Ready-to-use examples for quick testing

## Installation

### Mobile App (Android)

1. **Download APK**:
   - Get `openbot-mobile-control-v1.0.0.apk` from the release assets
   - APK size: ~49.4 MB

2. **Install**:
   - Enable "Install from Unknown Sources" in Android settings
   - Open the APK file and follow installation prompts

3. **Grant Permissions**:
   - Camera (required for video streaming)
   - Internet (required for network communication)
   - Network State (for connection monitoring)

### Python SDK (PC)

```bash
# Navigate to the SDK directory
cd python_sdk

# Install dependencies
pip install -r requirements.txt

# Optional: Install as package
pip install -e .
```

## Quick Start Guide

### 1. Setup PC Server

```python
from openbot_sdk import OpenBotClient

# Create and start the server
client = OpenBotClient(host="0.0.0.0", port=8765)
client.start()

# Get your PC's local IP address
# Windows: ipconfig
# macOS/Linux: ifconfig or ip addr
print("Server running. Connect from mobile app using your PC's IP")
```

### 2. Connect Mobile App

1. Launch the **OpenBot** app on your Android device
2. Ensure your phone and PC are on the **same Wi-Fi network**
3. Enter your PC's IP address (e.g., `192.168.1.100`)
4. Keep default port as `8765`
5. Tap **"Connect to PC"**

### 3. Receive Data on PC

```python
# Get latest video frame
video_frame = client.get_video_frame()  # Returns JPEG bytes

# Get sensor data
sensor_data = client.get_sensor_data()  # Returns dict
print(sensor_data)
# {
#   'accelerometer': {'x': 0.1, 'y': 0.2, 'z': 9.8},
#   'gyroscope': {'x': 0.0, 'y': 0.0, 'z': 0.0},
#   'battery_level': 0.85,
#   'timestamp': '2026-01-04T12:00:00.000Z'
# }

# Use callbacks for real-time processing
def on_video_frame(frame_bytes):
    # Process video frame
    pass

def on_sensor_data(data):
    # Process sensor data
    pass

client.set_video_frame_callback(on_video_frame)
client.set_sensor_data_callback(on_sensor_data)
```

## Technical Specifications

### Mobile App
- **Platform**: Android 5.0+ (API 21+)
- **Package Name**: `com.openbot.mobile_control`
- **Version Code**: 1
- **Framework**: Flutter 3.10+
- **Video Format**: JPEG (base64 encoded over WebSocket)
- **Sensor Update Rate**: Real-time (as available from device)

### Python SDK
- **Python Version**: 3.7+
- **Protocol**: WebSocket (ws://)
- **Default Port**: 8765
- **Dependencies**: websockets, asyncio

### Network Protocol
- **Transport**: WebSocket
- **Message Format**: JSON
- **Message Types**:
  - `video_frame`: Video data with timestamp
  - `sensor_data`: Sensor readings
  - `ping`/`pong`: Heartbeat mechanism

## Known Limitations

- iOS app not yet available (coming in future release)
- Video quality is fixed (settings page planned for v1.1)
- No robot control commands yet (planned feature)
- Debug signing used (suitable for testing, not Play Store distribution)

## Troubleshooting

### Connection Issues
- **Symptom**: Cannot connect to PC
- **Solutions**:
  - Verify both devices are on the same Wi-Fi network
  - Check PC firewall allows port 8765
  - Ensure correct IP address is entered
  - Try disabling PC firewall temporarily for testing

### No Video Stream
- **Symptom**: Black screen or no video
- **Solutions**:
  - Grant camera permission in Android app settings
  - Restart the app
  - Check if camera is being used by another app

### High Latency
- **Symptom**: Delayed video or sensor data
- **Solutions**:
  - Use 5GHz Wi-Fi if available
  - Reduce distance between phone and router
  - Check network bandwidth and close other apps

### App Crashes
- **Symptom**: App unexpectedly closes
- **Solutions**:
  - Clear app data in Android settings
  - Reinstall the app
  - Check device has Android 5.0 or higher

## System Requirements

### Mobile Device
- Android 5.0 (Lollipop) or higher
- Camera support
- Wi-Fi capability
- Minimum 100MB free storage

### PC
- Python 3.7 or higher
- Network connectivity
- Any OS (Windows, macOS, Linux)

## File Structure

```
openbot-mobile-control-v1.0.0/
├── openbot-mobile-control-v1.0.0.apk   # Android app (49.4MB)
├── python_sdk/                          # Python SDK
│   ├── openbot_sdk/                    # SDK source
│   ├── examples/                       # Example scripts
│   ├── requirements.txt                # Dependencies
│   └── README.md                       # SDK documentation
└── README.md                           # Project documentation
```

## What's Next (Roadmap)

### v1.1 (Planned)
- [ ] iOS app support
- [ ] Settings page (video quality, frame rate control)
- [ ] Improved error messages
- [ ] Network diagnostics tool

### v1.2 (Planned)
- [ ] Robot control commands (forward, backward, turn)
- [ ] Recording functionality
- [ ] Multiple camera support (front/back toggle)

### Future
- [ ] Google Play Store release
- [ ] Apple App Store release
- [ ] Bluetooth connectivity option
- [ ] Cloud streaming support

## Acknowledgments

This project is built with:
- **Flutter** - Google's UI framework for mobile apps
- **Python** - Backend SDK and examples
- **WebSocket** - Real-time communication protocol

## Support

- **Documentation**: See [README.md](README.md) in the repository
- **Issues**: Report bugs via GitHub Issues
- **Questions**: Check the troubleshooting section above

## License

This project is licensed under the MIT License.

---

**Download**: Get the APK from the release assets below

**Size**: 49.4 MB (Release APK)

**SHA256**: (Will be available after upload)

Built with Flutter and Python | Powered by OpenBot
