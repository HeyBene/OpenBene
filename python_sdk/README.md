# OpenBot Python SDK

Python SDK for receiving video streams and sensor data from the OpenBot mobile app.

## Features

- 📹 Real-time video streaming from mobile camera
- 📊 Sensor data reception (IMU, battery, voltage, etc.)
- 🔄 Automatic reconnection handling
- 🎯 Simple callback-based API
- 🚀 Easy to integrate

## Installation

```bash
cd python_sdk
pip install -r requirements.txt
```

Or install as a package:

```bash
pip install -e .
```

## Quick Start

```python
from openbot_sdk import OpenBotClient

# Create client
client = OpenBotClient(host="0.0.0.0", port=8765)

# Start server
client.start()

# Get latest data
frame = client.get_video_frame()  # Returns JPEG bytes
sensor_data = client.get_sensor_data()  # Returns dict

# Use callbacks for real-time processing
def on_frame(frame_bytes):
    print(f"Received frame: {len(frame_bytes)} bytes")

def on_sensor(data):
    print(f"Battery: {data.get('battery_level', 'N/A')}")

client.set_video_frame_callback(on_frame)
client.set_sensor_data_callback(on_sensor)
```

## API Reference

### OpenBotClient

#### Methods

- `__init__(host="0.0.0.0", port=8765)` - Initialize the client
- `start()` - Start the WebSocket server
- `stop()` - Stop the server
- `get_video_frame()` - Get latest video frame (JPEG bytes)
- `get_sensor_data()` - Get latest sensor data (dict)
- `set_video_frame_callback(callback)` - Set callback for video frames
- `set_sensor_data_callback(callback)` - Set callback for sensor data
- `is_connected()` - Check connection status
- `get_statistics()` - Get connection statistics

### Sensor Data Format

```python
{
    'accelerometer': {'x': 0.1, 'y': 0.2, 'z': 9.8},
    'gyroscope': {'x': 0.0, 'y': 0.0, 'z': 0.0},
    'magnetometer': {'x': 30.0, 'y': -20.0, 'z': 40.0},
    'battery_level': 0.85,  # 0.0 - 1.0
    'voltage': 12.6,
    'timestamp': '2025-12-30T12:00:00.000Z'
}
```

## Examples

### Display Video Stream

```bash
cd examples
python test_client.py
```

This will:
- Start a WebSocket server on port 8765
- Display incoming video stream with OpenCV
- Show sensor data overlay on video
- Print sensor updates to console

### Simple Example

```bash
cd examples
python simple_example.py
```

Basic example showing how to receive and log data.

## Requirements

- Python 3.8+
- websockets >= 12.0
- numpy >= 1.24.0
- opencv-python >= 4.8.0 (for video display examples)

## Network Configuration

The SDK runs a WebSocket server that listens for connections from the OpenBot mobile app.

**Default settings:**
- Host: `0.0.0.0` (all interfaces)
- Port: `8765`

**To connect from the mobile app:**
1. Ensure your PC and phone are on the same network
2. Find your PC's IP address (e.g., `192.168.1.100`)
3. In the app, enter: `192.168.1.100:8765`

## Troubleshooting

**Connection issues:**
- Check firewall settings (allow port 8765)
- Ensure PC and phone are on same network
- Verify IP address is correct

**No video frames:**
- Check camera permissions in the app
- Verify the app is streaming (check app UI)

**High latency:**
- Reduce video quality in the app settings
- Check network bandwidth
- Use a 5GHz Wi-Fi connection if available

## License

MIT License
