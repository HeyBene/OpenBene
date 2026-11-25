#!/usr/bin/env bash
# End-to-end smoke test: zenohd + Swift SDK publisher + PC receiver/recorder.
#
#   ZENOHD=/path/to/zenohd scripts/e2e.sh
#
# Requires: zenohd 1.x and a Python environment with zenoh_ios/pc installed
# (set PYTHON to that interpreter; defaults to python3).
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="${PYTHON:-python3}"
ZENOHD="${ZENOHD:-zenohd}"
PORT="${PORT:-7461}"
FRAMES="${FRAMES:-20}"
OUT="${OUT:-$HERE/../runs/e2e-$(date +%Y%m%d-%H%M%S)}"

mkdir -p "$(dirname "$OUT")"
MCAP="$OUT.mcap"

echo "router: $ZENOHD on tcp/127.0.0.1:$PORT"
"$ZENOHD" --listen "tcp/127.0.0.1:$PORT" >"$OUT.zenohd.log" 2>&1 &
ROUTER=$!
cleanup() {
  kill "$ROUTER" 2>/dev/null || true
  wait "$ROUTER" 2>/dev/null || true
}
trap cleanup EXIT
sleep 2

echo "receiver: recording to $MCAP"
"$PYTHON" -m openbene_receiver.cli \
  --endpoint "tcp/127.0.0.1:$PORT" \
  --record "$MCAP" \
  --duration 18 >"$OUT.receiver.log" 2>&1 &
RECEIVER=$!
sleep 2

echo "publisher: $FRAMES frames"
(cd "$HERE" && swift run openbene-zenoh-demo publish \
  --endpoint "tcp/127.0.0.1:$PORT" \
  --frames "$FRAMES" --fps 10 --legacy-video)

wait "$RECEIVER"

"$PYTHON" - "$MCAP" "$FRAMES" <<'PY'
import json
import sys
from mcap.reader import make_reader

path, expected = sys.argv[1], int(sys.argv[2])
with open(path, "rb") as handle:
    messages = list(make_reader(handle).iter_messages())
frames = sum(1 for _, channel, _ in messages if channel.topic.endswith("/frame/meta"))
print(json.dumps({"mcap": path, "messages": len(messages), "frames": frames}))
if frames < expected:
    raise SystemExit(f"expected at least {expected} frames, recorded {frames}")
print("e2e ok")
PY
