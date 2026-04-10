#!/usr/bin/env bash
set -eo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  echo "Usage: $0 <dataset_dir> <output_file_prefix> [wait_sec]" >&2
  exit 2
fi

DATASET_DIR="$1"
OUTPUT_FILE_PREFIX="$2"
WAIT_SEC="${3:-55}"

WORKSPACE_DIR="${HOME}/ros2_ws"
TMPDIR="$(mktemp -d /tmp/openbene_mapping_save.XXXXXX)"
STACK_LOG="${TMPDIR}/mapping_stack.log"
MAP_METADATA_LOG="${TMPDIR}/map_metadata.log"
SAVE_MAP_LOG="${TMPDIR}/save_map.log"

cleanup() {
  local status=$?
  jobs -pr | xargs -r kill 2>/dev/null || true
  wait || true
  printf '\nTMPDIR=%s\n' "${TMPDIR}"
  printf '\nSTACK_LOG\n'
  sed -n '1,260p' "${STACK_LOG}" 2>/dev/null || true
  printf '\nMAP_METADATA_LOG\n'
  sed -n '1,120p' "${MAP_METADATA_LOG}" 2>/dev/null || true
  printf '\nSAVE_MAP_LOG\n'
  sed -n '1,160p' "${SAVE_MAP_LOG}" 2>/dev/null || true
  exit "${status}"
}
trap cleanup EXIT

cd "${WORKSPACE_DIR}"
set +u
source /opt/ros/humble/setup.bash
source "${WORKSPACE_DIR}/install/setup.bash"
set -u

timeout "${STACK_TIMEOUT_SEC:-90}" \
  ros2 launch openbene_ros2 slam_mapping_from_dataset.launch.py \
  dataset_dir:="${DATASET_DIR}" \
  >"${STACK_LOG}" 2>&1 &
STACK_PID=$!

sleep "${WAIT_SEC}"

timeout 10s ros2 topic echo --once /map_metadata >"${MAP_METADATA_LOG}" 2>&1 || true

ros2 launch openbene_ros2 save_map.launch.py \
  output_file_prefix:="${OUTPUT_FILE_PREFIX}" \
  >"${SAVE_MAP_LOG}" 2>&1

wait "${STACK_PID}" || true
