#!/usr/bin/env python3
"""
OpenBene Full Demo v4
Full Demo: Connect + Video + Game-like Control + Recording

Features:
  - Manual / Auto connect (manual recommended to avoid firewall issues)
  - Real-time video stream (OpenCV main thread, Windows compatible)
  - Sensor overlay (accelerometer / gyroscope / battery)
  - Game-style smooth control: hold WASD to move, W+A arc turn, release to stop
  - Global hotkeys: press R anytime to record, no window focus needed
  - Optional data recording, saves images + labels.csv

Controls (global hotkeys, work regardless of window focus):
  W/S        - Hold to go forward / backward (release to stop)
  A/D        - Hold to turn left / right
  W+A / W+D  - Arc turn (like a video game)
  Shift+A/D  - Drift sharp turn
  + / -      - Speed up / Speed down
  R          - Start / Stop recording
  ESC        - Quit
"""

import sys
import os
import subprocess
import time
import threading
from datetime import datetime

# Prefer installed package; fall back to src/ for dev
try:
    from openbene import OpenBene
except ImportError:
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))
    from openbene import OpenBene

# OpenCV
try:
    import cv2
    import numpy as np
    CV2_AVAILABLE = True
except ImportError:
    CV2_AVAILABLE = False
    print("[!] OpenCV not installed: pip install opencv-python")

# pynput (required for game-style hold-to-move control)
try:
    from pynput import keyboard
except ImportError:
    print("Installing pynput...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pynput"])
    from pynput import keyboard
    print("pynput installed!\n")


# =============================================
#  Utilities
# =============================================

def make_session_dir() -> str:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = os.path.join(os.path.dirname(__file__), "demo_data", ts)
    os.makedirs(path, exist_ok=True)
    return path


# =============================================
#  Connection
# =============================================

def connect_bot() -> OpenBene:
    """Connection menu: manual IP / auto-discover / exit"""
    while True:
        print("  Connection method:")
        print("    1. Enter phone IP manually")
        print("    2. Auto-discover (UDP broadcast + TCP subnet scan)")
        print("    0. Exit")
        choice = input("  > ").strip()

        if choice == '0':
            sys.exit(0)

        elif choice == '2':
            print("\n  [ Auto-discovering robot... ]")
            print("    Phase 1: Listening for UDP broadcast (~5s)")
            print("    Phase 2: TCP subnet scan if UDP fails (~8s)")
            try:
                bot = OpenBene.auto_connect(timeout=60.0)
                print(f"  OK  Connected -> {bot.ip}:{bot.port}\n")
                return bot
            except Exception as e:
                print(f"  X   Auto-discover failed: {e}\n")

        else:  # default = manual
            ip = input("  Enter phone IP (shown in the App): ").strip()
            if not ip:
                continue
            try:
                bot = OpenBene(ip)
                bot.connect(timeout=30.0)
                print(f"  OK  Connected -> {bot.ip}:{bot.port}\n")
                return bot
            except Exception as e:
                print(f"  X   Connection failed: {e}\n")


# =============================================
#  Sensor Poller (background thread)
# =============================================

class SensorPoller(threading.Thread):
    def __init__(self, bot, state):
        super().__init__(daemon=True)
        self.bot, self.state, self.running = bot, state, True

    def run(self):
        while self.running and self.bot.connected:
            try:
                data = self.bot.get_sensors()
                if data:
                    # Only update fields that carry real values
                    for key in ('accelerometer', 'gyroscope', 'magnetometer', 'battery_level'):
                        val = data.get(key)
                        if val is not None:
                            self.state[key] = val
            except Exception:
                pass
            time.sleep(0.5)

    def stop(self):
        self.running = False


# =============================================
#  Game-style Differential Controller
# =============================================

