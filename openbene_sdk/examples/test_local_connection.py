#!/usr/bin/env python3
"""
Local loopback test: simulate the phone App (WebSocket server + UDP broadcast)
and the PC client on the SAME machine.

This lets you verify the discovery + connection logic WITHOUT a phone.

Usage:
    python test_local_connection.py

Expected output:
    [SERVER] WebSocket server started on 0.0.0.0:8765
    [BROADCAST] Sending UDP broadcast -> 127.0.0.1:12345 ...
    [DISCOVERY] Found robot: 127.0.0.1:8765
    [CLIENT] Connected to ws://127.0.0.1:8765
    [SERVER] PC connected!
    [CLIENT] Sent: {"cmd": "drive", "val": [0.3, 0.3]}
    [SERVER] Received: {"cmd": "drive", "val": [0.3, 0.3]}
    [CLIENT] Received: {"type": "echo", ...}
    OK - loopback test passed
"""

import asyncio
import json
import socket
import time
import threading
import sys

WS_PORT   = 8765
UDP_PORT  = 12345
HOST      = "127.0.0.1"
TEST_MSG  = {"cmd": "drive", "val": [0.3, 0.3]}

# ── shared state ─────────────────────────────────────────────────────────────
server_received: list = []
client_received: list = []
errors: list = []

# ── Phase 1: WebSocket server (simulates phone app) ───────────────────────────

async def _ws_server_handler(websocket):
    print("[SERVER] PC connected!")
    try:
        async for raw in websocket:
            msg = json.loads(raw)
            server_received.append(msg)
            print(f"[SERVER] Received: {raw}")
            # Echo back so the client can verify round-trip
            await websocket.send(json.dumps({"type": "echo", "original": msg}))
    except Exception as e:
        if "connection closed" not in str(e).lower():
            errors.append(f"server handler: {e}")

async def run_ws_server(stop_event: asyncio.Event):
    try:
        import websockets
    except ImportError:
        errors.append("websockets not installed — run: pip install websockets")
        stop_event.set()
        return

    async with websockets.serve(_ws_server_handler, "0.0.0.0", WS_PORT):
        print(f"[SERVER] WebSocket server started on 0.0.0.0:{WS_PORT}")
        await stop_event.wait()

# ── Phase 2: UDP broadcast (simulates DiscoveryService on phone) ──────────────

def run_udp_broadcast(stop_event: threading.Event, interval: float = 1.0):
    """Send UDP broadcasts to localhost just like the Flutter DiscoveryService."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    payload = json.dumps({
        "type": "discovery",
        "name": "OpenBene Robot (test)",
        "ip":   HOST,
        "port": WS_PORT,
    }).encode()

    try:
        while not stop_event.is_set():
            # localhost unicast (works even when broadcast is blocked by OS)
            sock.sendto(payload, (HOST, UDP_PORT))
            print(f"[BROADCAST] Sent UDP -> {HOST}:{UDP_PORT}")
            stop_event.wait(interval)
    finally:
        sock.close()

# ── Phase 3: UDP listener + WebSocket client (simulates PC openbene SDK) ──────

async def run_client(stop_event: asyncio.Event):
    try:
        import websockets
    except ImportError:
        errors.append("websockets not installed")
        stop_event.set()
        return

    # --- discover via UDP (with 5 s timeout) ---
    discovered_ip   = None
    discovered_port = None

    udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    udp_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    udp_sock.bind(("", UDP_PORT))
    udp_sock.settimeout(5.0)

    print(f"[DISCOVERY] Listening on UDP port {UDP_PORT} for 5 s...")
    deadline = time.time() + 5.0
    while time.time() < deadline:
        try:
            data, addr = udp_sock.recvfrom(1024)
            msg = json.loads(data.decode())
            if msg.get("type") == "discovery":
                discovered_ip   = msg["ip"]
                discovered_port = msg["port"]
                print(f"[DISCOVERY] Found robot: {discovered_ip}:{discovered_port}")
                break
        except socket.timeout:
            pass
        except Exception as e:
            errors.append(f"udp recv: {e}")
            break
    udp_sock.close()

    if not discovered_ip:
        errors.append("UDP discovery timed out — no broadcast received")
        stop_event.set()
        return

    # --- connect via WebSocket ---
    uri = f"ws://{discovered_ip}:{discovered_port}"
    try:
        async with websockets.connect(uri, open_timeout=5) as ws:
            print(f"[CLIENT] Connected to {uri}")

            # Send a test command
            await ws.send(json.dumps(TEST_MSG))
            print(f"[CLIENT] Sent: {json.dumps(TEST_MSG)}")

            # Wait for echo
            resp = await asyncio.wait_for(ws.recv(), timeout=3.0)
            client_received.append(json.loads(resp))
            print(f"[CLIENT] Received: {resp}")

    except Exception as e:
        errors.append(f"ws client: {e}")

    stop_event.set()   # signal server to shut down

# ── Main orchestrator ─────────────────────────────────────────────────────────

async def main():
    loop = asyncio.get_event_loop()
    server_stop = asyncio.Event()

    # Start server in same event loop
    server_task = asyncio.create_task(run_ws_server(server_stop))

    # Give server a moment to bind
    await asyncio.sleep(0.3)

    # Start UDP broadcast in background thread
    bcast_stop   = threading.Event()
    bcast_thread = threading.Thread(target=run_udp_broadcast,
                                    args=(bcast_stop,), daemon=True)
    bcast_thread.start()

    # Run client (discovery + connect + send/recv)
    await run_client(server_stop)

    # Clean up
    bcast_stop.set()
    await server_task

    # ── Result ──
    print("\n" + "=" * 50)
    if errors:
        print("FAILED")
        for e in errors:
            print(f"  ERROR: {e}")
        sys.exit(1)
    elif server_received and client_received:
        print("OK — loopback test passed")
        print(f"  Server received:  {server_received}")
        print(f"  Client received:  {client_received}")
    else:
        print("FAILED — no messages exchanged")
        print(f"  server_received={server_received}")
        print(f"  client_received={client_received}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
