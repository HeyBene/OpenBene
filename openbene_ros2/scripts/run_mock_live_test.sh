#!/usr/bin/env bash
set -eo pipefail

cd "${HOME}/ros2_ws"
source /opt/ros/humble/setup.bash
source install/setup.bash

tmpdir="$(mktemp -d /tmp/openbene_live_test.XXXXXX)"
server_log="${tmpdir}/server.log"
client_log="${tmpdir}/client.log"

(
  timeout 8s ros2 run openbene_ros2 live_capture_scan_server --ros-args -p output_root_dir:="${tmpdir}" \
    >"${server_log}" 2>&1 || true
) &

sleep 2
ros2 run openbene_ros2 mock_capture_client >"${client_log}" 2>&1
sleep 2

echo "TMPDIR=${tmpdir}"
find "${tmpdir}" -maxdepth 3 -type f | sort
printf '\nSERVER_LOG\n'
sed -n '1,120p' "${server_log}"
printf '\nCLIENT_LOG\n'
sed -n '1,120p' "${client_log}"