class GameController:
    """
    pynput listens for keys (global hotkeys, no window focus needed).
    Background thread calculates differential motor values at ~30Hz.
    W+A = arc left, W+D = arc right, like driving in a game.
    """

    # Turning parameters  (v4: much more aggressive arc turns)
    TURN_RATIO  = -0.1       # Arc turn: inner wheel = speed * TURN_RATIO (slight reverse for tight arc)
    DRIFT_RATIO = -0.5       # Drift: inner wheel reverses harder
    SPIN_SPEED  = 0.6        # In-place spin speed multiplier
    MIN_MOTOR   = 0.35       # Motor dead-zone compensation

    def __init__(self, bot, speed_ref, session_dir, rec_state):
        self.bot = bot
        self.speed_ref = speed_ref          # [0.6] mutable reference
        self.session_dir = session_dir
        self.rec_state = rec_state

        self.pressed = set()
        self.running = True
        self._listener = None

    def _deadzone(self, v):
        """Dead-zone compensation: maps 0~1 to MIN_MOTOR~1"""
        if abs(v) < 0.01:
            return 0.0
        sign = 1 if v > 0 else -1
        return sign * (self.MIN_MOTOR + abs(v) * (1.0 - self.MIN_MOTOR))

    def _calc_motors(self):
        """Calculate left/right motor values from current key set"""
        keys = self.pressed
        speed = self.speed_ref[0]
        drift = 'shift' in keys
        fwd   = 'w' in keys
        bwd   = 's' in keys
        left  = 'a' in keys
        right = 'd' in keys

        if not (fwd or bwd or left or right):
            return 0.0, 0.0

        # Base forward/backward speed
        base = speed if fwd else (-speed if bwd else 0.0)
        L, R = base, base

        if left:
            if drift and base != 0:
                L = base * self.DRIFT_RATIO       # Drift: inner wheel reverses
            elif base != 0:
                L = base * self.TURN_RATIO        # Arc: inner wheel slows/reverses
            else:
                L, R = -speed * self.SPIN_SPEED, speed * self.SPIN_SPEED  # Spin in place
        elif right:
            if drift and base != 0:
                R = base * self.DRIFT_RATIO
            elif base != 0:
                R = base * self.TURN_RATIO
            else:
                L, R = speed * self.SPIN_SPEED, -speed * self.SPIN_SPEED

        L = max(-1.0, min(1.0, self._deadzone(L)))
        R = max(-1.0, min(1.0, self._deadzone(R)))
        return L, R

    # -- Motor loop (background thread) --------
    def _motor_loop(self):
        last = (0.0, 0.0)
        last_print = 0.0

        while self.running and self.bot.connected:
            L, R = self._calc_motors()

            if (L, R) != last:
                if L == 0 and R == 0:
                    self.bot.stop()
                else:
                    self.bot.drive(L, R)

                # Sync to recorder
                try:
                    if self.bot._recorder and self.bot._recorder.is_recording:
                        cmd = "stop" if (L == 0 and R == 0) else "drive"
                        self.bot._recorder.set_command(cmd, [L, R])
                except Exception:
                    pass

                last = (L, R)

                # Terminal status (rate-limited)
                now = time.time()
                if now - last_print > 0.15:
                    if L == 0 and R == 0:
                        st = "STOP"
                    else:
                        st = f"L:{L:+.2f} R:{R:+.2f}"
                        if 'shift' in self.pressed:
                            st += " [DRIFT]"
                    rec = " * REC" if self.rec_state.get('recording') else ""
                    spd = int(self.speed_ref[0] * 100)
                    print(f"\r  Speed {spd}% | {st}{rec}                    ", end='', flush=True)
                    last_print = now

            time.sleep(0.03)

    # -- pynput callbacks ----------------------
    def _on_press(self, key):
        try:
            k = key.char.lower()
            self.pressed.add(k)

            if k in ('+', '='):
                self.speed_ref[0] = min(1.0, round(self.speed_ref[0] + 0.1, 1))
                print(f"\r  Speed: {int(self.speed_ref[0]*100)}%                              ", flush=True)
            elif k in ('-', '_'):
                self.speed_ref[0] = max(0.1, round(self.speed_ref[0] - 0.1, 1))
                print(f"\r  Speed: {int(self.speed_ref[0]*100)}%                              ", flush=True)
            elif k == 'r':
                if self.bot._recorder and self.bot._recorder.is_recording:
                    self.bot.stop_recording()
                    self.rec_state['recording'] = False
                    print(f"\r  [STOP] Recording stopped                        ", flush=True)
                else:
                    self.bot.start_recording(self.session_dir)
                    self.rec_state['recording'] = True
                    self.rec_state['frames'] = 0
                    print(f"\r  [REC]  Recording started                        ", flush=True)
        except AttributeError:
            if key in (keyboard.Key.shift, keyboard.Key.shift_l, keyboard.Key.shift_r):
                self.pressed.add('shift')
            elif key == keyboard.Key.esc:
                self.running = False
                return False  # stop listener

    def _on_release(self, key):
        try:
            self.pressed.discard(key.char.lower())
        except AttributeError:
            if key in (keyboard.Key.shift, keyboard.Key.shift_l, keyboard.Key.shift_r):
                self.pressed.discard('shift')

    # -- Start / Stop -------------------------
    def start(self):
        """Start motor loop thread + pynput listener"""
        threading.Thread(target=self._motor_loop, daemon=True).start()
        self._listener = keyboard.Listener(
            on_press=self._on_press,
            on_release=self._on_release
        )
        self._listener.start()

    def wait(self):
        """Block until ESC"""
        if self._listener:
            self._listener.join()

    def stop(self):
        self.running = False
        self.bot.stop()
        if self._listener:
            self._listener.stop()


