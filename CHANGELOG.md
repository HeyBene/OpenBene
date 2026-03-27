# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Community files (CONTRIBUTING.md, CODE_OF_CONDUCT.md)
- Added a first session-aware real-time upload foundation for the LiDAR iOS app by introducing upload session descriptors plus a lightweight coordinator that can open a mapping session, stream accepted frames, and close the session without changing the local dataset-write source of truth in [UploadProtocol.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Transport/UploadProtocol.swift) and [CaptureUploadCoordinator.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Transport/CaptureUploadCoordinator.swift).

### Changed
- Added a first lightweight fused point-cloud side channel to the LiDAR capture workflow: the iOS app now accumulates a sparse session-end world-space point cloud from accepted LiDAR depth frames and, when the receiver advertises support, uploads it after the normal manifest without breaking the existing RGB/depth/transforms dataset flow in [LightweightPointCloudAccumulator.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Capture/LightweightPointCloudAccumulator.swift), [CaptureSessionManager.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Capture/CaptureSessionManager.swift), [UploadProtocol.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Transport/UploadProtocol.swift), [CaptureUploadCoordinator.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Transport/CaptureUploadCoordinator.swift), [WebSocketUploadClient.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Transport/WebSocketUploadClient.swift), and [capture_receiver.py](openbene_sdk/src/openbene/capture_receiver.py).
- Surfaced receiver point-cloud capability and per-session point-cloud generation status in the capture UI so users can tell whether a session produced the new lightweight geometry artifact without opening exported files in [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift) and [CaptureSessionManager.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Capture/CaptureSessionManager.swift).
- Extended the capture state model with workflow phases, capture duration, and latest-session summary data to support the new camera-style UI without duplicating state logic in the view in [CaptureSessionManager.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Capture/CaptureSessionManager.swift).
- Switched the capture workflow to a manual-first interaction model with `Prepare / Capture / Result` staging, a single main button for `Start Session / Capture Frame`, and a separate finish action while keeping auto capture as a secondary mode in [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift) and [CaptureSessionManager.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Capture/CaptureSessionManager.swift).
- Replaced the fake preview placeholder with a live AR camera preview, added an in-app dataset location card plus share/export entry, and surfaced the current capture folder directly in the capture UI so on-device validation no longer depends on guessing the sandbox path in [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift).
- Updated the capture manager to retain the current dataset folder URL and make manual mode start a session and immediately become ready for real frame capture instead of silently consuming the first tap in [CaptureSessionManager.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Capture/CaptureSessionManager.swift).
- Extended the WebSocket upload path and Python receiver to exchange explicit `session_start` / `session_end` messages with session metadata, and wired the iOS capture flow to open and close mapping uploads through capture lifecycle callbacks in [WebSocketUploadClient.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Transport/WebSocketUploadClient.swift), [CaptureSessionManager.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Capture/CaptureSessionManager.swift), [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift), and [capture_receiver.py](openbene_sdk/src/openbene/capture_receiver.py).
- Replaced the hardcoded loopback receiver with a persisted configurable WebSocket endpoint and a minimal in-app connection card so capture sessions can target a real LAN receiver and surface upload status directly in [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift) and [CaptureUploadCoordinator.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Transport/CaptureUploadCoordinator.swift).
- Added receiver-side status replies plus minimal address validation and session feedback in the iOS app so LAN bring-up failures are easier to diagnose before full mapping/localization integration in [capture_receiver.py](openbene_sdk/src/openbene/capture_receiver.py), [WebSocketUploadClient.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Transport/WebSocketUploadClient.swift), and [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift).
- Added a small LAN test aid by showing the current WebSocket target inside the app and printing a clearer session summary when the Python receiver finalizes a session in [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift) and [capture_receiver.py](openbene_sdk/src/openbene/capture_receiver.py).
- Added a first Phase 2 mode split by exposing `mapping` / `localization` session modes in the iOS capture UI and sending the selected mode through the existing session-aware upload protocol so later localization-only backend work can branch cleanly from the same transport path in [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift), [UploadProtocol.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Transport/UploadProtocol.swift), and [capture_receiver.py](openbene_sdk/src/openbene/capture_receiver.py).
- Fixed the Python receiver's status-reply path so session feedback no longer crashes on `session_start` / `session_end`, allowing Phase 2 mode verification to complete cleanly in [capture_receiver.py](openbene_sdk/src/openbene/capture_receiver.py).
- Added an MVP in-app capture quality diagnostic flow with live Chinese advisories, session-end quality reports, and more conservative auto-mode rejection for unstable tracking or suspicious pose jumps in [CaptureQualityReport.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Models/CaptureQualityReport.swift), [CaptureSessionManager.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Capture/CaptureSessionManager.swift), [FrameAcceptancePolicy.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Capture/FrameAcceptancePolicy.swift), and [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift).
- Promoted the lightweight fused point cloud from a side-channel-only artifact to a first-class session output by writing `fused_pointcloud.ply` into the local capture folder and surfacing its presence directly in the result card alongside the quality recommendation in [CaptureSessionManager.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/Capture/CaptureSessionManager.swift) and [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift).
- Hardened the Python receiver for repeated wireless sessions by resetting per-session state on `session_start`, allocating a fresh output folder per uploaded session, returning the resolved output path to the app, and raising the WebSocket message size limit so larger session-end point-cloud uploads no longer disconnect mid-transfer in [capture_receiver.py](openbene_sdk/src/openbene/capture_receiver.py).
- Simplified the LiDAR capture home screen by removing the unused stage strip and merging mode controls so the main preview and active capture guidance are less cluttered while preserving the current workflow in [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift).
- Further reduced capture-page clutter by removing the duplicated side mode toggle so session mode and capture mode now live in a single compact control row around the shutter area in [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift).
- Compressed the connection card into a summary-first layout that shows status and target address by default, keeping error text and manual connection controls behind expansion in [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift).
- Further tightened the capture result area by shortening the dataset-location card and making the quality report grid denser, so the home screen keeps more attention on live preview and the main controls in [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift).
- Removed the standalone readiness bar and folded its status text back into the main control area after simulator review showed the extra bar was still crowding the preview in [RootView.swift](openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/UI/RootView.swift).

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
