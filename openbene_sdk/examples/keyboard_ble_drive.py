#!/usr/bin/env python3
"""Windows-first keyboard teleop for OpenBot ESP32 BLE."""

from __future__ import annotations

import argparse
import asyncio
from dataclasses import dataclass
import sys
import time

try:
    import msvcrt
except ImportError:  # pragma: no cover - Windows-only script
    msvcrt = None  # type: ignore[assignment]


SCRIPT_DIR = __file__
try:
    from pathlib import Path

    SDK_ROOT = Path(SCRIPT_DIR).resolve().parents[1] / "src"
    if str(SDK_ROOT) not in sys.path:
        sys.path.insert(0, str(SDK_ROOT))
except Exception:
    pass

from openbene.esp32_ble import OpenBotBleClient
from openbene.esp32_ble import clamp_pwm
from openbene.esp32_ble import parse_esp_message
from openbene.esp32_ble import scan_openbot_devices


HELP_TEXT = """
OpenBot ESP32 BLE keyboard drive
--------------------------------
w: forward
s: reverse
a: turn left
d: turn right
q: forward-left arc
e: forward-right arc
space/x: stop
h: print help
ESC or Ctrl-C: quit

Safety model:
- Keep pressing or holding a key to continue moving.
- When key repeat stops, the command expires and the tool sends stop().
- A BLE heartbeat is sent continuously so the MCU can also stop on timeout.
""".strip()


@dataclass(frozen=True)
class DriveCommand:
    left: int
    right: int
    label: str


def command_for_key(raw_key: str, *, drive_pwm: int, turn_pwm: int, arc_scale: float) -> DriveCommand | None:
    if len(raw_key) != 1:
        return None

    key = raw_key.lower()
    drive = clamp_pwm(drive_pwm)
    turn = clamp_pwm(turn_pwm)
    arc_inner = clamp_pwm(int(round(drive * arc_scale)))

    if key == "w":
        return DriveCommand(drive, drive, "forward")
    if key == "s":
        return DriveCommand(-drive, -drive, "reverse")
    if key == "a":
        return DriveCommand(-turn, turn, "turn_left")
    if key == "d":
        return DriveCommand(turn, -turn, "turn_right")
    if key == "q":
        return DriveCommand(arc_inner, drive, "arc_left")
    if key == "e":
        return DriveCommand(drive, arc_inner, "arc_right")
    if key in ("x", " "):
        return DriveCommand(0, 0, "stop")
    return None


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Windows keyboard control over BLE for OpenBot ESP32 firmware.")
    parser.add_argument("--address", default="", help="BLE MAC/address. If omitted, scan and choose interactively.")
    parser.add_argument("--scan-timeout", type=float, default=6.0, help="BLE scan timeout in seconds.")
    parser.add_argument("--drive-pwm", type=int, default=80, help="PWM used for forward/reverse commands.")
    parser.add_argument("--turn-pwm", type=int, default=90, help="PWM used for turn-in-place commands.")
    parser.add_argument("--arc-scale", type=float, default=0.55, help="Inner wheel scale for q/e arc moves.")
    parser.add_argument("--hold-seconds", type=float, default=0.30, help="How long one key repeat stays active.")
    parser.add_argument("--heartbeat-ms", type=int, default=300, help="MCU heartbeat timeout to advertise.")
    parser.add_argument("--telemetry-ms", type=int, default=500, help="Telemetry report interval. 0 disables telemetry.")
    parser.add_argument("--loop-hz", type=float, default=10.0, help="Control loop frequency.")
    parser.add_argument("--verbose-telemetry", action="store_true", help="Print wheel/sonar/voltage telemetry.")
    return parser


def print_message(parsed: dict[str, object], *, verbose: bool) -> None:
    message_type = parsed.get("type")
    if message_type == "features":
        print(
            f"[BLE] firmware={parsed.get('robot_type')} caps={parsed.get('capabilities')}",
            flush=True,
        )
        return
    if message_type == "bumper":
        print(f"[BLE] bumper={parsed.get('collision_id')} -> emergency stop on MCU", flush=True)
        return
    if not verbose:
        return
    if message_type == "voltage":
        print(f"[BLE] voltage={parsed.get('voltage')}V", flush=True)
    elif message_type == "wheel":
        print(f"[BLE] wheel rpm L={parsed.get('rpm_left')} R={parsed.get('rpm_right')}", flush=True)
    elif message_type == "sonar":
        print(f"[BLE] sonar={parsed.get('distance_cm')}cm", flush=True)
    elif message_type == "unknown" and parsed.get("raw"):
        print(f"[BLE] raw={parsed.get('raw')}", flush=True)


