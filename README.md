# OpenBene

![Python Version](https://img.shields.io/badge/python-3.8%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
[![GitHub Discussions](https://img.shields.io/github/discussions/HeyBene/OpenBene)](https://github.com/HeyBene/OpenBene/discussions)

**Languages:** English | [简体中文](README.zh-CN.md)

**Phone as Body, PC as Brain** - control OpenBot-based robots from Python with a public platform-layer toolkit.

> Scope note:
> `OpenBene` is the public platform-layer repository.
> ROS2, mapping, localization, and other internal mobility work are promoted here selectively after cleanup.
> See [docs/OPENBENE_SCOPE.md](docs/OPENBENE_SCOPE.md) for the boundary.

[![Join Discussion](https://img.shields.io/badge/Join_Discussion-GitHub_Discussions-blue?style=for-the-badge)](https://github.com/HeyBene/OpenBene/discussions)

## Overview

OpenBene focuses on reusable platform capabilities:

- Python SDK for robot control
- Phone app workflows for OpenBot-style robots
- WebSocket connectivity and discovery
- Video, sensor, and recording support
- BLE manual-control utilities for ESP32/OpenBot workflows

## Architecture

```text
PC (Python) -> WebSocket -> Phone App -> USB/BLE -> Robot Controller -> Motors
```

## Quick Start

Before you start:

- Python `3.8+`
- phone and PC on the same local network
- the phone app shows `Waiting for PC...`
- the phone app shows a valid `Server Address`

### 1. Prepare the phone app

If an Android build is included for your release, start here:

- [openbot-mobile-control/releases/README.md](openbot-mobile-control/releases/README.md)

For source-based mobile development:

- Flutter app: [openbot-mobile-control](openbot-mobile-control)

Important:

- Always use the server address shown inside the app UI.
- On iOS, confirm Local Network permission is enabled for the app.

### 2. Install the Python SDK

```bash
cd openbene_sdk
pip install -e .
```

Optional but recommended:

```bash
python -m venv .venv
```

### 3. Run the full demo

```bash
cd openbene_sdk/examples
python full_demo.py
```

The demo can guide you through:

- manual phone IP connection
- auto-discovery connection
- motion control
- video preview
- sensor reading
- data recording

Success looks like:

- the demo finds the phone automatically, or connects with the displayed IP
- control commands reach the robot
- video or sensor output starts appearing in the demo flow

### 4. Basic Python example

```python
from openbene import OpenBene

bot = OpenBene.auto_connect()
print(f"Connected to {bot.ip}:{bot.port}")

bot.forward(0.5)

import time
time.sleep(2)

bot.stop()
bot.disconnect()
```

If auto-discovery fails, use the phone app's displayed address and run:

```bash
cd openbene_sdk/examples
python diagnose.py <phone_ip>
```

### 5. Quick troubleshooting

1. Confirm the phone and PC are on the same subnet.
2. Use the app's displayed `Server Address`; do not guess the IP manually.
3. On Windows, verify the WebSocket port:

```powershell
Test-NetConnection -ComputerName <phone_ip> -Port 8765
```

4. If `PingSucceeded=True` but `TcpTestSucceeded=False`, disable VPN/proxy/TUN and retry.
5. On iOS, check:
   `Settings -> Privacy & Security -> Local Network -> OpenBene = ON`

## SDK Entry Points

Useful examples:

```bash
python examples/basic_control.py
python examples/interactive_control.py
python examples/video_display.py
python examples/video_recording_demo.py
python examples/data_collection.py
python examples/test_udp_discovery.py
python examples/diagnose.py <phone_ip>
```

For Windows BLE manual control to ESP32/OpenBot firmware:

- [docs/WINDOWS_BLE_CONTROL_RUNBOOK.md](docs/WINDOWS_BLE_CONTROL_RUNBOOK.md)

## Project Structure

```text
OpenBene/
├── .github/                     # GitHub config and workflows
├── docs/                        # Public documentation
├── openbene_sdk/                # Python SDK
│   ├── src/                     # Core SDK code
│   ├── examples/                # Example scripts
│   └── tests/                   # SDK tests
├── openbot/                     # Firmware / hardware baseline
├── openbot-mobile-control/      # Flutter mobile app
├── README.md                    # English README (default)
├── README.zh-CN.md              # Simplified Chinese README
├── PROJECT_CONTEXT.md           # Architecture and project context
└── CHANGELOG.md                 # Changelog
```

## Documentation

- [openbene_sdk/README.md](openbene_sdk/README.md) - SDK documentation
- [openbot-mobile-control/releases/README.md](openbot-mobile-control/releases/README.md) - Android build and release notes
- [docs/WINDOWS_BLE_CONTROL_RUNBOOK.md](docs/WINDOWS_BLE_CONTROL_RUNBOOK.md) - Windows BLE control workflow
- [docs/OPENBENE_SCOPE.md](docs/OPENBENE_SCOPE.md) - Public scope boundary
- [docs/MOBILITY_SYNC_RULES.md](docs/MOBILITY_SYNC_RULES.md) - Rules for promoting internal mobility work into public OpenBene
- [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) - Architecture context
- [CHANGELOG.md](CHANGELOG.md) - Changelog

## Contributing

We welcome contributions.

- [Report Bug](https://github.com/HeyBene/OpenBene/issues/new?template=bug_report.yml)
- [Feature Request](https://github.com/HeyBene/OpenBene/issues/new?template=feature_request.yml)
- [Contributing Guide](CONTRIBUTING.md)
- [GitHub Discussions](https://github.com/HeyBene/OpenBene/discussions)

## Acknowledgments

This project builds on:

- [OpenBot](https://github.com/isl-org/OpenBot) - open-source robot platform by Intel ISL

## License

MIT License. See [LICENSE](LICENSE).
