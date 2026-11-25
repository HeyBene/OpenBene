#!/usr/bin/env bash
# Send a control command from the PC to the phone (downlink check).
#
#   bash zenoh_ios/scripts/send-cmd.sh stop
#   bash zenoh_ios/scripts/send-cmd.sh drive 0.4 0.4
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="${PYTHON:-$HERE/pc/.venv/bin/python}"
PORT="${PORT:-7447}"
ROBOT="${ROBOT:-rtr520}"
CMD="${1:-stop}"
LEFT="${2:-0.4}"
RIGHT="${3:-0.4}"

if ! (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
  echo "没有检测到 Zenoh 路由器：127.0.0.1:$PORT" >&2
  echo "请先在另一个终端保持运行：bash zenoh_ios/scripts/run-pc.sh" >&2
  echo "可以用 lsof -nP -iTCP:$PORT -sTCP:LISTEN 检查端口。" >&2
  exit 1
fi

"$PYTHON" - "$PORT" "$ROBOT" "$CMD" "$LEFT" "$RIGHT" <<'PY'
import json
import sys
import time

import zenoh

port, robot, command, left, right = sys.argv[1:6]
config = zenoh.Config()
config.insert_json5("mode", '"client"')
config.insert_json5("connect/endpoints", json.dumps([f"tcp/127.0.0.1:{port}"]))
session = zenoh.open(config)

if command == "drive":
    payload = {
        "version": 1,
        "cmd": "drive",
        "val": [float(left), float(right)],
        "seq": int(time.time() * 1000) % 100000,
        "sent_at": int(time.time() * 1000),
        "ttl_ms": 250,
    }
else:
    payload = {
        "version": 1,
        "cmd": "stop",
        "seq": int(time.time() * 1000) % 100000,
        "sent_at": int(time.time() * 1000),
    }

session.put(f"openbene/{robot}/cmd", json.dumps(payload))
print("sent", json.dumps(payload))
time.sleep(0.2)
session.close()
PY