# =============================================
#  Video Overlay
# =============================================

def draw_overlay(frame, sensor_state, rec_state, speed):
    h, w = frame.shape[:2]
    ov = frame.copy()

    # Top bar and bottom bar
    cv2.rectangle(ov, (0, 0), (w, 90), (0, 0, 0), -1)
    cv2.rectangle(ov, (0, h - 30), (w, h), (0, 0, 0), -1)
    cv2.addWeighted(ov, 0.45, frame, 0.55, 0, frame)

    accel = sensor_state.get('accelerometer')
    gyro  = sensor_state.get('gyroscope')
    bat   = sensor_state.get('battery_level')

    lines = []

    # Only show sensor values that are actually available and non-trivial
    if accel and isinstance(accel, dict):
        ax, ay, az = accel.get('x', 0), accel.get('y', 0), accel.get('z', 0)
        if not (ax == 0 and ay == 0 and az == 0):
            lines.append(f"Accel  X:{ax:+6.2f}  Y:{ay:+6.2f}  Z:{az:+6.2f}")

    if gyro and isinstance(gyro, dict):
        gx, gy, gz = gyro.get('x', 0), gyro.get('y', 0), gyro.get('z', 0)
        if not (gx == 0 and gy == 0 and gz == 0):
            lines.append(f"Gyro   X:{gx:+6.2f}  Y:{gy:+6.2f}  Z:{gz:+6.2f}")

    if bat is not None and bat > 0:
        lines.append(f"Battery: {bat:.0f}%")

    if not lines:
        lines.append("Sensors: waiting for data...")

    for i, l in enumerate(lines):
        cv2.putText(frame, l, (10, 22 + i * 24),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.50, (0, 255, 150), 1, cv2.LINE_AA)

    # Recording indicator (top-right)
    if rec_state.get('recording'):
        n = rec_state.get('frames', 0)
        cv2.circle(frame, (w - 20, 16), 8, (0, 0, 255), -1)
        cv2.putText(frame, f"REC {n}", (w - 100, 21),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.50, (0, 0, 255), 1, cv2.LINE_AA)
    else:
        cv2.putText(frame, "[R] Record", (w - 130, 21),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.42, (180, 180, 180), 1, cv2.LINE_AA)

    # Bottom hint bar
    hint = f"Speed:{int(speed*100)}%  WASD:Move  Shift:Drift  +/-:Speed  R:Record  ESC:Quit"
    cv2.putText(frame, hint, (6, h - 8),
                cv2.FONT_HERSHEY_SIMPLEX, 0.38, (200, 200, 200), 1, cv2.LINE_AA)
    return frame


