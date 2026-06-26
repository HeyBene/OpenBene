# OpenBene Scope

`OpenBene` after cleanup is intended to stay focused on reusable platform-layer work.

## Keep In OpenBene

- `openbene_sdk/` core SDK
- WebSocket / discovery / recording / sensor / video platform code
- BLE control utilities that are generic to OpenBot / ESP32 manual control
- `openbot-mobile-control/` source code
- `apps/robot_app/` source code
- `openbot/` firmware / hardware-side baseline
- community / release / general platform docs

## Keep Out Of OpenBene Git Tracking

These may still exist locally on this machine, but they are no longer intended to be part of the OpenBene Git scope:

- local staging tree: `openbene_mobility/`
- `openbene_ros2/`
- `openbene-lidar-capture-ios/`
- ROS2 / mapping / localization / relocalization docs
- session map-building / relocalization / ROS2 bridge helper scripts inside `openbene_sdk/src/openbene/`

The tracked home for that line is now:

- `HeyBene/BeneMobility`

## Practical Rule

- If a change is reusable platform capability, keep it in `OpenBene`.
- If a change is ROS2 / mapping / localization / navigation integration, keep it out of `OpenBene` and manage it in `BeneMobility`.
- If a `BeneMobility` change later proves reusable for OpenBot / platform workflows, backport it selectively instead of keeping two long-lived divergent copies.
