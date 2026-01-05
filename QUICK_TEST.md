# Quick Test Guide - Milestone 1 Task 1.1

## 1. Test without Flutter (Using Mock App)

Open TWO terminal windows:

### Terminal 1 - Run Discovery Listener (Python)
```bash
cd openbene_sdk
python examples/test_discovery.py
```

Expected output:
```
==================================================
OpenBene Discovery Test
==================================================
Starting UDP listener on port 12345...
Make sure your OpenBene App is running and broadcasting.
Press Ctrl+C to stop.

2025-XX-XX XX:XX:XX - src.discovery - INFO - Discovery service started on UDP port 12345
2025-XX-XX XX:XX:XX - src.discovery - INFO - Waiting for OpenBene robots to broadcast...
```

### Terminal 2 - Run Mock Broadcaster (Simulates Flutter App)
```bash
cd openbene_sdk
python examples/mock_app.py "My-Test-Bot"
```

Expected output:
```
============================================================
Mock Flutter App - UDP Broadcast Simulator
============================================================
Bot Name: My-Test-Bot
Local IP: 192.168.x.x
Broadcasting to: 255.255.255.255:12345
Press Ctrl+C to stop.

[1] Sent: {'type': 'discovery', 'name': 'My-Test-Bot', 'ip': '192.168.x.x'}
[2] Sent: {'type': 'discovery', 'name': 'My-Test-Bot', 'ip': '192.168.x.x'}
...
```

### Expected Result in Terminal 1:
```
2025-XX-XX XX:XX:XX - src.discovery - INFO - Discovered Bot: [My-Test-Bot] at [192.168.x.x]

Bot Details:
   Name: My-Test-Bot
   IP: 192.168.x.x
   Type: discovery
--------------------------------------------------
```

## 2. Test with Flutter App (After Flutter Installation)

### Step 1: Initialize Flutter Project
```bash
cd openbene_app
flutter create . --platforms android,ios
flutter pub get
```

### Step 2: Connect Device and Run
```bash
flutter devices
flutter run
```

### Step 3: Run Discovery on PC
```bash
cd openbene_sdk
python examples/test_discovery.py
```

### Step 4: In Flutter App
- Click "Start Broadcasting" button
- Check Terminal 1 for discovery messages

## Success Criteria

- [x] Python listener receives UDP messages
- [x] JSON data is correctly parsed
- [x] Bot name and IP are correctly displayed
- [x] Messages arrive every 2 seconds
- [x] Both PC and App are on same network

## Troubleshooting

### Windows Firewall
If not receiving messages, allow Python through firewall:
```powershell
# Run as Administrator
New-NetFirewallRule -DisplayName "Python UDP 12345" -Direction Inbound -Protocol UDP -LocalPort 12345 -Action Allow
```

### Check Network
Make sure devices are on same subnet:
```bash
# On PC
ipconfig

# Verify IP range matches device IP
```
