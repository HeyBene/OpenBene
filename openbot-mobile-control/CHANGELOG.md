# Changelog

All notable changes to OpenBot Mobile Control will be documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.6] - 2026-02-13

### ✨ Added
- **UDP Auto-Discovery**: Phone now broadcasts its IP address every 2 seconds on UDP port 12345
- Python SDK can now use `OpenBene.auto_connect()` to automatically find and connect to phone
- Detailed logging for UDP broadcast status
- Clear APK download instructions in `releases/README.md`

### 🐛 Fixed
- **Architecture confusion**: Confirmed and documented phone-as-server model
- **Version inconsistency**: This is now the official version compiled from current codebase
- Unclear APK download location causing users to get wrong versions

### 📖 Documentation
- Added comprehensive `releases/README.md` with version verification guide
- Updated project README with prominent APK download instructions
- Added CHANGELOG to track version changes
- Added troubleshooting section for common UDP discovery issues

### 🔧 Technical Details
- UDP broadcast message format:
  ```json
  {
    "type": "discovery",
    "name": "OpenBot",
    "ip": "192.168.x.x",
    "port": 8765
  }
  ```
- Broadcast interval: 2 seconds
- Discovery port: 12345 (matches Python SDK)
- Network permissions verified in AndroidManifest.xml

### ⚠️ Breaking Changes
None - fully backward compatible with v1.0.5

---

## [1.0.5] - 2026-01-04

### Features
- Real-time video streaming from phone camera
- Sensor data transmission (accelerometer, gyroscope, battery)
- WebSocket communication on port 8765
- Phone as WebSocket server
- Multi-language support (English/Chinese)
- USB connection to OpenBot robot
- Modern Material Design 3 UI

### Known Issues (Fixed in v1.0.6)
- ❌ No UDP auto-discovery - `OpenBene.auto_connect()` fails
- ❌ Unclear APK download location
- ❌ No version verification method

---

## Version History Summary

| Version | Date | Key Feature |
|---------|------|-------------|
| 1.0.6 | 2026-02-13 | ✅ UDP Auto-Discovery |
| 1.0.5 | 2026-01-04 | Initial phone-as-server version |

---

## How to Verify Version

After installing APK, open the app and verify:

### Correct Version (1.0.6+)
- ✅ Shows "Server Address"
- ✅ Shows "Waiting for PC..."
- ✅ Displays phone IP address
- ✅ Has "Connect to OpenBot" button (for USB)

### Wrong Version
- ❌ Shows "Connection Settings"
- ❌ Has "PC IP Address" input field
- ❌ Says "Enter your PC's IP address"

If you see the wrong UI, uninstall and reinstall from `releases/` folder.
