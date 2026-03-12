#!/usr/bin/env python3
"""
OpenBene 连接诊断工具
逐层排查 iPhone ↔ PC 连接问题：
  Step 1: TCP — 端口是否可达？
  Step 2: HTTP — 服务器是否响应？
  Step 3: WebSocket — 能否升级协议？
  Step 4: 数据 — 能否收到心跳包？

用法:
    python diagnose.py
    python diagnose.py 192.168.100.200
"""

import sys
import os
import socket
import json
import time

# Allow running from examples/ without installing the package
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

PHONE_PORT = 8765
TIMEOUT = 5.0

# ──────────────────────────────────────────────
def _ok(msg):  print(f"  [OK]  {msg}")
def _fail(msg): print(f"  [FAIL] {msg}")
def _info(msg): print(f"        {msg}")
# ──────────────────────────────────────────────

def step1_tcp(ip: str, port: int) -> bool:
    """TCP: can we even open a socket to ip:port?"""
    print(f"\nStep 1 — TCP  ({ip}:{port})")
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(TIMEOUT)
        result = s.connect_ex((ip, port))
        s.close()
        if result == 0:
            _ok("TCP connection accepted")
            return True
        else:
            _fail(f"TCP connect_ex returned {result} (errno)")
            _info("→ Phone App is NOT listening on this port.")
            _info("  Check: App is open, server started, IP is correct.")
            return False
    except socket.timeout:
        _fail("TCP connection timed out")
        _info("→ Phone not reachable. Same WiFi? Correct IP?")
        return False
    except OSError as e:
        _fail(f"TCP socket error: {e}")
        return False


def step2_http_ping(ip: str, port: int) -> bool:
    """HTTP GET /ping — does the server respond to plain HTTP?"""
    print(f"\nStep 2 — HTTP ping  (GET http://{ip}:{port}/ping)")
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(TIMEOUT)
        s.connect((ip, port))
        request = (
            "GET /ping HTTP/1.1\r\n"
            f"Host: {ip}:{port}\r\n"
            "Connection: close\r\n"
            "\r\n"
        )
        s.sendall(request.encode())
        response = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            response += chunk
        s.close()

        text = response.decode(errors="replace")
        first_line = text.split("\r\n")[0] if text else ""
        if "200" in first_line:
            _ok(f"Server responded: {first_line}")
            # Try to parse JSON body
            if "{" in text:
                body = text[text.index("{"):]
                try:
                    data = json.loads(body)
                    _info(f"Server info: {data}")
                except Exception:
                    pass
            return True
        elif "101" in first_line or "426" in first_line:
            _ok(f"Server responded (WebSocket-only mode): {first_line}")
            _info("  Server is alive but only accepts WebSocket upgrades.")
            return True
        else:
            _fail(f"Unexpected HTTP response: {first_line}")
            _info("  Server is listening but returned an unexpected status.")
            return True  # TCP+HTTP works, issue is at WebSocket level
    except socket.timeout:
        _fail("HTTP request timed out — server accepted TCP but sent no response")
        _info("→ Server may be stuck or still starting. Wait 3s and retry.")
        return False
    except OSError as e:
        _fail(f"HTTP error: {e}")
        return False


def step3_websocket(ip: str, port: int) -> bool:
    """WebSocket upgrade — does the server complete the handshake?"""
    print(f"\nStep 3 — WebSocket upgrade  (ws://{ip}:{port})")
    try:
        import websockets
        import asyncio

        result = {"ok": False, "error": None, "msg": None}

        async def _test():
            uri = f"ws://{ip}:{port}"
            try:
                async with websockets.connect(uri, open_timeout=TIMEOUT + 2, proxy=None) as ws:
                    result["ok"] = True
                    _ok("WebSocket handshake succeeded!")
                    # Wait up to 8s for the first message (heartbeat / status)
                    try:
                        msg = await asyncio.wait_for(ws.recv(), timeout=8)
                        result["msg"] = msg
                        _info(f"First message from phone: {msg[:120]}")
                    except asyncio.TimeoutError:
                        _info("No message received in 8s (phone may need a PC command first)")
            except Exception as e:
                result["error"] = e

        asyncio.run(_test())

        if result["ok"]:
            return True
        else:
            _fail(f"WebSocket handshake failed: {result['error']}")
            err = str(result["error"])
            if "timed out" in err.lower():
                _info("→ Server accepted TCP but never sent HTTP 101.")
                _info("  Possible cause: App was just resumed from background.")
                _info("  Fix: wait 2 seconds after unlocking phone, then retry.")
            elif "refused" in err.lower():
                _info("→ Connection refused mid-handshake.")
                _info("  The server may have restarted between Step 1 and this step.")
            else:
                _info(f"  Raw error: {result['error']}")
            return False

    except ImportError:
        _fail("websockets not installed — run: pip install websockets")
        return False
    except Exception as e:
        _fail(f"Unexpected error: {e}")
        return False


def check_udp_broadcast(timeout: float = 6.0) -> bool:
    """Listen for phone's UDP discovery broadcast."""
    print(f"\nBonus — UDP auto-discovery (listening {timeout:.0f}s on port 12345)")
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.settimeout(1.0)
        s.bind(("", 12345))
        end = time.time() + timeout
        got = False
        while time.time() < end:
            try:
                data, addr = s.recvfrom(1024)
                msg = json.loads(data.decode())
                if msg.get("type") == "discovery":
                    _ok(f"Heard broadcast from {addr[0]}  →  {msg}")
                    got = True
                    break
            except socket.timeout:
                sys.stdout.write(".")
                sys.stdout.flush()
        s.close()
        print()
        if not got:
            _fail("No UDP broadcast received")
            _info("→ Either phone hasn't started server, UDP is blocked,")
            _info("  or iOS Local Network permission is denied.")
            _info("  Go to Settings → Privacy & Security → Local Network → enable App.")
        return got
    except OSError as e:
        _fail(f"UDP socket error: {e}  (port 12345 may be in use)")
        return False


def main():
    if len(sys.argv) >= 2:
        ip = sys.argv[1]
    else:
        ip = input("Enter phone IP (shown in App, e.g. 192.168.100.200): ").strip()
        if not ip:
            print("No IP entered. Running UDP discovery check only.")
            check_udp_broadcast()
            return

    print(f"\n{'='*55}")
    print(f"  OpenBene Connection Diagnostics")
    print(f"  Target: {ip}:{PHONE_PORT}")
    print(f"{'='*55}")

    ok1 = step1_tcp(ip, PHONE_PORT)
    if not ok1:
        print("\n⚠  Stopped at TCP — fix the network issue first.")
        check_udp_broadcast()
        return

    ok2 = step2_http_ping(ip, PHONE_PORT)
    if not ok2:
        print("\n⚠  TCP works but HTTP doesn't — server may be mid-restart.")
        print("  Wait 3 seconds and run again.")
        return

    ok3 = step3_websocket(ip, PHONE_PORT)

    print(f"\n{'='*55}")
    if ok3:
        print("  All steps passed — connection should work!")
        print(f"  Run: python full_demo.py  and enter IP: {ip}")
    else:
        print("  WebSocket step failed.")
        print("  If Step 1+2 passed but Step 3 fails consistently:")
        print("  → Rebuild the App with latest fixes and redeploy to phone.")
    print(f"{'='*55}\n")


if __name__ == "__main__":
    main()
