# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Community files (CONTRIBUTING.md, CODE_OF_CONDUCT.md)

---

## [2.2.0] - 2026-01-15

### Added
- `realtime_control()` method for WASD keyboard control
- Recording support during realtime control (press R to toggle)
- Comprehensive README with step-by-step tutorial
- FAQ section in documentation

### Changed
- Modularized SDK into independent components:
  - `connection.py` - WebSocket connection management
  - `motor.py` - Motor control
  - `video.py` - Video receiving
  - `sensors.py` - Sensor data
  - `recording.py` - Data collection
- Main `OpenBene` class now uses composition pattern
- Improved racing control responsiveness (turn_ratio: 0.4 → 0.15)
- Added motor deadzone compensation (min 35%)

### Removed
- Old TCP-based video module (`openbene/core/`)

---

## [2.1.0] - 2026-01-14

### Added
- Racing control example with drift mode
- Auto-install pynput dependency
- GitHub Issue templates (bug report, feature request)
- GitHub PR templates (English and Chinese)

### Fixed
- Racing control turn ratio for tighter arc turns

---

## [2.0.0] - 2026-01-12

### Changed
- **Breaking**: Simplified to WebSocket-only architecture
- Removed TCP video streaming (now uses WebSocket)
- Removed UDP sensor streaming (now uses WebSocket)

### Added
- Unified WebSocket communication for all data types
- MIT license attribution for OpenBot firmware

---

## [1.0.5] - 2026-01-05

### Changed
- Project reorganization
- Performance improvements

---

## [1.0.0] - 2026-01-04

### Added
- Initial release
- Python SDK for OpenBot control
- Flutter mobile app
- Arduino firmware integration
- Basic control commands (forward, backward, turn)
- Video streaming support
- Sensor data reading
- Data collection for training

---

## Version History Summary

| Version | Date | Highlights |
|---------|------|------------|
| 2.2.0 | 2026-01-15 | Modular SDK, realtime control |
| 2.1.0 | 2026-01-14 | Racing control, GitHub templates |
| 2.0.0 | 2026-01-12 | WebSocket-only architecture |
| 1.0.5 | 2026-01-05 | Project reorganization |
| 1.0.0 | 2026-01-04 | Initial release |
