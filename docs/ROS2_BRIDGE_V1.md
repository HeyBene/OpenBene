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

## Recommended target environment for handoff

Recommended setup for the next Windows machine:

- Windows host for repository management and optional receiver process
- WSL2 Ubuntu 22.04 for ROS2 and Python bridge execution
- ROS2 distro: Humble

This keeps the ROS2 side close to a standard Ubuntu workflow and reduces
Windows-native ROS2 environment differences.

## WSL2 + ROS2 Humble minimal setup checklist

Inside Ubuntu 22.04:

1. Install Python 3.10 and common build tools
2. Install ROS2 Humble
3. Clone this repository into the Linux filesystem, for example:

```bash
mkdir -p ~/workspace
cd ~/workspace
git clone https://github.com/HeyBene/OpenBene.git
cd OpenBene
```

4. Install Python dependencies for the SDK/bridge

```bash
cd openbene_sdk
pip install -e .
```

5. Source ROS2 before running the bridge

```bash
source /opt/ros/humble/setup.bash
```

If a local ROS2 workspace is later added, also source its `install/setup.bash`
after sourcing `/opt/ros/humble/setup.bash`.

## Recommended path conventions on the new machine

- Repo root: `~/workspace/OpenBene`
- Session data root: `~/openbene_sessions`
- Avoid running the main ROS2 bridge workflow from `/mnt/c/...`

Using the Linux filesystem is preferred for file watching, Python IO, and fewer
path/permission surprises.

## First validation on the new ROS2 machine

Use a known-good session first, for example `session_1774409566`.

```bash
source /opt/ros/humble/setup.bash
python3 openbene_sdk/src/openbene/session_ros2_bridge.py \
  "~/openbene_sessions/session_1774409566" \
  --rate 1.0
```

Then in another terminal:

```bash
source /opt/ros/humble/setup.bash
ros2 topic list
ros2 topic echo /openbene/camera/pose
ros2 topic hz /openbene/camera/depth/image_raw
```

Expected result:
- bridge process keeps replaying frames without immediate import/runtime failure
- ROS2 topics appear
- pose topic can be echoed
- depth topic reports a non-zero publish rate

## Handoff note for receiver/live bridge split

Current recommended order is:
1. validate `session_ros2_bridge.py` replay first
2. then validate `live_ros2_bridge.py`
3. only after that, connect the full iPhone -> receiver -> watched directory -> ROS2 flow

This keeps debugging layered and avoids mixing network issues with ROS2 issues.

## Common environment pitfalls on the new machine

- ROS2 not sourced in the current shell
- repository cloned only on Windows filesystem and run from `/mnt/c/...`
- session path copied incorrectly between Windows and WSL2
- Python dependencies installed on Windows Python instead of WSL2 Python
- trying live bridge first before replay bridge is confirmed

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
