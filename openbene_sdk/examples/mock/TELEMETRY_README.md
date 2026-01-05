# Telemetry Testing

Test bidirectional communication between PC and robot with real-time status updates.

## Components

### 1. Mock TCP Server (`mock_tcp_server.py`)

Simulates a complete robot with bidirectional communication:
- **Receives** control commands from PC (drive, stop)
- **Sends** status telemetry back to PC every 0.5 seconds

#### Usage

```bash
# Start mock robot server
python mock_tcp_server.py --port 8888 --interval 0.5
```

#### Protocol

**PC → Robot (Commands):**
```json
{"cmd": "drive", "val": [0.5, 0.5]}
{"cmd": "stop"}
```

**Robot → PC (Status):**
```json
{"type": "status", "bat": 12.4, "spd": [0.5, 0.5]}
```

### 2. Telemetry Dashboard (`telemetry_dashboard.py`)

Real-time viewer for robot telemetry data.

#### Usage

```bash
# Connect to mock server
python telemetry_dashboard.py --ip 127.0.0.1

# With control command test
python telemetry_dashboard.py --ip 127.0.0.1 --test

# Simple mode (no curses)
python telemetry_dashboard.py --ip 127.0.0.1 --simple
```

#### Display

```
============================================================
OpenBene Telemetry Dashboard
============================================================

Robot IP:     127.0.0.1:8888
Connected:    Yes

Last Update:  0.12s ago ✓
Updates Recv: 42

Battery:      12.38V (95%)
              [████████████████████]

Wheel Speeds:
  Left:  ====================  +0.50
  Right: ====================  +0.50

------------------------------------------------------------
Press Ctrl+C to quit

Last status: 14:32:51.234
```

## Complete Test Flow

### Terminal 1: Start Mock Robot

```bash
cd openbene_sdk/examples/mock
python mock_tcp_server.py
```

You should see:
```
INFO - Mock robot listening on 0.0.0.0:8888
INFO - Waiting for client connection...
```

### Terminal 2: Run Dashboard

```bash
cd openbene_sdk/examples
python telemetry_dashboard.py --ip 127.0.0.1 --test
```

You should see:
1. Connection established
2. Control command test (forward, backward, turns)
3. Real-time telemetry dashboard

### Expected Behavior

- **Mock server** receives commands and prints them
- **Dashboard** shows:
  - Battery voltage decreasing slowly (simulated drain)
  - Wheel speeds matching sent commands
  - Real-time updates every 0.5 seconds
  - Connection status

## Concurrent Safety

The SDK uses thread-safe patterns for telemetry:

```python
# SDK handles concurrency automatically
bot = OpenBene("192.168.1.100")
bot.connect()  # Starts listener thread

# Main thread: Send commands
bot.drive(0.5, 0.5)

# Listener thread: Receive status
battery = bot.get_battery_voltage()  # Thread-safe read

# Callback thread: React to updates
def on_status(status):
    print(f"Battery: {status['bat']}V")

bot.on_status_update(on_status)
```

## Troubleshooting

### No telemetry received

```
⚠️  No telemetry received yet
```

**Solution:** Make sure the server is sending status messages. Check server logs for "Sent telemetry".

### Connection refused

```
✗ Error: Connection refused
```

**Solution:** Start the mock server first, then run the dashboard.

### Curses not available

```
Note: Install 'windows-curses' for better display
```

**Solution (Windows):**
```bash
pip install windows-curses
```

**Solution (Linux/Mac):**
Curses is usually built-in, but if not:
```bash
pip install curses
```
