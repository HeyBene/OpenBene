from __future__ import annotations

import os
from typing import Optional

from geometry_msgs.msg import Twist
import rclpy
from rclpy.node import Node

from .kinematics import twist_to_drive


class CmdVelBridge(Node):
    """Bridge ROS 2 cmd_vel messages to OpenBene differential drive commands."""

    def __init__(self) -> None:
        super().__init__("openbene_cmd_vel_bridge")

        self.declare_parameter("cmd_vel_topic", "cmd_vel")
        self.declare_parameter("ip", os.environ.get("OPENBENE_SERVER_IP", ""))
        self.declare_parameter("port", 8765)
        self.declare_parameter("connect_on_startup", True)
        self.declare_parameter("dry_run", False)
        self.declare_parameter("log_commands", True)
        self.declare_parameter("linear_scale", 1.0)
        self.declare_parameter("angular_scale", 0.6)
        self.declare_parameter("command_timeout_sec", 0.75)

        self._bot = None
        self._openbene_import_error: Optional[Exception] = None
        self._last_command_time = self.get_clock().now()
        self._sent_timeout_stop = False
        self._dry_run = bool(self.get_parameter("dry_run").value)
        self._log_commands = bool(self.get_parameter("log_commands").value)
        self._cmd_vel_topic = str(self.get_parameter("cmd_vel_topic").value)

        self._subscription = self.create_subscription(
            Twist,
            self._cmd_vel_topic,
            self._handle_cmd_vel,
            10,
        )
        self._watchdog = self.create_timer(0.1, self._watchdog_tick)

        if self._dry_run:
            self.get_logger().info(
                f"Bridge started in dry_run mode. Listening on topic '{self._cmd_vel_topic}'."
            )
        elif self.get_parameter("connect_on_startup").value:
            self.connect()
        else:
            self.get_logger().info("Bridge started without auto-connect.")

    @property
    def connected(self) -> bool:
        return self._bot is not None and getattr(self._bot, "connected", False)

    def connect(self) -> bool:
        """Connect to the OpenBene phone server using current parameters."""
        if self._dry_run:
            return True

        ip = str(self.get_parameter("ip").value).strip()
        port = int(self.get_parameter("port").value)

        if not ip:
            self.get_logger().error(
                "No OpenBene server IP configured. Set parameter 'ip' or export OPENBENE_SERVER_IP."
            )
            return False

        try:
            from openbene import OpenBene
        except Exception as exc:
            self._openbene_import_error = exc
            self.get_logger().error(
                "Failed to import openbene SDK. Install it first with "
                "'python3 -m pip install -e /path/to/OpenBene/openbene_sdk'."
            )
            self.get_logger().error(f"Import error: {exc}")
            return False

        try:
            self._bot = OpenBene(ip, port)
            self._bot.connect(timeout=15.0)
            self.get_logger().info(f"Connected to OpenBene server at {ip}:{port}")
            return True
        except Exception as exc:
            self._bot = None
            self.get_logger().error(f"Failed to connect to OpenBene server at {ip}:{port}: {exc}")
            return False

    def disconnect(self) -> None:
        """Disconnect cleanly from the OpenBene server."""
        if self._bot is None:
            return
        try:
            self._bot.disconnect()
        except Exception as exc:
            self.get_logger().warning(f"Disconnect raised an exception: {exc}")
        finally:
            self._bot = None

    def _handle_cmd_vel(self, msg: Twist) -> None:
        if not self._dry_run and not self.connected and not self.connect():
            return

        linear = float(msg.linear.x)
        angular = float(msg.angular.z)

        linear_scale = float(self.get_parameter("linear_scale").value)
        angular_scale = float(self.get_parameter("angular_scale").value)

        left, right = twist_to_drive(
            linear,
            angular,
            linear_scale=linear_scale,
            angular_scale=angular_scale,
        )

        if self._dry_run:
            self._last_command_time = self.get_clock().now()
            self._sent_timeout_stop = False
            if self._log_commands:
                self.get_logger().info(
                    f"[dry_run] cmd_vel -> drive({left:.3f}, {right:.3f}) from "
                    f"linear.x={linear:.3f}, angular.z={angular:.3f}"
                )
            return

        try:
            self._bot.drive(left, right)
            self._last_command_time = self.get_clock().now()
            self._sent_timeout_stop = False
            if self._log_commands:
                self.get_logger().info(
                    f"Forwarded cmd_vel as drive({left:.3f}, {right:.3f})"
                )
            else:
                self.get_logger().debug(
                    f"Forwarded cmd_vel as drive({left:.3f}, {right:.3f})"
                )
        except Exception as exc:
            self.get_logger().error(f"Failed to forward cmd_vel: {exc}")

    def _watchdog_tick(self) -> None:
        if not self._dry_run and not self.connected:
            return

        timeout_sec = float(self.get_parameter("command_timeout_sec").value)
        elapsed = (self.get_clock().now() - self._last_command_time).nanoseconds / 1e9

        if elapsed < timeout_sec or self._sent_timeout_stop:
            return

        if self._dry_run:
            self._sent_timeout_stop = True
            if self._log_commands:
                self.get_logger().info("[dry_run] No cmd_vel received recently; simulated stop().")
            return

        try:
            self._bot.stop()
            self._sent_timeout_stop = True
            self.get_logger().debug("No cmd_vel received recently; sent stop().")
        except Exception as exc:
            self.get_logger().warning(f"Failed to send watchdog stop(): {exc}")

    def destroy_node(self) -> bool:
        self.disconnect()
        return super().destroy_node()


def main(args: Optional[list[str]] = None) -> None:
    rclpy.init(args=args)
    node = CmdVelBridge()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()
