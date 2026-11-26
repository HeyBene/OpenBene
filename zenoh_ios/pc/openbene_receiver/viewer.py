"""Local live preview + control page for OpenBene Zenoh sessions."""

from __future__ import annotations

import json
import socketserver
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable

from .pngviz import colorize_confidence, colorize_depth


class LiveViewer:
    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 8080,
        recording: Any | None = None,
        command_publisher: Callable[[float, float], None] | None = None,
    ) -> None:
        self.host = host
        self.port = port
        self.recording = recording
        self.command_publisher = command_publisher
        self._lock = threading.Lock()
        self._rgb = b""
        self._depth = b""
        self._confidence = b""
        self._meta: dict[str, Any] = {}
        self._stats: dict[str, Any] = {}
        self._last_command: Any = None
        self._last_sent: dict[str, Any] | None = None
        self._frames = 0
        self._frame_times: deque[float] = deque(maxlen=60)
        self._started_at = time.time()
        self._server: _FastHTTPServer | None = None
        self._thread: threading.Thread | None = None

    # -- ingestion --------------------------------------------------------

    def update_frame(
        self,
        meta: dict[str, Any],
        rgb: bytes | None,
        depth: bytes | None,
        confidence: bytes | None,
    ) -> None:
        now = time.time()
        with self._lock:
            self._frames += 1
            self._frame_times.append(now)
            self._meta = meta
            if rgb:
                self._rgb = rgb
            if depth:
                self._depth = depth
            if confidence:
                self._confidence = confidence

    def update_stats(self, stats: dict[str, Any]) -> None:
        with self._lock:
            self._stats = stats

    def update_command(self, document: Any) -> None:
        with self._lock:
            self._last_command = document

    def send_drive(self, left: float, right: float) -> dict[str, Any]:
        if self.command_publisher is None:
            raise RuntimeError("command publishing is not available")
        left = max(-1.0, min(1.0, float(left)))
        right = max(-1.0, min(1.0, float(right)))
        if left == 0 and right == 0:
            self.command_publisher(0.0, 0.0)
        else:
            self.command_publisher(left, right)
        with self._lock:
            self._last_sent = {"left": round(left, 3), "right": round(right, 3)}
            return dict(self._last_sent)

    def send_stop(self) -> dict[str, Any]:
        return self.send_drive(0.0, 0.0)

    # -- snapshot ---------------------------------------------------------

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            times = list(self._frame_times)
            frames = self._frames
            meta = dict(self._meta)
            stats = dict(self._stats)
            command = self._last_command
            sent = dict(self._last_sent) if self._last_sent else None
            sizes = {
                "rgb": len(self._rgb),
                "depth": len(self._depth),
                "confidence": len(self._confidence),
            }

        fps = 0.0
        if len(times) > 1:
            span = max(1e-3, times[-1] - times[0])
            fps = (len(times) - 1) / span
        mbps = (sizes["rgb"] + sizes["depth"] + sizes["confidence"]) * fps / 1_000_000
        recording_state = (
            self.recording.status()
            if self.recording is not None
            else {"active": False, "path": None}
        )

        return {
            "live": bool(times and time.time() - times[-1] < 3),
            "uptime_s": round(time.time() - self._started_at, 1),
            "frames": frames,
            "fps": round(fps, 1),
            "mbps": round(mbps, 2),
            "meta": meta,
            "sizes": sizes,
            "planes": {
                "enabled": meta.get("metadata", {}).get("enabledPlanes"),
                "rgb": sizes["rgb"] > 0,
                "depth": sizes["depth"] > 0,
                "confidence": sizes["confidence"] > 0,
            },
            "stats": stats,
            "last_command": command,
            "last_sent": sent,
            "recording": recording_state,
            "command_enabled": self.command_publisher is not None,
        }

    def image(self, kind: str) -> tuple[bytes, str]:
        with self._lock:
            if kind == "depth":
                return colorize_depth(self._depth), "image/png"
            if kind == "confidence":
                return colorize_confidence(self._confidence), "image/png"
            return self._rgb, "image/jpeg"

    # -- http -------------------------------------------------------------

    def start(self) -> str:
        handler = self._make_handler()
        server = _FastHTTPServer((self.host, self.port), handler)
        self._server = server
        self.port = server.server_address[1]
        self._thread = threading.Thread(target=server.serve_forever, daemon=True)
        self._thread.start()
        return self.url

    @property
    def url(self) -> str:
        host = "127.0.0.1" if self.host in ("0.0.0.0", "::") else self.host
        return f"http://{host}:{self.port}/"

    def stop(self) -> None:
        if self._server is not None:
            self._server.shutdown()
            self._server.server_close()
            self._server = None
        if self._thread is not None:
            self._thread.join(timeout=2)
            self._thread = None

    def _make_handler(self) -> type[BaseHTTPRequestHandler]:
        viewer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args: Any) -> None:
                return

            def do_GET(self) -> None:  # noqa: N802
                path = self.path.split("?", 1)[0]
                if path in ("/", "/index.html"):
                    self._send(200, "text/html; charset=utf-8", PAGE.encode("utf-8"))
                    return
                if path == "/state.json":
                    body = json.dumps(viewer.snapshot(), sort_keys=True).encode("utf-8")
                    self._send(200, "application/json", body)
                    return
                if path in ("/frame.jpg", "/depth.png", "/confidence.png"):
                    kind = {
                        "/frame.jpg": "rgb",
                        "/depth.png": "depth",
                        "/confidence.png": "confidence",
                    }[path]
                    data, content_type = viewer.image(kind)
                    if not data:
                        self._send(204, content_type, b"")
                    else:
                        self._send(200, content_type, data)
                    return
                self._send(404, "text/plain", b"not found")

            def do_POST(self) -> None:  # noqa: N802
                path = self.path.split("?", 1)[0]
                try:
                    if path == "/cmd/drive":
                        payload = self._read_json()
                        result = viewer.send_drive(
                            float(payload.get("left", 0)), float(payload.get("right", 0))
                        )
                        self._send(200, "application/json", json.dumps(result).encode())
                        return
                    if path == "/cmd/stop":
                        result = viewer.send_stop()
                        self._send(200, "application/json", json.dumps(result).encode())
                        return
                    controller = viewer.recording
                    if controller is None:
                        self._send(503, "application/json", b'{"error":"recording disabled"}')
                        return
                    if path == "/record/start":
                        controller.start()
                    elif path == "/record/stop":
                        controller.stop()
                    else:
                        self._send(404, "text/plain", b"not found")
                        return
                    body = json.dumps(controller.status(), sort_keys=True).encode("utf-8")
                    self._send(200, "application/json", body)
                except Exception as error:  # keep the page alive on bad input
                    self._send(500, "application/json", json.dumps({"error": str(error)}).encode())

            def _read_json(self) -> dict[str, Any]:
                length = int(self.headers.get("Content-Length") or 0)
                if length <= 0:
                    return {}
                raw = self.rfile.read(length)
                try:
                    value = json.loads(raw.decode("utf-8") or "{}")
                except json.JSONDecodeError:
                    return {}
                return value if isinstance(value, dict) else {}

            def _send(self, status: int, content_type: str, body: bytes) -> None:
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                if body:
                    self.wfile.write(body)

        return Handler


