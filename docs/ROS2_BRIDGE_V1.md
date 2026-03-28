# ROS2 Bridge v1

Current implementation entry point:
- `openbene_sdk/src/openbene/session_ros2_bridge.py`

## Purpose

Bridge OpenBene capture sessions into ROS2 camera topics before adding live
WebSocket receiver -> ROS2 streaming.

This is the fastest practical route to a ROS2-ready state because it allows:
- validating topic structure
- validating downstream ROS2 consumers
- replaying known-good sessions repeatedly

## Current mode

- Mode: session replay
- Input: exported session directory with `images/`, `depth/`, `transforms.json`
- Output topics:
  - `/openbene/camera/rgb/image_raw/compressed`
  - `/openbene/camera/depth/image_raw`
  - `/openbene/camera/camera_info`
  - `/openbene/camera/pose`

## Dry run on non-ROS machines

Use this on macOS or any machine without ROS2 installed:

```bash
python3 openbene_sdk/src/openbene/session_ros2_bridge.py \
  "/Users/fandi/Downloads/session_1774588130" \
  --dry-run
```

## Expected run command on a ROS2 machine

```bash
python3 openbene_sdk/src/openbene/session_ros2_bridge.py \
  "/path/to/session" \
  --rate 1.0
```

## Recommended first ROS2 validation steps

After sourcing the ROS2 environment on the target machine:

1. Start the bridge on a known-good session
2. In another terminal, verify topics:

```bash
ros2 topic list
ros2 topic echo /openbene/camera/pose
ros2 topic hz /openbene/camera/depth/image_raw
```

## Next bridge step

After replay mode is validated, implement live mode:

- input becomes WebSocket receiver frames
- output topic layout stays the same
- session replay remains the debugging and regression mode

## Live bridge skeleton

Current scaffold entry point:
- `openbene_sdk/src/openbene/live_ros2_bridge.py`

Dry-run on macOS:

```bash
python3 openbene_sdk/src/openbene/live_ros2_bridge.py \
  --watch-dir "/Users/fandi/Desktop/OpenBene_git/captured_data" \
  --dry-run
```

Single-pass simulation:

```bash
python3 openbene_sdk/src/openbene/live_ros2_bridge.py \
  --watch-dir "/Users/fandi/Downloads" \
  --dry-run \
  --once
```

Intended future live path:

- iPhone sends frames to receiver
- receiver writes session directories under the watched root
- live bridge notices new session/frame data
- live bridge publishes the same camera topics as replay mode
- live bridge also publishes `/openbene/session/state`
