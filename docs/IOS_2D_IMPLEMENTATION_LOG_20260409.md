# iOS 2D Capture/Upload Implementation Log (2026-04-09)

This file records what was implemented on the iOS app side for the 2D ROS2 route.

## Scope

Implemented for `openbene-lidar-capture-ios/Lidarcapture/Lidarcapture/`:

1. Prefer `smoothedSceneDepth` with fallback to `sceneDepth`
2. Capture and encode `confidenceMap`
3. Record frame-level `tracking_state`
4. Real-time `localization` upload changed to depth-only (no RGB)
5. Manifest extended with 2D quality fields

## Changed files

- `Models/CaptureFrameRecord.swift`
- `Capture/CaptureSessionManager.swift`
- `Transport/UploadProtocol.swift`
- `Transport/PreparedFrameEncoder.swift`
- `Transport/WebSocketUploadClient.swift`
- `Transport/CaptureUploadCoordinator.swift`
- `Dataset/NerfstudioDatasetWriter.swift`

## Key changes

### 1) Frame model (`CaptureFrameRecord`)

- Added:
  - `trackingStateRaw`
  - `depthSourceRaw`
  - `confidenceBuffer`
  - `confidenceWidth`
  - `confidenceHeight`
- Depth source policy:
  - prefer `frame.smoothedSceneDepth` (when available)
  - fallback to `frame.sceneDepth`
  - else `depth_source = "none"`
- Tracking state normalized to stable strings:
  - `normal`
  - `not_available`
  - `limited_initializing`
  - `limited_excessive_motion`
  - `limited_insufficient_features`
  - `limited_relocalizing`
  - `limited_unknown`

### 2) Session setup (`CaptureSessionManager`)

- LiDAR semantics now prefer `smoothedSceneDepth` if supported.
- Fallback to `sceneDepth` when `smoothedSceneDepth` is unavailable.

### 3) Payload protocol (`UploadProtocol`)

- `PreparedCaptureFramePayload` now supports:
  - `rgbJPEGData: Data?`
  - `depthPNGData: Data?`
  - `confidencePNGData: Data?`
- `sendRealtimeFrame` signature changed:
  - from `sendRealtimeFrame(_ record: CaptureFrameRecord)`
  - to `sendRealtimeFrame(_ payload: PreparedCaptureFramePayload)`

### 4) Frame encoding (`PreparedFrameEncoder`)

- Added confidence PNG encoder (`encodeConfidenceAsPNGData`).
- Payload preparation now emits:
  - optional RGB JPEG
  - optional 16-bit depth PNG
  - optional confidence PNG (single-channel grayscale)

### 5) Realtime upload behavior (`WebSocketUploadClient`)

- Session upload (`transfer_mode = "session"`):
  - sends image/depth/confidence conditionally
  - metadata now includes:
    - `has_image`
    - `has_depth`
    - `has_confidence`
    - `tracking_state`
    - `depth_source`
    - `confidence_width`
    - `confidence_height`
- Realtime upload (`transfer_mode = "live"`):
  - no RGB
  - requires depth
  - sends depth + optional confidence

### 6) Upload coordinator (`CaptureUploadCoordinator`)

- `localization` mode now passes prepared payload directly into realtime sender.

### 7) Dataset writing (`NerfstudioDatasetWriter`)

- Added optional `confidence/` directory.
- Writes confidence PNGs when available.
- Each frame entry in `transforms.json` now includes:
  - `tracking_state`
  - `depth_source`
  - optional `confidence_file_path`

## Expected receiver-side frame metadata (live 2D)

`frame` metadata now carries:

- `has_image = false`
- `has_depth = true`
- `has_confidence = true/false`
- `tracking_state`
- `depth_source`
- depth/confidence dimensions

Binary order remains conditional and deterministic:

1. image (if `has_image`)
2. depth (if `has_depth`)
3. confidence (if `has_confidence`)

## What still needs Mac verification

Windows side cannot run Xcode build here. Please verify on Mac:

1. Build and run app in Xcode.
2. Mapping mode export:
   - confirm `images/`, `depth/`, and `confidence/` are created as expected.
   - confirm `transforms.json` has `tracking_state`, `depth_source`, `confidence_file_path`.
3. Localization mode live upload:
   - confirm real-time stream works without RGB.
   - confirm depth frames continue to arrive.
   - confirm confidence frames arrive when available.
4. Validate that `depth_source` prefers `smoothed_scene_depth` on supported devices.
