#!/usr/bin/env bash
# One-command PC side for the OpenBene Zenoh link test.
#
#   bash zenoh_ios/scripts/run-pc.sh
#
# Starts zenohd (bundled at zenoh_ios/.tools/zenohd), records every
# openbene/{robot}/* stream into runs/zenoh-<timestamp>.mcap and prints the
# address to type into the iPhone app. Ctrl+C stops the recording.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
ZENOHD="${ZENOHD:-$HERE/.tools/zenohd}"
PYTHON="${PYTHON:-$HERE/pc/.venv/bin/python}"
PORT="${PORT:-7447}"
DURATION="${DURATION:-}"

detect_ip() {
  for iface in en0 en1 en2 en3 en4 en5 en6; do
    ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
    if [ -n "$ip" ]; then
      echo "$ip"
      return 0
    fi
  done
  return 1
}

LAN_IP="$(detect_ip || true)"
OUT_DIR="$HERE/runs"
mkdir -p "$OUT_DIR"
MCAP="$OUT_DIR/zenoh-$(date +%Y%m%d-%H%M%S).mcap"

if [ ! -x "$ZENOHD" ]; then
  echo "zenohd not found at $ZENOHD" >&2
  echo "Download zenoh 1.1.0 or set ZENOHD=/path/to/zenohd" >&2
  exit 1
fi
if [ ! -x "$PYTHON" ]; then
  echo "Python env missing; run: cd zenoh_ios/pc && python3 -m venv .venv && .venv/bin/pip install -e ." >&2
  exit 1
fi

cleanup() {
  kill "$ROUTER" 2>/dev/null || true
  wait "$ROUTER" 2>/dev/null || true
}
trap cleanup EXIT

"$ZENOHD" --listen "tcp/0.0.0.0:$PORT" >"$OUT_DIR/zenohd.log" 2>&1 &
ROUTER=$!
sleep 1.5

echo "Mac IP : ${LAN_IP:-unknown}"
echo "Phone  : 在 App 的「电脑地址」填 ${LAN_IP:-<电脑IP>}:$PORT"
echo "Record : $MCAP"
echo "Ctrl+C : 结束录制"
echo

ARGS=(--endpoint "tcp/127.0.0.1:$PORT" --record "$MCAP" --json)
if [ -n "$DURATION" ]; then
  ARGS+=(--duration "$DURATION")
fi
"$PYTHON" -m openbene_receiver.cli "${ARGS[@]}"

echo
echo "saved: $MCAP"
