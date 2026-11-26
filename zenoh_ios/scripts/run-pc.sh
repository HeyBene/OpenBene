#!/usr/bin/env bash
# OpenBene Zenoh — one command for the whole PC side.
#
#   bash zenoh_ios/scripts/run-pc.sh
#
# Does everything in one go:
#   1. prepares the bundled zenohd router (downloads it on first run)
#   2. prepares the Python receiver environment (venv + deps on first run)
#   3. starts the router, the receiver and the live preview page
#   4. opens the preview in the browser and prints the address for the iPhone
#   5. on Ctrl+C stops everything and reports the recordings
#
# Optional environment variables:
#   PORT=7447          router port the phone connects to
#   VIEW_PORT=8080     preview page port
#   OPEN_BROWSER=0     do not open a browser window
#   DURATION=          stop automatically after N seconds
#   ZENOHD= PYTHON=    use your own binaries instead of the bundled ones
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$HERE/.tools"
ZENOHD="${ZENOHD:-$TOOLS/zenohd}"
PYTHON="${PYTHON:-$HERE/pc/.venv/bin/python}"
PORT="${PORT:-7447}"
VIEW_PORT="${VIEW_PORT:-8080}"
DURATION="${DURATION:-}"
OPEN_BROWSER="${OPEN_BROWSER:-1}"
OUT_DIR="$HERE/runs"
ZENOH_LOG="$OUT_DIR/zenohd.log"

mkdir -p "$OUT_DIR"
ROUTER=""
RECEIVER=""

say() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

port_open() {
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

detect_ip() {
  for iface in en0 en1 en2 en3 en4 en5 en6; do
    ip=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
    if [ -n "$ip" ]; then
      printf '%s\n' "$ip"
      return 0
    fi
  done
  return 1
}

cleanup() {
  if [ -n "$RECEIVER" ]; then
    kill "$RECEIVER" 2>/dev/null || true
    wait "$RECEIVER" 2>/dev/null || true
  fi
  if [ -n "$ROUTER" ]; then
    kill "$ROUTER" 2>/dev/null || true
    wait "$ROUTER" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------- zenohd ----
if [ ! -x "$ZENOHD" ]; then
  case "$(uname -m)" in
    arm64) ZTARGET="aarch64-apple-darwin" ;;
    x86_64) ZTARGET="x86_64-apple-darwin" ;;
    *) fail "unsupported architecture $(uname -m); set ZENOHD=/path/to/zenohd" ;;
  esac
  ZVER="1.1.0"
  say "准备 zenohd $ZVER（首次运行需要联网下载）..."
  mkdir -p "$TOOLS"
  TMPZIP="$(mktemp -t zenohd).zip"
  curl -fsSL --retry 2 -m 300 \
    -o "$TMPZIP" \
    "https://github.com/eclipse-zenoh/zenoh/releases/download/$ZVER/zenoh-$ZVER-$ZTARGET-standalone.zip" \
    || fail "下载 zenohd 失败；请手动安装后设置 ZENOHD=/path/to/zenohd"
  unzip -oq "$TMPZIP" -d "$TOOLS"
  rm -f "$TMPZIP"
  chmod +x "$TOOLS/zenohd"
  say "zenohd 已就绪：$TOOLS/zenohd"
fi

# ----------------------------------------------------------------- python ---
need_venv=0
if [ ! -x "$PYTHON" ]; then
  need_venv=1
elif ! "$PYTHON" -c 'import zenoh, mcap, openbene_receiver' >/dev/null 2>&1; then
  need_venv=1
fi
if [ "$need_venv" = 1 ]; then
  say "准备 Python 接收端环境（首次运行需要联网安装 eclipse-zenoh / mcap）..."
  [ -x "$PYTHON" ] || python3 -m venv "$HERE/pc/.venv"
  "$HERE/pc/.venv/bin/pip" install -q --upgrade pip >/dev/null 2>&1 || true
  "$HERE/pc/.venv/bin/pip" install -q -e "$HERE/pc" \
    || fail "安装 Python 依赖失败；请检查网络后重试"
  PYTHON="$HERE/pc/.venv/bin/python"
fi

# ------------------------------------------------------------------ ports ---
while port_open "$VIEW_PORT"; do
  VIEW_PORT=$((VIEW_PORT + 1))
done

if port_open "$PORT"; then
  say "端口 $PORT 已有监听，直接复用（若它不是 zenohd，请换 PORT=...）"
else
  "$ZENOHD" --listen "tcp/0.0.0.0:$PORT" >"$ZENOH_LOG" 2>&1 &
  ROUTER=$!
  ready=0
  for _ in $(seq 1 40); do
    if port_open "$PORT"; then ready=1; break; fi
    if ! kill -0 "$ROUTER" 2>/dev/null; then
      tail -20 "$ZENOH_LOG" >&2 || true
      fail "zenohd 启动失败（日志：$ZENOH_LOG）"
    fi
    sleep 0.25
  done
  [ "$ready" = 1 ] || fail "zenohd 在端口 $PORT 上没有就绪（日志：$ZENOH_LOG）"
fi

# --------------------------------------------------------------- receiver ---
ARGS=(--endpoint "tcp/127.0.0.1:$PORT" --record-dir "$OUT_DIR"
      --view --view-port "$VIEW_PORT" --stats)
if [ -n "$DURATION" ]; then ARGS+=(--duration "$DURATION"); fi

"$PYTHON" -m openbene_receiver.cli "${ARGS[@]}" >"$OUT_DIR/receiver.log" 2>&1 &
RECEIVER=$!

VIEW_URL="http://127.0.0.1:$VIEW_PORT/"
ready=0
for _ in $(seq 1 40); do
  if curl -fsS --max-time 1 "${VIEW_URL}state.json" >/dev/null 2>&1; then ready=1; break; fi
  if ! kill -0 "$RECEIVER" 2>/dev/null; then
    tail -20 "$OUT_DIR/receiver.log" >&2 || true
    fail "接收端启动失败（日志：$OUT_DIR/receiver.log）"
  fi
  sleep 0.25
done
[ "$ready" = 1 ] || fail "预览页没有就绪（日志：$OUT_DIR/receiver.log）"

LAN_IP="$(detect_ip || true)"

say ""
say "=============================================================="
say " OpenBene Zenoh 已在运行"
say "=============================================================="
say " 电脑端预览   : $VIEW_URL"
say " 手机填写地址 : ${LAN_IP:-<电脑IP>}:$PORT"
say " 录制         : 默认关闭，在网页上点「开始录制」"
say " 录制目录     : $OUT_DIR"
say " 结束全部     : 在本终端按 Ctrl+C"
say "=============================================================="
say ""

if [ "$OPEN_BROWSER" = 1 ] && command -v open >/dev/null 2>&1; then
  open "$VIEW_URL" 2>/dev/null || true
fi

# Ctrl+C lands here; wait keeps the shell responsive to signals.
wait "$RECEIVER" || true
RECEIVER=""

say ""
say "已停止。录制文件（若有）在 ${OUT_DIR}："
ls -1t "$OUT_DIR"/*.mcap 2>/dev/null | head -5 || say "  （本次没有开始录制）"
