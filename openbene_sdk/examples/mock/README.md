# Mock Camera Server

Mock video stream server for testing OpenBene video streaming without real hardware.

## What It Does

Simulates an OpenBene robot's camera by generating colorful test pattern frames and streaming them via TCP using the standard protocol:

- **Header:** 4 bytes (Big-Endian uint32) indicating JPEG size
- **Body:** JPEG image bytes

## Usage

### Start Mock Camera

```bash
# Default settings (port 8000, 30 FPS, 640x480)
python mock_camera.py

# Custom settings
python mock_camera.py --port 8000 --fps 30 --size 640x480 --quality 80
```

### Options

- `--port`: TCP port to listen on (default: 8000)
- `--fps`: Frames per second (default: 30)
- `--size`: Frame size WxH (default: 640x480)
- `--quality`: JPEG quality 0-100 (default: 80)

## Test the Mock Camera

In a separate terminal:

```bash
cd ..
python video_view.py --ip 127.0.0.1 --port 8000
```

You should see a window displaying the colorful test pattern with frame counter and FPS overlay.

## What You'll See

The mock camera generates frames with:
- Colorful random noise background
- Gradient overlays
- Frame counter
- FPS indicator
- Resolution display
- "MOCK CAMERA" label

## Protocol Details

The mock camera implements the exact same protocol as the real OpenBene robot:

```python
# For each frame:
1. Generate/capture frame
2. Encode to JPEG
3. Pack header: struct.pack('>I', jpeg_size)
4. Send: header (4 bytes) + jpeg_data
```

This ensures perfect compatibility with the `VideoReceiver` class in the SDK.
