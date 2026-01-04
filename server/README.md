# Server Components

This directory contains the server-side components for OpenBot Mobile Control.

## Contents

- **`test_server.py`** - WebSocket test server for receiving video and sensor data
- **`python_sdk/`** - Python SDK for integrating OpenBot with your applications

## Quick Start

### 1. Install Dependencies

```bash
pip3 install -r python_sdk/requirements.txt
```

This will install:
- `websockets` - WebSocket server library
- `opencv-python` - For video processing (optional)

### 2. Start the Test Server

```bash
python3 test_server.py
```

The server will:
- Start a WebSocket server on port 8765
- Display your PC's IP address for connection
- Accept connections from the mobile app
- Display received video frames and sensor data

Example output:
```
🚀 WebSocket服务器启动成功！
📱 请在手机APP中输入以下信息：

IP地址: 192.168.1.100
端口号: 8765

等待客户端连接...
```

### 3. Configure Firewall

Make sure port 8765 is open in your firewall:

**Windows:**
```powershell
New-NetFirewallRule -DisplayName "OpenBot Server" -Direction Inbound -Port 8765 -Protocol TCP -Action Allow
```

**macOS/Linux:**
```bash
sudo ufw allow 8765
```

## Python SDK Usage

The Python SDK allows you to integrate OpenBot data into your own applications.

### Installation

```bash
cd python_sdk
pip3 install -e .
```

### Basic Example

```python
from openbot_sdk import OpenBotServer

async def handle_video_frame(frame_data):
    """Process received video frame"""
    print(f"Received video frame: {len(frame_data)} bytes")
    # Process frame with OpenCV, TensorFlow, etc.

async def handle_sensor_data(sensor_data):
    """Process received sensor data"""
    print(f"Accelerometer: {sensor_data['accelerometer']}")
    print(f"Gyroscope: {sensor_data['gyroscope']}")
    print(f"Battery: {sensor_data['battery_level']}%")

# Create and start server
server = OpenBotServer(
    host='0.0.0.0',
    port=8765,
    on_video_frame=handle_video_frame,
    on_sensor_data=handle_sensor_data
)

await server.start()
```

### Advanced Examples

See `python_sdk/examples/` for more examples:
- `basic_server.py` - Simple server setup
- `opencv_display.py` - Display video with OpenCV
- `data_logger.py` - Log sensor data to file

## Server Protocol

The server communicates with the mobile app using WebSocket protocol with JSON messages.

### Message Types

**1. Video Frame**
```json
{
  "type": "video_frame",
  "timestamp": 1234567890,
  "frame": "base64_encoded_jpeg_data"
}
```

**2. Sensor Data**
```json
{
  "type": "sensor_data",
  "timestamp": 1234567890,
  "accelerometer": {"x": 0.1, "y": 0.2, "z": 9.8},
  "gyroscope": {"x": 0.01, "y": 0.02, "z": 0.03},
  "battery_level": 0.85
}
```

**3. Heartbeat**
```json
{
  "type": "heartbeat",
  "timestamp": 1234567890
}
```

## Troubleshooting

### Connection Issues

1. **App can't connect to server**
   - Check that PC and phone are on the same WiFi network
   - Verify IP address is correct
   - Check firewall settings
   - Try disabling VPN

2. **Server crashes on video frame**
   - Install OpenCV: `pip3 install opencv-python`
   - Check video frame decoding in your handler

3. **High latency**
   - Reduce video quality in the app
   - Check network bandwidth
   - Use 5GHz WiFi if available

### Performance Tips

- Use `asyncio` for non-blocking operations
- Process frames in a separate thread/process
- Adjust camera resolution in the app (default: 640px width)
- Reduce sensor update rate if needed

## Development

### Running Tests

```bash
cd python_sdk
python3 -m pytest tests/
```

### Building the SDK

```bash
cd python_sdk
python3 setup.py sdist bdist_wheel
```

## Support

For issues and questions:
- Check the main documentation: [../docs/README.md](../docs/README.md)
- Review examples: `python_sdk/examples/`
- Open an issue on GitHub

---

Made with Python 🐍
