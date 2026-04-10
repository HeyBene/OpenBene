from __future__ import annotations

from geometry_msgs.msg import Twist
import rclpy
from rclpy.node import Node


class CmdVelDemoPublisher(Node):
    """Publish a simple repeating cmd_vel sequence for dry-run testing."""

    def __init__(self) -> None:
        super().__init__("openbene_cmd_vel_demo")

        self.declare_parameter("cmd_vel_topic", "/cmd_vel")
        self.declare_parameter("publish_period_sec", 0.25)
        self.declare_parameter("step_duration_sec", 2.0)
        self.declare_parameter("loop", True)

        self._cmd_vel_topic = str(self.get_parameter("cmd_vel_topic").value)
        self._publish_period_sec = float(self.get_parameter("publish_period_sec").value)
        self._step_duration_sec = float(self.get_parameter("step_duration_sec").value)
        self._loop = bool(self.get_parameter("loop").value)

        self._publisher = self.create_publisher(Twist, self._cmd_vel_topic, 10)
        self._timer = self.create_timer(self._publish_period_sec, self._tick)
        self._sequence = [
            ("forward", 0.30, 0.00),
            ("arc_left", 0.25, 0.40),
            ("arc_right", 0.25, -0.40),
            ("stop", 0.00, 0.00),
        ]
        self._step_index = 0
        self._step_started_at = self.get_clock().now()
        self._last_announced_step = -1

        self.get_logger().info(
            f"Publishing demo cmd_vel messages to '{self._cmd_vel_topic}'. Loop={self._loop}."
        )

    def _tick(self) -> None:
        now = self.get_clock().now()
        elapsed = (now - self._step_started_at).nanoseconds / 1e9

        if elapsed >= self._step_duration_sec:
            self._step_index += 1
            self._step_started_at = now

            if self._step_index >= len(self._sequence):
                if self._loop:
                    self._step_index = 0
                else:
                    self._step_index = len(self._sequence) - 1

        label, linear_x, angular_z = self._sequence[self._step_index]

        if self._last_announced_step != self._step_index:
            self._last_announced_step = self._step_index
            self.get_logger().info(
                f"Demo step '{label}': linear.x={linear_x:.2f}, angular.z={angular_z:.2f}"
            )

        msg = Twist()
        msg.linear.x = linear_x
        msg.angular.z = angular_z
        self._publisher.publish(msg)


def main(args: list[str] | None = None) -> None:
    rclpy.init(args=args)
    node = CmdVelDemoPublisher()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()