async def choose_device(scan_timeout: float) -> str:
    devices = await scan_openbot_devices(timeout=scan_timeout)
    if not devices:
        raise RuntimeError("No OpenBot BLE device found. Confirm ESP32 firmware is advertising over BLE.")
    if len(devices) == 1:
        device = devices[0]
        print(f"[BLE] Selected {device.name} ({device.address})")
        return str(device.address)

    print("[BLE] Multiple OpenBot devices found:")
    for index, device in enumerate(devices):
        print(f"  [{index}] {device.name} ({device.address})")

    while True:
        raw = input("Choose device index [0]: ").strip()
        if not raw:
            return str(devices[0].address)
        try:
            choice = int(raw)
        except ValueError:
            print("Please enter a valid number.")
            continue
        if 0 <= choice < len(devices):
            return str(devices[choice].address)
        print("Choice out of range.")


async def run_keyboard_drive(args: argparse.Namespace) -> None:
    if msvcrt is None:
        raise RuntimeError("keyboard_ble_drive.py currently supports Windows terminals only.")
    if args.loop_hz <= 0.0:
        raise ValueError("--loop-hz must be positive.")
    if args.hold_seconds <= 0.0:
        raise ValueError("--hold-seconds must be positive.")
    if args.heartbeat_ms <= 0:
        raise ValueError("--heartbeat-ms must be positive.")

    address = args.address.strip() or await choose_device(args.scan_timeout)
    client = OpenBotBleClient(address)
    client.add_message_callback(lambda parsed: print_message(parsed, verbose=args.verbose_telemetry))

    print(f"[BLE] Connecting to {address} ...")
    await client.connect()
    print("[BLE] Connected.")
    try:
        await client.start_notify()
        await client.request_features()
        if args.telemetry_ms > 0:
            await client.enable_basic_telemetry(args.telemetry_ms)

        print()
        print(HELP_TEXT)
        print()

        loop_period = 1.0 / args.loop_hz
        heartbeat_period = max(0.05, (args.heartbeat_ms / 1000.0) / 3.0)
        last_heartbeat = 0.0
        current_command = DriveCommand(0, 0, "stop")
        current_deadline = 0.0
        sent_idle_stop = False
        last_label: str | None = None

        while True:
            while msvcrt.kbhit():
                raw = msvcrt.getwch()
                if raw in ("\x03", "\x1b"):
                    raise KeyboardInterrupt
                if raw.lower() == "h":
                    print()
                    print(HELP_TEXT)
                    print()
                    continue

                command = command_for_key(
                    raw,
                    drive_pwm=args.drive_pwm,
                    turn_pwm=args.turn_pwm,
                    arc_scale=args.arc_scale,
                )
                if command is None:
                    continue
                current_command = command
                current_deadline = time.monotonic() + args.hold_seconds
                sent_idle_stop = False
                if command.label != last_label:
                    last_label = command.label
                    print(
                        f"[CMD] {command.label} -> left={command.left} right={command.right}",
                        flush=True,
                    )

            now = time.monotonic()
            if now - last_heartbeat >= heartbeat_period:
                await client.send_heartbeat(args.heartbeat_ms)
                last_heartbeat = now

            if now <= current_deadline:
                await client.send_drive(current_command.left, current_command.right)
                sent_idle_stop = False
            elif not sent_idle_stop:
                await client.send_stop()
                sent_idle_stop = True
                if last_label != "idle_stop":
                    last_label = "idle_stop"
                    print("[CMD] idle_stop -> left=0 right=0", flush=True)

            await asyncio.sleep(loop_period)
    finally:
        try:
            await client.send_stop()
        except Exception:
            pass
        try:
            await client.stop_notify()
        except Exception:
            pass
        await client.disconnect()
        print("[BLE] Disconnected.")


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        asyncio.run(run_keyboard_drive(args))
        return 0
    except KeyboardInterrupt:
        print("\n[BLE] Keyboard exit requested.")
        return 0
    except Exception as exc:
        print(f"[!] {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
