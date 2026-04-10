from __future__ import annotations

import os
import select
import sys
import termios
import tty
from typing import Optional

from geometry_msgs.msg import Twist
import rclpy
from rclpy.node import Node

from .keyboard_teleop_logic import KeyboardTeleopCommand
from .keyboard_teleop_logic import KeyboardTeleopConfig
from .keyboard_teleop_logic import command_for_key


HELP_TEXT = """
OpenBene ROS2 keyboard teleop
-----------------------------
w: forward
s: reverse
a: turn left
d: turn right
q: forward-left arc
e: forward-right arc
space/x: stop
h: print help
ESC or Ctrl-C: quit

Tip:
- This node is meant to publish to /cmd_vel_user and let safety_cmd_vel gate motion.
- Motion is "hold by repeat": keep pressing / holding a key and it stays active.
- When you stop pressing, the command expires automatically after a short hold window.
""".strip()


class CmdVelKeyboard(Node):
    """Minimal terminal keyboard teleop for the semi-auto safety pipeline."""

    def __init__(self) -> None:
        super().__init__("openbene_cmd_vel_keyboard")

        self.declare_parameter("cmd_vel_topic", "/cmd_vel_user")
        self.declare_parameter("linear_speed_mps", 0.12)
        self.declare_parameter("angular_speed_radps", 0.40)
        self.declare_parameter("arc_linear_scale", 0.60)
        self.declare_parameter("hold_duration_sec", 0.25)
        self.declare_parameter("publish_rate_hz", 10.0)

        self._cmd_vel_topic = str(self.get_parameter("cmd_vel_topic").value)
        self._cfg = KeyboardTeleopConfig(
            linear_speed_mps=float(self.get_parameter("linear_speed_mps").value),
            angular_speed_radps=float(self.get_parameter("angular_speed_radps").value),
            arc_linear_scale=float(self.get_parameter("arc_linear_scale").value),
        )
        self._cfg.validate()

        self._hold_duration_sec = float(self.get_parameter("hold_duration_sec").value)
        self._publish_rate_hz = float(self.get_parameter("publish_rate_hz").value)
        if self._hold_duration_sec <= 0.0:
            raise ValueError("hold_duration_sec must be positive.")
        if self._publish_rate_hz <= 0.0:
            raise ValueError("publish_rate_hz must be positive.")

        if not sys.stdin.isatty():
            raise RuntimeError("cmd_vel_keyboard requires an interactive terminal (TTY).")

        self._stdin_fd = sys.stdin.fileno()
        self._stdin_settings = termios.tcgetattr(self._stdin_fd)
        tty.setraw(self._stdin_fd)

        self._publisher = self.create_publisher(Twist, self._cmd_vel_topic, 10)
        self._timer = self.create_timer(1.0 / self._publish_rate_hz, self._tick)
        self._active_command = KeyboardTeleopCommand(0.0, 0.0, "stop")
        self._command_deadline_ns = 0
        self._published_zero = False
        self._last_logged_label: str | None = None

        self.get_logger().info(f"Keyboard teleop publishing to '{self._cmd_vel_topic}'.")
        print(HELP_TEXT)

    def destroy_node(self) -> bool:
        self._restore_terminal()
        return super().destroy_node()

    def _restore_terminal(self) -> None:
        if hasattr(self, "_stdin_settings"):
            try:
                termios.tcsetattr(self._stdin_fd, termios.TCSADRAIN, self._stdin_settings)
            except Exception:
                pass
            delattr(self, "_stdin_settings")

    def _tick(self) -> None:
        self._drain_keys()

        now_ns = self.get_clock().now().nanoseconds
        if now_ns <= self._command_deadline_ns:
            self._publish_command(self._active_command)
            self._published_zero = False
            return

        if self._published_zero:
            return

        self._publish_command(KeyboardTeleopCommand(0.0, 0.0, "stop"))
        self._published_zero = True

    def _drain_keys(self) -> None:
        while True:
            ready, _, _ = select.select([sys.stdin], [], [], 0.0)
            if not ready:
                return

            key = os.read(self._stdin_fd, 1).decode(errors="ignore")
            if not key:
                return
            if key == "\x03":
                raise KeyboardInterrupt
            if key == "\x1b":
                raise KeyboardInterrupt
            if key.lower() == "h":
                print()
                print(HELP_TEXT)
                print()
                continue

            command = command_for_key(key, cfg=self._cfg)
            if command is None:
                continue

            self._active_command = command
            self._command_deadline_ns = (
                self.get_clock().now().nanoseconds + int(self._hold_duration_sec * 1e9)
            )
            self._published_zero = False
            if self._last_logged_label != command.label:
                self._last_logged_label = command.label
                self.get_logger().info(
                    "teleop key -> %s (linear=%.3f angular=%.3f)"
                    % (command.label, command.linear_x, command.angular_z)
                )

    def _publish_command(self, command: KeyboardTeleopCommand) -> None:
        msg = Twist()
        msg.linear.x = float(command.linear_x)
        msg.angular.z = float(command.angular_z)
        self._publisher.publish(msg)


def main(args: Optional[list[str]] = None) -> None:
    rclpy.init(args=args)
    node = CmdVelKeyboard()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()
