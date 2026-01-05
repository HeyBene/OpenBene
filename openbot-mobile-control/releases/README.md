# OpenBot Mobile Control - Releases

This directory contains all APK release files for the OpenBot Mobile Control app.

## Latest Release

**Version 1.0.5** - 2026-01-04
- File: `openbot-mobile-control-v1.0.5.apk`
- Size: 48 MB
- **Performance improvements**: Significantly improved scrolling performance

[View full changelog](../docs/CHANGELOG.md)

## Download & Install

### Method 1: Direct Download (Recommended)

If you have the project on your PC:
```bash
# Copy APK to your phone via USB or cloud storage
adb install releases/openbot-mobile-control-v1.0.5.apk
```

### Method 2: HTTP Server Download

Start an HTTP server to download on your phone:
```bash
cd /Users/zhangzhiyuan/Projects/my_app
python3 -m http.server 8000 --bind <YOUR_PC_IP>
```

Then on your phone's browser, visit:
```
http://<YOUR_PC_IP>:8000/releases/
```

## Version History

### v1.0.5 (2026-01-04) - Current
- **Major performance improvements**
- Optimized UI refresh rate (100ms → 300ms)
- Smart repaint mechanism with RepaintBoundary
- Better scrolling experience

### v1.0.4 (2026-01-04)
- Sensor dashboard localization (Chinese/English)
- Initial scrolling optimizations
- ListView implementation

### v1.0.3 (2026-01-04)
- Fixed control screen language switching
- Fixed black screen on disconnect

### v1.0.2 (2026-01-04)
- Added Chinese/English language switching
- Fixed WebSocket server compatibility

### v1.0.1 (2026-01-04)
- Fixed input field interaction
- Fixed Android 13+ permission issues

### v1.0.0 (2026-01-04)
- Initial release
- Real-time video streaming
- Sensor data transmission
- WebSocket communication

## Requirements

- Android 5.0 (Lollipop) or higher
- ~100MB free storage space
- Camera permission

## Installation Issues?

See [Quick Start Guide](../docs/QUICK_START.md) for troubleshooting.

---

For detailed release notes, see [CHANGELOG.md](../docs/CHANGELOG.md)
