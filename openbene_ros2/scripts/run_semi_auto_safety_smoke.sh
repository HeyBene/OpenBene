#!/usr/bin/env bash
set -eo pipefail

cd "${HOME}/ros2_ws"
source /opt/ros/humble/setup.bash
colcon build --packages-select openbene_ros2 >/tmp/openbene_semi_auto_build.log 2>&1
source install/setup.bash

tmpdir="$(mktemp -d /tmp/openbene_semi_auto_test.XXXXXX)"
launch_log="${tmpdir}/launch.log"

sample_status() {
  ros2 topic echo --once /openbene/safety/status_test --field data --full-length
}

run_case() {
  local label="$1"
  local scan_payload="$2"

  echo "=== ${label} ==="
  ros2 topic pub --once /scan_test sensor_msgs/msg/LaserScan "${scan_payload}" >/dev/null 2>&1
  (
    timeout 2s ros2 topic pub -r 5 /cmd_vel_user_test geometry_msgs/msg/Twist \
      "{linear: {x: 0.12}, angular: {z: 0.0}}" >/dev/null 2>&1 || true
  ) &
  local pub_pid=$!
  sleep 0.4
  sample_status
  wait "${pub_pid}" || true
}

(
  timeout 18s ros2 launch openbene_ros2 semi_auto_cmd_vel.launch.py \
    input_cmd_vel_topic:=/cmd_vel_user_test \
    output_cmd_vel_topic:=/cmd_vel_safe_test \
    scan_topic:=/scan_test \
    status_topic:=/openbene/safety/status_test \
    dry_run:=true >"${launch_log}" 2>&1 || true
) &

launch_pid=$!
sleep 6

run_case "PASS" \
  "{angle_min: -0.5, angle_max: 0.5, angle_increment: 0.5, range_min: 0.1, range_max: 5.0, ranges: [2.0, 2.0, 2.0]}"

run_case "SLOWDOWN" \
  "{angle_min: -0.5, angle_max: 0.5, angle_increment: 0.5, range_min: 0.1, range_max: 5.0, ranges: [2.0, 0.27, 2.0]}"

run_case "OBSTACLE_STOP" \
  "{angle_min: -0.5, angle_max: 0.5, angle_increment: 0.5, range_min: 0.1, range_max: 5.0, ranges: [2.0, 0.18, 2.0]}"

sleep 0.7
echo "=== TIMEOUT_STOP ==="
sample_status

wait "${launch_pid}" || true

echo "TMPDIR=${tmpdir}"
echo "=== LAUNCH LOG ==="
sed -n '1,200p' "${launch_log}"