class _FastHTTPServer(ThreadingHTTPServer):
    """HTTPServer without the reverse-DNS lookup in server_bind()."""

    daemon_threads = True

    def server_bind(self) -> None:
        socketserver.TCPServer.server_bind(self)
        self.server_name = "openbene"
        self.server_port = self.server_address[1]

PAGE = """<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>OpenBene 实时控制台</title>
<style>
  :root {
    color-scheme: light;
    --bg: #f5f6f8;
    --card: #ffffff;
    --border: #e5e7eb;
    --text: #1f2937;
    --muted: #6b7280;
    --accent: #2563eb;
    --accent-soft: #eff4ff;
    --teal: #0f766e;
    --teal-soft: #ecfdf5;
    --danger: #dc2626;
    --danger-soft: #fef2f2;
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--text);
         font: 14px/1.5 -apple-system, BlinkMacSystemFont, "PingFang SC", system-ui, sans-serif; }
  header { display: flex; align-items: center; gap: 12px; padding: 16px 24px;
           background: rgba(255,255,255,.86); border-bottom: 1px solid var(--border);
           position: sticky; top: 0; z-index: 5; backdrop-filter: blur(8px); }
  h1 { font-size: 17px; margin: 0; letter-spacing: .01em; }
  .pill { font-size: 11px; font-weight: 600; padding: 3px 9px; border-radius: 999px;
          border: 1px solid var(--border); color: var(--muted); background: #fff; }
  .pill.live { color: var(--teal); background: var(--teal-soft); border-color: #a7f3d0; }
  .pill.rec { color: var(--danger); background: var(--danger-soft); border-color: #fecaca; }
  .muted { color: var(--muted); font-size: 12px; }
  main { display: grid; grid-template-columns: minmax(0, 1.7fr) minmax(350px, 1fr);
         gap: 16px; padding: 18px 24px 28px; max-width: 1500px; margin: 0 auto; }
  .card { background: var(--card); border: 1px solid var(--border); border-radius: 16px;
          box-shadow: 0 1px 2px rgba(16,24,40,.04), 0 8px 24px rgba(16,24,40,.04);
          overflow: hidden; }
  .card h2 { display: flex; align-items: center; gap: 8px; font-size: 13px; font-weight: 600;
             margin: 0; padding: 13px 16px; border-bottom: 1px solid var(--border); }
  .card h2 .dot { width: 6px; height: 6px; border-radius: 50%; background: var(--accent); }
  .stage { background: #f8fafc; display: grid; place-items: center; min-height: 330px; }
  .stage img { width: 100%; height: auto; display: block; }
  .stage .empty { color: var(--muted); font-size: 12px; text-align: center; padding: 16px; }
  .stack { position: relative; }
  .stack .empty { position: absolute; inset: 0; display: none; place-items: center;
                  background: #f8fafc; }
  .stack.off .empty { display: grid; }
  .stack.off img { visibility: hidden; }
  .planes { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-top: 16px; }
  .planes .stage { min-height: 150px; }
  .col { display: flex; flex-direction: column; gap: 16px; }
  .metrics { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px; padding: 14px 16px; }
  .metric { background: var(--bg); border-radius: 11px; padding: 9px 12px; }
  .metric span { display: block; font-size: 11px; color: var(--muted); }
  .metric strong { font-size: 18px; font-weight: 650; font-variant-numeric: tabular-nums; }
  .metric em { font-style: normal; font-size: 11px; color: var(--muted); margin-left: 2px; }
  dl { margin: 0; padding: 12px 16px 15px; display: grid; grid-template-columns: auto 1fr;
       gap: 5px 16px; font-size: 12px; }
  dt { color: var(--muted); }
  dd { margin: 0; text-align: right; font-variant-numeric: tabular-nums; word-break: break-all; }
  .pad { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; padding: 0 16px 14px; }
  .key { height: 50px; border-radius: 12px; border: 1px solid var(--border); background: #fff;
         color: var(--text); font: inherit; font-weight: 600; cursor: pointer;
         display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 1px;
         transition: background .08s ease, color .08s ease, border-color .08s ease; }
  .key small { font-size: 9px; color: var(--muted); font-weight: 600; letter-spacing: .06em; }
  .key:hover { border-color: #c7d2fe; background: #fafbff; }
  .key.on { background: var(--accent); border-color: var(--accent); color: #fff; }
  .key.on small { color: rgba(255,255,255,.8); }
  .key.stop { color: var(--danger); border-color: #fecaca; background: var(--danger-soft); }
  .sliders { padding: 4px 16px 14px; display: grid; gap: 10px; }
  .slider-row label { display: flex; justify-content: space-between; font-size: 12px; color: var(--muted); }
  .slider-row b { color: var(--text); font-weight: 600; font-variant-numeric: tabular-nums; }
  input[type=range] { width: 100%; accent-color: var(--accent); margin-top: 4px; }
  .hint { padding: 0 16px 16px; font-size: 11px; color: var(--muted); }
  .hint kbd { display: inline-block; padding: 1px 5px; border-radius: 5px; border: 1px solid var(--border);
              background: var(--bg); font-size: 10px; font-weight: 600; color: var(--text); }
  .buttons { display: flex; gap: 10px; padding: 0 16px 16px; }
  button.act { flex: 1; padding: 10px 12px; border-radius: 11px; border: 1px solid var(--border);
               font: inherit; font-size: 13px; font-weight: 600; cursor: pointer; background: #fff; }
  button.act.primary { background: var(--accent); border-color: var(--accent); color: #fff; }
  button.act.primary:hover { background: #1d4ed8; }
  button.act.danger { background: var(--danger-soft); border-color: #fecaca; color: var(--danger); }
  button.act:disabled { opacity: .45; cursor: default; }
  code { font-size: 11px; color: var(--muted); }
</style>
</head>
<body>
<header>
  <h1>OpenBene 实时控制台</h1>
  <span id="pill" class="pill">等待数据</span>
  <span id="recpill" class="pill">未录制</span>
  <span class="spacer" style="flex:1"></span>
  <span id="robot" class="muted">robot —</span>
</header>
<main>
  <section>
    <div class="card">
      <h2><span class="dot"></span>RGB 实时画面</h2>
        <div class="stage stack" id="rgbWrap">
          <img id="rgb" alt="RGB">
          <div class="empty" id="rgbEmpty">等待手机画面</div>
        </div>
    </div>
    <div class="planes">
      <div class="card">
        <h2><span class="dot" style="background:#0f766e"></span>深度</h2>
        <div class="stage stack" id="depthWrap">
          <img id="depth" alt="深度">
          <div class="empty" id="depthEmpty">等待深度数据</div>
        </div>
      </div>
      <div class="card">
        <h2><span class="dot" style="background:#7c3aed"></span>置信度</h2>
        <div class="stage stack" id="confWrap">
          <img id="confidence" alt="置信度">
          <div class="empty" id="confEmpty">等待置信度数据</div>
        </div>
      </div>
    </div>
  </section>

  <aside class="col">
    <div class="card">
      <h2><span class="dot"></span>传输状态</h2>
      <div class="metrics">
        <div class="metric"><span>帧率</span><strong id="fps">0.0</strong><em>fps</em></div>
        <div class="metric"><span>已收帧</span><strong id="frames">0</strong></div>
        <div class="metric"><span>带宽</span><strong id="mbps">0.0</strong><em>MB/s</em></div>
        <div class="metric"><span>跳号</span><strong id="gaps">0</strong></div>
      </div>
      <dl>
        <dt>帧号</dt><dd id="frame_id">—</dd>
        <dt>分辨率</dt><dd id="resolution">—</dd>
        <dt>跟踪状态</dt><dd id="tracking">—</dd>
        <dt>深度来源</dt><dd id="depth_source">—</dd>
        <dt>坏包</dt><dd id="errors">0</dd>
        <dt>手机收到</dt><dd id="command">—</dd>
      </dl>
    </div>

    <div class="card">
      <h2><span class="dot" style="background:#0f766e"></span>控制小车</h2>
      <div class="sliders">
        <div class="slider-row">
          <label>速度<b id="speedLabel">47%</b></label>
          <input id="speed" type="range" min="10" max="100" value="47">
        </div>
        <div class="slider-row">
          <label>转向<b id="turnLabel">35%</b></label>
          <input id="turn" type="range" min="10" max="100" value="35">
        </div>
      </div>
      <div class="pad">
        <button class="key" data-key="q">↖<small>Q</small></button>
        <button class="key" data-key="w">↑<small>W</small></button>
        <button class="key" data-key="e">↗<small>E</small></button>
        <button class="key" data-key="a">←<small>A</small></button>
        <button class="key" data-key="s">↓<small>S</small></button>
        <button class="key" data-key="d">→<small>D</small></button>
      </div>
      <div class="buttons">
        <button id="stop" class="act danger">停车</button>
      </div>
      <p class="hint">键盘 <kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> 移动，<kbd>Q</kbd><kbd>E</kbd> 弧线，<kbd>空格</kbd> 停车。
      指令经 Zenoh 发到手机，手机再通过 BLE 驱动小车。</p>
    </div>

    <div class="card">
      <h2><span class="dot" style="background:#dc2626"></span>录制</h2>
      <dl style="padding-bottom:6px">
        <dt>状态</dt><dd id="recstate">未录制</dd>
        <dt>文件</dt><dd><code id="recpath">—</code></dd>
      </dl>
      <div class="buttons">
        <button id="recstart" class="act primary">开始录制</button>
        <button id="recstop" class="act danger" disabled>停止录制</button>
      </div>
    </div>
  </aside>
</main>
<script>
const $ = (id) => document.getElementById(id);
let heldKey = null;
let repeatTimer = null;
let lastState = null;

function pwm(percent) { return Math.round(percent / 100 * 255); }

function mapping(key) {
  const drive = pwm(Number($('speed').value));
  const turn = pwm(Number($('turn').value));
  const arc = Math.round(drive * 0.55);
  switch (key) {
    case 'w': return [drive, drive];
    case 's': return [-drive, -drive];
    case 'a': return [-turn, turn];
    case 'd': return [turn, -turn];
    case 'q': return [arc, drive];
    case 'e': return [drive, arc];
    default: return [0, 0];
  }
}

async function sendDrive(key) {
  const [left, right] = mapping(key);
  const scale = (v) => Math.max(-1, Math.min(1, v / 255));
  await post('/cmd/drive', {left: scale(left), right: scale(right)});
}

async function post(path, body) {
  try {
    return await (await fetch(path, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: body ? JSON.stringify(body) : undefined
    })).json();
  } catch (err) {
    return null;
  }
}

function highlight(key, on) {
  const button = document.querySelector('.key[data-key="' + key + '"]');
  if (button) button.classList.toggle('on', on);
}

function startHold(key) {
  if (heldKey === key) return;
  stopHold();
  if (!lastState || !lastState.command_enabled) return;
  heldKey = key;
  highlight(key, true);
  sendDrive(key);
  repeatTimer = setInterval(() => sendDrive(key), 100);
}

function stopHold() {
  if (repeatTimer) { clearInterval(repeatTimer); repeatTimer = null; }
  if (heldKey) highlight(heldKey, false);
  heldKey = null;
  post('/cmd/stop');
}

document.addEventListener('keydown', (event) => {
  const tag = (event.target.tagName || '').toLowerCase();
  if (tag === 'input' || tag === 'textarea') return;
  const key = event.key.toLowerCase();
  if (['w','a','s','d','q','e'].includes(key)) {
    event.preventDefault();
    startHold(key);
  } else if (key === ' ' || key === 'x') {
    event.preventDefault();
    stopHold();
  }
});

document.addEventListener('keyup', (event) => {
  const key = event.key.toLowerCase();
  if (heldKey === key) stopHold();
});

window.addEventListener('blur', stopHold);
document.addEventListener('visibilitychange', () => { if (document.hidden) stopHold(); });

document.querySelectorAll('.key').forEach((button) => {
  const key = button.dataset.key;
  button.addEventListener('pointerdown', (event) => { event.preventDefault(); startHold(key); });
  button.addEventListener('pointerup', stopHold);
  button.addEventListener('pointerleave', () => { if (heldKey === key) stopHold(); });
});

$('stop').addEventListener('click', stopHold);
$('speed').addEventListener('input', () => {
  $('speedLabel').textContent = $('speed').value + '%';
  if (heldKey) sendDrive(heldKey);
});
$('turn').addEventListener('input', () => {
  $('turnLabel').textContent = $('turn').value + '%';
  if (heldKey) sendDrive(heldKey);
});

$('recstart').onclick = async () => { await post('/record/start'); await tick(); };
$('recstop').onclick = async () => { await post('/record/stop'); await tick(); };

async function tick() {
  try {
    const state = await (await fetch('/state.json', {cache: 'no-store'})).json();
    lastState = state;
    $('pill').textContent = state.live ? 'LIVE' : '等待数据';
    $('pill').className = 'pill' + (state.live ? ' live' : '');
    const rec = state.recording || {};
    $('recpill').textContent = rec.active ? '录制中' : '未录制';
    $('recpill').className = 'pill' + (rec.active ? ' rec' : '');
    $('recstart').disabled = rec.active;
    $('recstop').disabled = !rec.active;
    $('recstate').textContent = rec.active ? '录制中' : '未录制';
    $('recpath').textContent = rec.path || '—';
    $('fps').textContent = state.fps.toFixed(1);
    $('frames').textContent = state.frames;
    $('mbps').textContent = state.mbps.toFixed(1);
    $('gaps').textContent = (state.stats || {}).gaps || 0;
    $('errors').textContent = (state.stats || {}).decode_errors || 0;
    const meta = state.meta || {};
    const info = meta.metadata || {};
    $('frame_id').textContent = meta.frame_id ?? '—';
    $('resolution').textContent = info.width
      ? info.width + '×' + info.height + (info.depthWidth ? ' / ' + info.depthWidth + '×' + info.depthHeight : '')
      : '—';
    $('tracking').textContent = info.trackingState || '—';
    $('depth_source').textContent = info.depthSource || '—';
    $('command').textContent = state.last_sent
      ? 'L' + Math.round(state.last_sent.left * 255) + ' R' + Math.round(state.last_sent.right * 255)
      : '—';
    $('robot').textContent = 'robot ' + ((state.stats || {}).robot || '—');
    const planes = state.planes || {};
    const enabled = planes.enabled || null;
    const marker = (name, hasData) => {
      if (hasData) return true;
      if (enabled && !enabled.includes(name)) return false;
      return 'pending';
    };
    const show = (wrapId, emptyId, src, state) => {
      const wrap = $(wrapId);
      wrap.classList.toggle('off', !state);
      if (state === false) {
        $(emptyId).textContent = '手机端已关闭该传感器';
      } else if (state === 'pending') {
        $(emptyId).textContent = '等待数据…';
      }
    };
    show('rgbWrap', 'rgbEmpty', '', marker('rgb', planes.rgb));
    show('depthWrap', 'depthEmpty', '', marker('depth', planes.depth));
    show('confWrap', 'confEmpty', '', marker('confidence', planes.confidence));
    if (planes.depth) $('depth').src = '/depth.png?a=' + Date.now();
    if (planes.confidence) $('confidence').src = '/confidence.png?a=' + Date.now();
  } catch (err) {
    $('pill').textContent = '连接中断';
  }
}
setInterval(tick, 300);
tick();
setInterval(() => { $('rgb').src = '/frame.jpg?a=' + Date.now(); }, 250);
</script>
</body>
</html>
"""
