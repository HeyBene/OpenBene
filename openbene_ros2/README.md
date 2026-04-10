# openbene_ros2

`openbene_ros2` is the current ROS 2 entry point for this repository.

There are now two ROS 2 data lines:

- camera-topic line
  publish RGB/depth/pose topics from a saved session or a watched receiver directory
- mapping `/scan` line
  convert OpenBene depth data into `sensor_msgs/msg/LaserScan` for future `slam_toolbox`

What works today:

- `doctor`
  Check whether ROS 2 and the local `openbene_sdk` are ready.
- `cmd_vel_bridge`
  Subscribe to `geometry_msgs/msg/Twist` on `/cmd_vel` and convert it to
  OpenBene differential wheel commands.
- `safety_cmd_vel`
  Subscribe to `/cmd_vel_user` plus `/scan`, then publish a safer `/cmd_vel_safe`
  with speed limits, forward obstacle slowdown / stop, and command-timeout stop.
- `cmd_vel_keyboard`
  Publish manual keyboard teleop commands to `/cmd_vel_user` for the semi-auto stack.
- `dry_run_demo.launch.py`
  Start a no-hardware demo that runs the bridge and a demo `/cmd_vel` publisher
  together.
- `dataset_scan_replay`
  Replay an OpenBene LiDAR capture dataset from `transforms.json + depth/*.png`
  as a ROS 2 `/scan` topic.
- `session_camera_replay`
  Replay a saved OpenBene session into RGB/depth/camera_info/pose ROS 2 topics.
- `live_camera_bridge`
  Watch receiver output directories and publish RGB/depth/camera_info/pose ROS 2 topics.
- `live_capture_scan_server`
  Accept the OpenBene iPhone LiDAR WebSocket upload protocol, save each capture
  session to disk, and publish `/scan` from incoming depth frames.
- `dataset_relocalization`
  Run one-shot geometry relocalization for a saved session against a baseline
  map point cloud and publish the result on `/openbene/relocalization/*`.
- `relocalization_initialpose_bridge`
  Convert a relocalization `PoseStamped` into `/initialpose` for AMCL / Nav2 style consumers.
- `lifecycle_bringup`
  Configure and activate simple lifecycle nodes such as `nav2_map_server/map_server`.

If you are new to WSL or ROS 2, start with:

- `../docs/ROS2_BEGINNER_RUNBOOK.md`

## 1. Prerequisites

Inside Ubuntu / WSL:

```bash
source /opt/ros/humble/setup.bash
python3 -m pip install -e /path/to/OpenBene/openbene_sdk
```

If you just pulled the latest iOS transport / bridge updates, run that editable
install command again so new Python dependencies are picked up. The camera-topic
bridge now needs `Pillow`, which is included once the SDK dependencies are
refreshed.

If this repository is on your Windows desktop, the path will usually be:

```bash
python3 -m pip install -e /mnt/c/Users/<your-user>/Desktop/OpenBene/openbene_sdk
```

## 2. Build in a ROS 2 workspace

Create a workspace if you do not already have one:

```bash
mkdir -p ~/ros2_ws/src
cd ~/ros2_ws/src
```

Symlink this package into `~/ros2_ws/src/`:

```bash
ln -s /path/to/OpenBene/openbene_ros2 ~/ros2_ws/src/openbene_ros2
```

Build:

```bash
cd ~/ros2_ws
source /opt/ros/humble/setup.bash
colcon build --packages-select openbene_ros2
source install/setup.bash
```

## 3. Run the environment check

```bash
ros2 run openbene_ros2 doctor
```

## 4. No-hardware smoke test

Single-command demo:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 dry_run_demo.launch.py
```

Expected logs include lines like:

```text
Bridge started in dry_run mode. Listening on topic '/cmd_vel'.
[dry_run] cmd_vel -> drive(0.300, 0.300)
```

Manual two-terminal test:

Terminal 1:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 cmd_vel_bridge.launch.py dry_run:=true
```

Terminal 2:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 topic pub --once /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.3}, angular: {z: 0.0}}"
```

## 5. Real hardware later

When phone testing is available again, set the phone app server IP:

```bash
export OPENBENE_SERVER_IP=192.168.1.100
```

Then run:

```bash
ros2 launch openbene_ros2 cmd_vel_bridge.launch.py ip:=192.168.1.100
```

## 5a. Semi-auto safety layer v1

The current baseline for semi-automatic mapping / teleop is recorded in:

- `../docs/SEMI_AUTO_SAFETY_V1_20260409.md`

Launch the safety layer alone:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 safety_cmd_vel.launch.py
```

Default topic flow:

- `/cmd_vel_user`
- `/scan`
- `/cmd_vel_safe`
- `/openbene/safety/status`

