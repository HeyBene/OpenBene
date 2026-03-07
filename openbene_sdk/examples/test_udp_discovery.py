#!/usr/bin/env python3
"""
Quick diagnostic: test if UDP discovery broadcasts from the phone App
are actually reaching this PC.

Run this WHILE the phone App is running and the server is started.
If you see "Got broadcast!" messages, discovery works at the network level.
If nothing appears after 10 seconds, it's a firewall / network issue.
"""
import socket
import json
import time
import sys

PORT = 12345

print(f"Listening for UDP broadcasts on port {PORT}...")
print("Make sure the phone App is running and server is started.")
print("Waiting up to 15 seconds...\n")

try:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    # On Windows, also try SO_BROADCAST
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    except Exception:
        pass

    sock.bind(('', PORT))
    sock.settimeout(1.0)

    start = time.time()
    count = 0

    while time.time() - start < 15:
        try:
            data, addr = sock.recvfrom(2048)
            count += 1
            elapsed = time.time() - start
            try:
                msg = json.loads(data.decode('utf-8'))
                print(f"  [{elapsed:.1f}s] Got broadcast from {addr[0]}:{addr[1]}")
                print(f"         type={msg.get('type')}  name={msg.get('name')}")
                print(f"         ip={msg.get('ip')}  port={msg.get('port')}")
            except json.JSONDecodeError:
                print(f"  [{elapsed:.1f}s] Got raw data from {addr}: {data[:100]}")
        except socket.timeout:
            remaining = 15 - (time.time() - start)
            if remaining > 0:
                print(f"\r  Waiting... {remaining:.0f}s remaining", end='', flush=True)

    print(f"\n\nResult: received {count} broadcast(s) in 15 seconds.")
    if count == 0:
        print("\n  DIAGNOSIS: No UDP broadcasts received!")
        print("  Possible causes:")
        print("    1. Phone App server not started (press Start in the App)")
        print("    2. Phone and PC on different WiFi networks")
        print("    3. Windows Firewall blocking UDP port 12345")
        print("    4. Router isolating clients (AP isolation / guest network)")
        print("\n  Quick fix: try adding a Windows Firewall rule:")
        print('    netsh advfirewall firewall add rule name="OpenBene UDP" '
              'dir=in action=allow protocol=UDP localport=12345')
    else:
        print("\n  OK! UDP discovery is working at the network level.")
        print("  The auto_connect() in the SDK should work fine.")

except OSError as e:
    print(f"\nERROR: Could not bind to port {PORT}: {e}")
    print("  Another program might be using this port.")
    print("  Or try running as Administrator.")

finally:
    try:
        sock.close()
    except:
        pass
