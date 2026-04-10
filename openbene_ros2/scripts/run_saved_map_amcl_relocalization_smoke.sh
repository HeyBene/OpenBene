#!/usr/bin/env bash
set -eo pipefail

if [ "$#" -lt 3 ] || [ "$#" -gt 6 ]; then
  echo "Usage: $0 <map_yaml> <dataset_dir> <report_path> [target_frame] [source_tail_frames] [replay_tail_frames]" >&2
  exit 2
fi

MAP_YAML="$1"
DATASET_DIR="$2"
REPORT_PATH="$3"
TARGET_FRAME="${4:-map}"

REPORT_SOURCE_TAIL_FRAMES="$(
  python3 - "${REPORT_PATH}" <<'PY'
import json
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
try:
    payload = json.loads(report_path.read_text(encoding="utf-8"))
except Exception:
    print(0)
else:
    print(int(payload.get("source_tail_frames", 0)))
PY
)"
SOURCE_TAIL_FRAMES="${5:-${REPORT_SOURCE_TAIL_FRAMES}}"
REPLAY_TAIL_FRAMES="${6:-${SOURCE_TAIL_FRAMES}}"

WORKSPACE_DIR="${HOME}/ros2_ws"
TMPDIR="$(mktemp -d /tmp/openbene_saved_map_amcl.XXXXXX)"
STACK_LOG="${TMPDIR}/stack.log"
BRIDGE_LOG="${TMPDIR}/bridge.log"
RELOCALIZATION_LOG="${TMPDIR}/relocalization.log"
STATUS_LOG="${TMPDIR}/status.log"
INITIALPOSE_LOG="${TMPDIR}/initialpose.log"
AMCL_POSE_LOG="${TMPDIR}/amcl_pose.log"
SCRIPT_STATUS=0

cleanup() {
  local exit_status=$?
  local status="${SCRIPT_STATUS}"
  if [ "${status}" -eq 0 ]; then
    status="${exit_status}"
  fi
  jobs -pr | xargs -r kill 2>/dev/null || true
  wait || true
  printf '\nSOURCE_TAIL_FRAMES=%s\n' "${SOURCE_TAIL_FRAMES}"
  printf 'REPLAY_TAIL_FRAMES=%s\n' "${REPLAY_TAIL_FRAMES}"
  printf '\nTMPDIR=%s\n' "${TMPDIR}"
  printf '\nSTACK_LOG\n'
  sed -n '1,220p' "${STACK_LOG}" 2>/dev/null || true
  printf '\nBRIDGE_LOG\n'
  sed -n '1,220p' "${BRIDGE_LOG}" 2>/dev/null || true
  printf '\nRELOCALIZATION_LOG\n'
  sed -n '1,220p' "${RELOCALIZATION_LOG}" 2>/dev/null || true
  printf '\nSTATUS_LOG\n'
  sed -n '1,120p' "${STATUS_LOG}" 2>/dev/null || true
  printf '\nINITIALPOSE_LOG\n'
  sed -n '1,120p' "${INITIALPOSE_LOG}" 2>/dev/null || true
  printf '\nAMCL_POSE_LOG\n'
  sed -n '1,120p' "${AMCL_POSE_LOG}" 2>/dev/null || true
  exit "${status}"
}
trap cleanup EXIT

cd "${WORKSPACE_DIR}"
set +u
source /opt/ros/humble/setup.bash
source "${WORKSPACE_DIR}/install/setup.bash"
set -u

timeout "${STACK_TIMEOUT_SEC:-35}" \
  ros2 launch openbene_ros2 saved_map_amcl_from_dataset.launch.py \
  map_yaml:="${MAP_YAML}" \
  dataset_dir:="${DATASET_DIR}" \
  tail_frames:="${REPLAY_TAIL_FRAMES}" \
  repeat:=true \
  >"${STACK_LOG}" 2>&1 &
STACK_PID=$!

for _ in $(seq 1 30); do
  if grep -q "Managed nodes are active" "${STACK_LOG}" 2>/dev/null; then
    break
  fi
  sleep 1
done

timeout "${BRIDGE_TIMEOUT_SEC:-20}" \
  ros2 run openbene_ros2 relocalization_initialpose_bridge --ros-args \
  -p target_frame:="${TARGET_FRAME}" \
  -p repeat_count:=20 \
  -p repeat_interval_sec:=0.5 \
  >"${BRIDGE_LOG}" 2>&1 &
BRIDGE_PID=$!

timeout 12s sh -c '
  until ros2 topic list -t 2>/dev/null | grep -q "/openbene/relocalization/status"; do
    sleep 0.2
  done
  ros2 topic echo --once /openbene/relocalization/status --field data --full-length
' >"${STATUS_LOG}" 2>&1 &
STATUS_PID=$!

timeout 12s ros2 topic echo --once /initialpose >"${INITIALPOSE_LOG}" 2>&1 &
INITIALPOSE_PID=$!
timeout 20s ros2 topic echo --once /amcl_pose >"${AMCL_POSE_LOG}" 2>&1 &
AMCL_POSE_PID=$!

sleep 0.5

timeout "${RELOCALIZATION_TIMEOUT_SEC:-20}" \
  ros2 run openbene_ros2 dataset_relocalization --ros-args \
  -p report_path:="${REPORT_PATH}" \
  -p source_tail_frames:="${SOURCE_TAIL_FRAMES}" \
  >"${RELOCALIZATION_LOG}" 2>&1

wait "${STATUS_PID}" || true
wait "${INITIALPOSE_PID}" || true
wait "${AMCL_POSE_PID}" || true

wait "${STACK_PID}" || true
wait "${BRIDGE_PID}" || true

if ! grep -q "state 'success'" "${RELOCALIZATION_LOG}" 2>/dev/null; then
  SCRIPT_STATUS=1
fi
if ! grep -q "position:" "${INITIALPOSE_LOG}" 2>/dev/null; then
  SCRIPT_STATUS=1
fi
if ! grep -q "position:" "${AMCL_POSE_LOG}" 2>/dev/null; then
  SCRIPT_STATUS=1
fi

exit "${SCRIPT_STATUS}"