# =============================================
#  Main
# =============================================

def main():
    print("\n" + "=" * 60)
    print("   OpenBene Full Demo v4")
    print("=" * 60)
    print("  Game-style control: Hold WASD to move, W+A for arc turns")
    print("  Global hotkeys: Press R/ESC anytime, no window focus needed")
    print("=" * 60 + "\n")

    # -- 1. Connect ----------------------------
    print("Step 1/3  Connect to phone\n")
    bot = connect_bot()

    # -- 2. Recording option -------------------
    session_dir = make_session_dir()
    print(f"  Data directory: {session_dir}")
    do_rec = input("  Start recording now? [y/N]: ").strip().lower() == 'y'
    rec_state = {'recording': False, 'frames': 0}
    if do_rec:
        bot.start_recording(session_dir)
        rec_state['recording'] = True
        print("  OK  Recording started\n")
    else:
        print("  (Press R anytime to start recording)\n")

    # -- 3. Background threads -----------------
    sensor_state = {}
    sensor_poller = SensorPoller(bot, sensor_state)
    sensor_poller.start()

    # Frame count sync
    def _sync_frames():
        while bot.connected:
            if bot._recorder and bot._recorder.is_recording:
                rec_state['recording'] = True
                rec_state['frames'] = getattr(bot._recorder, '_frame_counter', 0)
            else:
                rec_state['recording'] = False
            time.sleep(0.3)
    threading.Thread(target=_sync_frames, daemon=True).start()

    # -- 4. Game controller --------------------
    speed = [0.6]
    ctrl = GameController(bot, speed, session_dir, rec_state)
    ctrl.start()

    # -- 5. Main thread: video loop -----------
    print("Step 2/3  Running\n")
    print("  +--------------------------------------------+")
    print("  |  W/S         Hold forward / backward       |")
    print("  |  A/D         Hold turn left / right        |")
    print("  |  W+A / W+D   Arc turn (like a game!)       |")
    print("  |  Shift+A/D   Drift sharp turn              |")
    print("  |  + / -       Speed up / Speed down         |")
    print("  |  R           Start/Stop recording (global) |")
    print("  |  ESC         Quit                          |")
    print("  +--------------------------------------------+")
    print("  * No need to click any window - just press keys!\n")

    if CV2_AVAILABLE:
        WINDOW = "OpenBene Live View"
        cv2.namedWindow(WINDOW, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(WINDOW, 800, 500)

        while ctrl.running and bot.connected:
            frame = bot.get_frame()
            if frame is not None:
                frame = draw_overlay(frame, sensor_state, rec_state, speed[0])
                cv2.imshow(WINDOW, frame)

            # waitKey only refreshes the OpenCV window; keys are captured by pynput
            k = cv2.waitKey(30) & 0xFF
            if k == 27:  # ESC also works in video window
                ctrl.running = False
                break

        cv2.destroyAllWindows()
    else:
        # No video, pynput still works
        print("  (No OpenCV - keyboard control only, press ESC to quit)")
        ctrl.wait()

    # -- 6. Cleanup ----------------------------
    ctrl.stop()
    sensor_poller.stop()

    print("\n\n" + "=" * 60)
    print("Step 3/3  Demo finished")

    if bot._recorder and bot._recorder.is_recording:
        bot.stop_recording()
    bot.disconnect()
    print("  Disconnected")

    images_dir = os.path.join(session_dir, "images")
    labels_csv = os.path.join(session_dir, "labels.csv")
    n_img = len(os.listdir(images_dir)) if os.path.isdir(images_dir) else 0
    print(f"\n  Data saved to: {session_dir}")
    print(f"     images/ : {n_img} frames")
    if os.path.isfile(labels_csv):
        with open(labels_csv) as f:
            n_rows = max(0, sum(1 for _ in f) - 1)
        print(f"     labels.csv : {n_rows} rows")
    else:
        print(f"     labels.csv : (not recorded)")

    print("\nDone!\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