Launch the full semi-auto chain into the existing OpenBene drive bridge:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 semi_auto_cmd_vel.launch.py dry_run:=true
```

The v1 baseline parameters are:

- `max_linear_speed_mps = 0.15`
- `max_angular_speed_radps = 0.50`
- `slowdown_distance_m = 0.35`
- `stop_distance_m = 0.20`
- `command_timeout_sec = 0.30`
- `front_sector_half_angle_deg = 30.0`

Minimal two-terminal operator flow:

Terminal 1:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 semi_auto_cmd_vel.launch.py dry_run:=true
```

Terminal 2:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run openbene_ros2 cmd_vel_keyboard
```

Keyboard controls:

- `w` forward
- `s` reverse
- `a` turn left
- `d` turn right
- `q` forward-left arc
- `e` forward-right arc
- `space` / `x` stop
- `h` print help
- `ESC` quit

## 6. Offline depth replay for mapping prep

If you later capture a LiDAR session with the iPhone app and get a directory like
this:

```text
session_xxx/
  transforms.json
  images/
  depth/
```

you can replay its depth data into a ROS 2 `/scan` topic:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run openbene_ros2 dataset_scan_replay --ros-args -p dataset_dir:=/path/to/session_xxx
```

Launch file version:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 dataset_scan_replay.launch.py dataset_dir:=/path/to/session_xxx
```

This node:

- reads `transforms.json`
- loads each `depth/*.png`
- scales camera intrinsics to the depth image resolution
- projects a horizontal depth band into `sensor_msgs/msg/LaserScan`

Useful parameters:

- `dataset_dir`
- `scan_topic`
- `camera_info_topic`
- `frame_id`
- `publish_period_sec`
- `band_center_ratio`
- `band_height`
- `range_min_m`
- `range_max_m`
- `confidence_min_value`
- `accepted_tracking_states`
- `allow_missing_tracking_state`
- `accepted_depth_sources`
- `allow_missing_depth_source`
- `repeat`
- `publish_odom_tf`
- `odom_frame`
- `base_frame`

Example with a slower replay:

```bash
ros2 run openbene_ros2 dataset_scan_replay --ros-args \
  -p dataset_dir:=/path/to/session_xxx \
  -p publish_period_sec:=0.5 \
  -p repeat:=false
```

If you want to feed the replay directly into `slam_toolbox`, also enable odom TF
projection from the session poses:

```bash
ros2 run openbene_ros2 dataset_scan_replay --ros-args \
  -p dataset_dir:=/path/to/session_xxx \
  -p repeat:=false \
  -p publish_odom_tf:=true \
  -p odom_frame:=odom \
  -p base_frame:=openbene_base
```

## 7. Camera-topic replay from a saved session

The newly pulled upstream bridge work is now exposed through the same
`openbene_ros2` package. To replay a saved session into camera topics:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run openbene_ros2 session_camera_replay /path/to/session_xxx --dry-run
```

Actual ROS 2 replay:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run openbene_ros2 session_camera_replay /path/to/session_xxx --rate 1.0
```

Topics:

- `/openbene/camera/rgb/image_raw/compressed`
- `/openbene/camera/depth/image_raw`
- `/openbene/camera/camera_info`
- `/openbene/camera/pose`

## 8. Live camera-topic bridge from receiver output

If you use the newer iPhone -> PC receiver flow that writes session directories
to disk first, you can watch that directory and publish the same camera topics:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run openbene_ros2 live_camera_bridge --watch-dir /path/to/openbene_sessions --dry-run --once
```

When run without `--dry-run`, this bridge also publishes:

- `/openbene/session/state`

## 9. Live capture server for future phone testing

When phone testing becomes available again, this package also includes a live
WebSocket receiver node:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run openbene_ros2 live_capture_scan_server
```

Launch file version:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 live_capture_scan_server.launch.py
```

What it does:

- listens for the iPhone LiDAR upload protocol on `ws://0.0.0.0:8765`
- writes each session under `~/openbene_captured_sessions` by default
- saves `images/`, `depth/`, `transforms.json`, and uploaded point clouds
- publishes a live `/scan` topic from each incoming depth PNG

Useful parameters:

- `host`
- `port`
- `output_root_dir`
- `scan_topic`
- `camera_info_topic`
- `frame_id`
- `band_center_ratio`
- `band_height`
- `range_min_m`
- `range_max_m`
- `confidence_min_value`
- `accepted_tracking_states`
- `allow_missing_tracking_state`
- `accepted_depth_sources`
- `allow_missing_depth_source`
- `publish_odom_tf`
- `odom_frame`
- `base_frame`

Example with a custom output directory:

```bash
ros2 run openbene_ros2 live_capture_scan_server --ros-args \
  -p output_root_dir:=/home/jiken/openbene_sessions \
  -p port:=8765
```

Future live mapping can also enable TF projection from incoming poses:

```bash
ros2 run openbene_ros2 live_capture_scan_server --ros-args \
  -p publish_odom_tf:=true \
  -p odom_frame:=odom \
  -p base_frame:=openbene_base
```

2D quality gate example (recommended default):

```bash
ros2 run openbene_ros2 live_capture_scan_server --ros-args \
  -p confidence_min_value:=1 \
  -p accepted_tracking_states:=normal \
  -p allow_missing_tracking_state:=false \
  -p accepted_depth_sources:=smoothed_scene_depth \
  -p allow_missing_depth_source:=false
```

This keeps only frames with:

- `tracking_state == normal`
- confidence values >= `confidence_min_value`
- `depth_source == smoothed_scene_depth`

No-phone self-test:

Terminal 1:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run openbene_ros2 live_capture_scan_server
```

Terminal 2:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run openbene_ros2 mock_capture_client
```

If you prefer a single helper script from the repository:

```bash
bash /mnt/c/Users/<your-user>/Desktop/OpenBene/openbene_ros2/scripts/run_mock_live_test.sh
```

The protocol handler and ROS 2 package wiring are tested, but end-to-end phone
validation is still pending because real-device testing is currently skipped.
The no-phone mock client path has been validated in WSL.

Its receiver handshake has now been aligned with the newer iOS transport flow,
including:

- `output_dir`
- `live_localization_v1`
- `session_saved`

## 10. Offline relocalization bridge

If you already have:

- a baseline map point cloud such as `map_tsdf_pointcloud.ply`
- a second OpenBene session you want to locate inside that map

you can now publish the relocalization result directly into ROS 2:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run openbene_ros2 dataset_relocalization --ros-args \
  -p session_dir:=/path/to/localization_session \
  -p map_pointcloud:=/path/to/mapping_session/map_tsdf/map_tsdf_pointcloud.ply
```

If Open3D is inconvenient in WSL, you can also compute the report on Windows
first and then publish that precomputed report into ROS 2:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run openbene_ros2 dataset_relocalization --ros-args \
  -p report_path:=/path/to/localization_session/relocalization_report.json
```

Launch file version:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 dataset_relocalization.launch.py \
  session_dir:=/path/to/localization_session \
  map_pointcloud:=/path/to/mapping_session/map_tsdf/map_tsdf_pointcloud.ply
```

Report-based launch version:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 dataset_relocalization.launch.py \
  report_path:=/path/to/localization_session/relocalization_report.json
```

Published topics:

- `/openbene/relocalization/initial_guess`
- `/openbene/relocalization/refined_pose`
- `/openbene/relocalization/fitness`
- `/openbene/relocalization/status`

Notes:

- this is a first-pass bridge around the existing Open3D relocalization flow
- it still depends on the local `openbene_sdk`
- it requires `Open3D` only when you ask it to compute relocalization in-place
- if you pass `report_path`, it can reuse a precomputed JSON report instead
- it is best described today as an offline-to-ROS2 bridge, not a full live localization stack

The status topic publishes a compact JSON string with:

- `state`
- `report_path`
- `global_fitness`
- `global_rmse`
- `fine_icp_fitness`
- `fine_icp_rmse`

If you want to inspect the entire JSON payload without truncation:

```bash
ros2 topic echo --once /openbene/relocalization/status --field data --full-length
```

## 11. Seed `/initialpose` From Relocalization

To convert the relocalization pose into a Nav2 / AMCL style `/initialpose`:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run openbene_ros2 relocalization_initialpose_bridge
```

Launch file version:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 relocalization_initialpose_bridge.launch.py
```

Useful parameters:

- `source_pose_topic`
- `initialpose_topic`
- `target_frame`
- `xy_stddev`
- `yaw_stddev`
- `force_zero_z`
- `use_zero_stamp`
- `repeat_count`
- `repeat_interval_sec`

Important note:

- this bridge republishes the incoming pose into `/initialpose`
- in offline replay workflows, `use_zero_stamp:=true` helps AMCL use the latest available TF instead of a stale wall-clock timestamp
- it is only meaningful when the relocalization pose is already expressed in the same map frame that Nav2 is using
- for first experiments, treat it as a helper for seeding navigation, not proof that the 3D point-cloud map and 2D occupancy map are perfectly aligned

## 12. Save The 2D Occupancy Map

While `slam_mapping_from_dataset.launch.py` is still running and `/map` is
being published, save the current occupancy map with:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 save_map.launch.py \
  output_file_prefix:=/home/jiken/ros2_ws/maps/openbene_map
```

This writes:

- `/home/jiken/ros2_ws/maps/openbene_map.yaml`
- `/home/jiken/ros2_ws/maps/openbene_map.pgm`

Right after saving, inspect whether the map is actually good enough for
localization:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run openbene_ros2 map_doctor /home/jiken/ros2_ws/maps/openbene_map
```

You can pass any of these:

- the map prefix, for example `/home/jiken/ros2_ws/maps/openbene_map`
- the yaml path, for example `/home/jiken/ros2_ws/maps/openbene_map.yaml`
- the pgm path, for example `/home/jiken/ros2_ws/maps/openbene_map.pgm`

`map_doctor` reports:

- map extent in meters
- occupied / free / unknown ratios
- known-area bounding box size
- whether obstacle structure looks strong enough for the current 2D localization path

Use it as a quick gate before moving on to AMCL / saved-map localization.

Direct `nav2_map_server` command version:

```bash
ros2 run nav2_map_server map_saver_cli -t /map -f /home/jiken/ros2_ws/maps/openbene_map
```

## 13. Load A Saved Map Again

If you already saved:

- `/home/jiken/ros2_ws/maps/openbene_map.yaml`
- `/home/jiken/ros2_ws/maps/openbene_map.pgm`

you can bring that map back into ROS 2 with:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 saved_map_server.launch.py \
  map_yaml:=/home/jiken/ros2_ws/maps/openbene_map.yaml
```

This uses:

- `nav2_map_server/map_server`
- the local `openbene_ros2 lifecycle_bringup` helper

The result should be a live `/map` topic again, even without rerunning SLAM.

To inspect it visually:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 openbene_mapping_viewer.launch.py
```

Current limit:

- this machine already has `nav2_map_server`
- it does not yet have `nav2_amcl`, `nav2_planner`, or `nav2_controller`
- so saved-map loading is ready, but full Nav2 navigation is not yet installed on this machine

If `nav2_amcl` is installed, you can also run a minimal saved-map localization
stack from a recorded OpenBene dataset:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 saved_map_amcl_from_dataset.launch.py \
  map_yaml:=/home/jiken/ros2_ws/maps/openbene_map.yaml \
  dataset_dir:=/mnt/c/Users/jiken/Desktop/reciever/session_1775024454/session_1775024454
```

This starts:

- saved map server
- AMCL
- dataset scan replay
- odom TF projection

Then, in another terminal, seed AMCL from the precomputed relocalization result:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run openbene_ros2 dataset_relocalization --ros-args \
  -p report_path:=/mnt/c/Users/jiken/Desktop/reciever/session_1775024454/session_1775024454/relocalization_report.json
```

And in a third terminal:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 run openbene_ros2 relocalization_initialpose_bridge --ros-args -p target_frame:=map
```

That is the current shortest path from:

- saved OpenBene map
- saved OpenBene localization dataset

to:

- `/map`
- `/scan`
- `/initialpose`
- `nav2_amcl`

## 14. Parameters

Current parameters:

- `cmd_vel_topic`
- `ip`
- `port`
- `connect_on_startup`
- `dry_run`
- `log_commands`
- `linear_scale`
- `angular_scale`
- `command_timeout_sec`
- `report_path`
- `source_pose_topic`
- `initialpose_topic`

Example:

```bash
ros2 run openbene_ros2 cmd_vel_bridge --ros-args -p ip:=192.168.1.100 -p angular_scale:=0.5
```

## 15. Mapping next

The likely next ROS 2 mapping package is `slam_toolbox`.

This package now includes the first mapping-oriented bridge:

- `dataset_scan_replay` can publish `/scan` from a recorded OpenBene depth dataset
- `live_capture_scan_server` can prepare for live `/scan` once phone testing resumes
- `session_camera_replay` and `live_camera_bridge` expose the new RGB/depth/pose topic path from the upstream iOS transport upgrade

The remaining step later is:

- install `slam_toolbox`
- connect it to the replayed or live `/scan` topic

That dataset path is now wired through a single launch file:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 slam_mapping_from_dataset.launch.py \
  dataset_dir:=/path/to/session_xxx
```

This launch:

- replays `/scan`
- publishes `odom -> openbene_base` from the saved session poses
- publishes a static `openbene_base -> openbene_depth_frame`
- starts `slam_toolbox`

If `rviz2` shows a black window in WSL, use the packaged viewer launch, which
forces software rendering and loads a ready-made map/scan/TF layout:

```bash
source /opt/ros/humble/setup.bash
source ~/ros2_ws/install/setup.bash
ros2 launch openbene_ros2 openbene_mapping_viewer.launch.py
```
