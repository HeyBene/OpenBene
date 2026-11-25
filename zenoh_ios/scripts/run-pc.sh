#!/usr/bin/env bash
# One-command PC side for the OpenBene Zenoh link test.
#
#   bash zenoh_ios/scripts/run-pc.sh
#
# Starts zenohd (bundled at zenoh_ios/.tools/zenohd), serves a live preview at
# http://127.0.0.1:8080 and prints the address to type into the iPhone app.
# Recording is off until you press 开始录制 in the preview page.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
ZENOHD="${ZENOHD:-$HERE/.tools/zenohd}"
PYTHON="${PYTHON:-$HERE/pc/.venv/bin/python}"
PORT="${PORT:-7447}"
DURATION="${DURATION:-}"
VIEW_PORT="${VIEW_PORT:-8080}"

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
  if [ -n "$ROUTER" ]; then
    kill "$ROUTER" 2>/dev/null || true
    wait "$ROUTER" 2>/dev/null || true
  fi
}
trap cleanup EXIT

ROUTER=""
if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
  echo "port $PORT already has a listener; reusing it"
else
  "$ZENOHD" --listen "tcp/0.0.0.0:$PORT" >"$OUT_DIR/zenohd.log" 2>&1 &
  ROUTER=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
      break
    fi
    if ! kill -0 "$ROUTER" 2>/dev/null; then
      echo "zenohd exited before listening on port $PORT:" >&2
      tail -20 "$OUT_DIR/zenohd.log" >&2 || true
      exit 1
    fi
    sleep 0.25
  done
fi

echo "Mac IP : ${LAN_IP:-unknown}"
echo "Phone  : 在 App 的「电脑地址」填 ${LAN_IP:-<电脑IP>}:$PORT"
echo "View   : http://127.0.0.1:$VIEW_PORT/  (录制默认关闭，在网页里点「开始录制」)"
echo "Record : 网页控制，文件写到 $OUT_DIR"
echo "Ctrl+C : 结束"
echo

ARGS=(--endpoint "tcp/127.0.0.1:$PORT" --record-dir "$OUT_DIR" --view --view-port "$VIEW_PORT" --json)
if [ -n "$DURATION" ]; then
  ARGS+=(--duration "$DURATION")
fi
"$PYTHON" -m openbene_receiver.cli "${ARGS[@]}"

echo
echo "saved: $MCAP"
