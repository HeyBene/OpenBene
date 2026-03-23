# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Community files (CONTRIBUTING.md, CODE_OF_CONDUCT.md)

### Changed
- Redesigned the LiDAR capture app home screen into a camera-first layout with a large preview area, bottom control bar, live status badges, and a latest-capture summary so the main workflow is clearer during capture and reconstruction validation in [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift).
- Extended the capture state model with workflow phases, capture duration, and latest-session summary data to support the new camera-style UI without duplicating state logic in the view in [CaptureSessionManager.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Capture/CaptureSessionManager.swift).
- Switched the capture workflow to a manual-first interaction model with `Prepare / Capture / Result` staging, a single main button for `Start Session / Capture Frame`, and a separate finish action while keeping auto capture as a secondary mode in [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift) and [CaptureSessionManager.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Capture/CaptureSessionManager.swift).
- Replaced the fake preview placeholder with a live AR camera preview, added an in-app dataset location card plus share/export entry, and surfaced the current capture folder directly in the capture UI so on-device validation no longer depends on guessing the sandbox path in [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift).
- Updated the capture manager to retain the current dataset folder URL and make manual mode start a session and immediately become ready for real frame capture instead of silently consuming the first tap in [CaptureSessionManager.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Capture/CaptureSessionManager.swift).

### Fixed
- iOS LiDAR capture app now builds again by updating PNG export code to use modern `UniformTypeIdentifiers` / `ImageIO` APIs in [NerfstudioDatasetWriter.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Dataset/NerfstudioDatasetWriter.swift).
- iOS LiDAR capture app generated Info.plist now includes camera and local network usage descriptions in [project.pbxproj](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture.xcodeproj/project.pbxproj) so on-device testing can request the required permissions.
- Lowered the `Lidarcapture` deployment target from iOS 18.2 to iOS 16.0 in [project.pbxproj](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture.xcodeproj/project.pbxproj) to match the intended ARKit/LiDAR testing baseline.
- Verified `Lidarcapture` builds successfully for both `generic/platform=iOS Simulator` and `generic/platform=iOS` with the updated project settings.

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
