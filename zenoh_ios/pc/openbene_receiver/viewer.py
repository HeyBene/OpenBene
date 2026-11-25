"""Local live preview for OpenBene Zenoh sessions.

Serves a small page at http://127.0.0.1:<port>/ with the latest RGB, depth and
confidence planes plus frame statistics. It is intentionally dependency free
(standard library only) so it can run next to the recorder on any machine.
"""

from __future__ import annotations

import json
import socketserver
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any


class LiveViewer:
    def __init__(
        self,
        host: str = "127.0.0.1",
        port: int = 8080,
        recording: Any | None = None,
    ) -> None:
        self.host = host
        self.port = port
        self.recording = recording
        self._lock = threading.Lock()
        self._rgb = b""
        self._depth = b""
        self._confidence = b""
        self._meta: dict[str, Any] = {}
        self._stats: dict[str, Any] = {}
        self._last_command: Any = None
        self._frames = 0
        self._frame_times: deque[float] = deque(maxlen=60)
        self._started_at = time.time()
        self._server: ThreadingHTTPServer | None = None
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

    # -- snapshot ---------------------------------------------------------

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            times = list(self._frame_times)
            frames = self._frames
            meta = dict(self._meta)
            stats = dict(self._stats)
            command = self._last_command
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
            "stats": stats,
            "last_command": command,
            "recording": recording_state,
        }

    def image(self, kind: str) -> tuple[bytes, str]:
        with self._lock:
            if kind == "depth":
                return self._depth, "image/png"
            if kind == "confidence":
                return self._confidence, "image/png"
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
            def log_message(self, *_args: Any) -> None:  # keep the terminal quiet
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
    """HTTPServer without the reverse-DNS lookup in server_bind().

    http.server.HTTPServer.server_bind() calls socket.getfqdn(), which can stall
    for tens of seconds on networks with a broken DNS server. The preview only
    needs a local socket, so bind directly.
    """

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
<title>OpenBene Zenoh Live</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; background: #0b0f14; color: #d8e2ec;
         font: 14px/1.45 -apple-system, BlinkMacSystemFont, "SF Mono", system-ui, sans-serif; }
  header { display: flex; align-items: center; gap: 12px; padding: 14px 20px;
           border-bottom: 1px solid #1d2733; background: #0e141b; position: sticky; top: 0; z-index: 5; }
  h1 { font-size: 15px; margin: 0; font-weight: 600; letter-spacing: .02em; }
  .pill { font-size: 11px; padding: 2px 8px; border-radius: 999px; border: 1px solid #2b3a4a; color: #8fa3b6; }
  .pill.live { color: #58d68d; border-color: #2f6f4c; background: #10251a; }
  .pill.rec { color: #ff8b8b; border-color: #7a2f2f; background: #2a1414; }
  .spacer { flex: 1; }
  main { display: grid; grid-template-columns: minmax(0, 2fr) minmax(300px, 1fr);
         gap: 16px; padding: 16px 20px 24px; }
  .card { background: #0f1620; border: 1px solid #1d2733; border-radius: 10px; overflow: hidden; }
  .card h2 { font-size: 11px; text-transform: uppercase; letter-spacing: .08em;
             color: #7f93a7; margin: 0; padding: 10px 12px; border-bottom: 1px solid #1d2733; }
  .stage { background: #05080c; display: grid; place-items: center; min-height: 320px; }
  .stage img { width: 100%; height: auto; display: block; }
  .planes { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-top: 12px; }
  .planes .stage { min-height: 140px; }
  dl { margin: 0; padding: 12px; display: grid; grid-template-columns: auto 1fr; gap: 6px 14px; }
  dt { color: #7f93a7; font-size: 12px; }
  dd { margin: 0; font-variant-numeric: tabular-nums; word-break: break-all; }
  .big { font-size: 22px; font-weight: 600; color: #eaf2fa; }
  code { font-size: 12px; color: #9fd3ff; }
  .muted { color: #62748a; font-size: 12px; }
  .controls { display: flex; gap: 10px; padding: 12px; border-top: 1px solid #1d2733; }
  button { flex: 1; padding: 9px 12px; border-radius: 8px; border: 1px solid #2b3a4a;
           background: #16212d; color: #d8e2ec; font: inherit; cursor: pointer; }
  button:hover { background: #1c2a38; }
  button.primary { background: #1f5c3a; border-color: #2f7a50; }
  button.primary:hover { background: #266c45; }
  button.danger { background: #5c1f1f; border-color: #7a2f2f; }
  button:disabled { opacity: .45; cursor: default; }
</style>
</head>
<body>
<header>
  <h1>OpenBene Zenoh Live</h1>
  <span id="pill" class="pill">等待数据…</span>
  <span id="recpill" class="pill">未录制</span>
  <span class="spacer"></span>
  <span id="robot" class="muted">robot —</span>
</header>
<main>
  <section class="card">
    <h2>RGB 实时画面</h2>
    <div class="stage"><img id="rgb" alt="RGB frame"></div>
    <div class="planes">
      <div class="card">
        <h2>深度</h2>
        <div class="stage"><img id="depth" alt="Depth"></div>
      </div>
      <div class="card">
        <h2>置信度</h2>
        <div class="stage"><img id="confidence" alt="Confidence"></div>
      </div>
    </div>
  </section>
  <aside class="card">
    <h2>传输状态</h2>
    <dl>
      <dt>帧率</dt><dd class="big" id="fps">0.0</dd>
      <dt>已收帧</dt><dd class="big" id="frames">0</dd>
      <dt>带宽</dt><dd id="mbps">0 MB/s</dd>
      <dt>跳号</dt><dd id="gaps">0</dd>
      <dt>坏包</dt><dd id="errors">0</dd>
      <dt>帧号</dt><dd id="frame_id">—</dd>
      <dt>分辨率</dt><dd id="resolution">—</dd>
      <dt>跟踪状态</dt><dd id="tracking">—</dd>
      <dt>深度来源</dt><dd id="depth_source">—</dd>
      <dt>最近命令</dt><dd id="command">—</dd>
      <dt>录制文件</dt><dd><code id="recording">—</code></dd>
    </dl>
    <div class="controls">
      <button id="start" class="primary">开始录制</button>
      <button id="stop" class="danger" disabled>停止录制</button>
    </div>
  </aside>
</main>
<script>
const $ = (id) => document.getElementById(id);

async function toggle(path) {
  $('start').disabled = true;
  $('stop').disabled = true;
  try {
    await fetch(path, {method: 'POST'});
  } catch (err) {
    // state refresh below shows the result
  }
  await tick();
}

$('start').onclick = () => toggle('/record/start');
$('stop').onclick = () => toggle('/record/stop');

async function tick() {
  try {
    const state = await (await fetch('/state.json', {cache: 'no-store'})).json();
    $('pill').textContent = state.live ? 'LIVE' : '等待数据…';
    $('pill').className = 'pill' + (state.live ? ' live' : '');
    const rec = state.recording || {};
    $('recpill').textContent = rec.active ? '录制中' : '未录制';
    $('recpill').className = 'pill' + (rec.active ? ' rec' : '');
    $('start').disabled = rec.active;
    $('stop').disabled = !rec.active;
    $('fps').textContent = state.fps.toFixed(1);
    $('frames').textContent = state.frames;
    $('mbps').textContent = state.mbps.toFixed(2) + ' MB/s';
    $('gaps').textContent = (state.stats || {}).gaps ?? 0;
    $('errors').textContent = (state.stats || {}).decode_errors ?? 0;
    const meta = state.meta || {};
    $('frame_id').textContent = meta.frame_id ?? '—';
    $('resolution').textContent = meta.metadata
      ? meta.metadata.width + 'x' + meta.metadata.height +
        (meta.metadata.depthWidth ? ' / depth ' + meta.metadata.depthWidth + 'x' + meta.metadata.depthHeight : '')
      : '—';
    $('tracking').textContent = (meta.metadata || {}).trackingState ?? '—';
    $('depth_source').textContent = (meta.metadata || {}).depthSource ?? '—';
    $('command').textContent = state.last_command ? JSON.stringify(state.last_command) : '—';
    $('recording').textContent = rec.path || '未录制（点击左侧按钮开始）';
    $('robot').textContent = 'robot ' + ((state.stats || {}).robot || '—');
    if (state.live) {
      $('depth').src = '/depth.png?a=' + Date.now();
      $('confidence').src = '/confidence.png?a=' + Date.now();
    }
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
