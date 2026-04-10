from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from geometry_msgs.msg import Twist
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import LaserScan
from std_msgs.msg import String

from .safety_logic import SafetyConfig
from .safety_logic import apply_linear_safety
from .safety_logic import clamp_abs
from .safety_logic import front_min_range


@dataclass(frozen=True)
class SafetyState:
    front_min_distance_m: float | None
    mode: str
    detail: str


class SafetyCmdVel(Node):
    """Gate user cmd_vel with a simple forward obstacle safety policy."""

    def __init__(self) -> None:
        super().__init__("openbene_safety_cmd_vel")

        self.declare_parameter("input_cmd_vel_topic", "/cmd_vel_user")
        self.declare_parameter("output_cmd_vel_topic", "/cmd_vel_safe")
        self.declare_parameter("scan_topic", "/scan")
        self.declare_parameter("status_topic", "/openbene/safety/status")
        self.declare_parameter("command_timeout_sec", 0.30)
        self.declare_parameter("max_linear_speed_mps", 0.15)
        self.declare_parameter("max_angular_speed_radps", 0.50)
        self.declare_parameter("slowdown_distance_m", 0.35)
        self.declare_parameter("stop_distance_m", 0.20)
        self.declare_parameter("front_sector_half_angle_deg", 30.0)

        self._input_cmd_vel_topic = str(self.get_parameter("input_cmd_vel_topic").value)
        self._output_cmd_vel_topic = str(self.get_parameter("output_cmd_vel_topic").value)
        self._scan_topic = str(self.get_parameter("scan_topic").value)
        self._status_topic = str(self.get_parameter("status_topic").value)
        self._command_timeout_sec = float(self.get_parameter("command_timeout_sec").value)
        self._cfg = SafetyConfig(
            max_linear_speed_mps=float(self.get_parameter("max_linear_speed_mps").value),
            max_angular_speed_radps=float(self.get_parameter("max_angular_speed_radps").value),
            slowdown_distance_m=float(self.get_parameter("slowdown_distance_m").value),
            stop_distance_m=float(self.get_parameter("stop_distance_m").value),
            front_sector_half_angle_deg=float(self.get_parameter("front_sector_half_angle_deg").value),
        )
        self._cfg.validate()
        if self._command_timeout_sec <= 0.0:
            raise ValueError("command_timeout_sec must be positive.")

        self._cmd_pub = self.create_publisher(Twist, self._output_cmd_vel_topic, 10)
        self._status_pub = self.create_publisher(String, self._status_topic, 10)
        self._cmd_sub = self.create_subscription(Twist, self._input_cmd_vel_topic, self._handle_user_cmd, 10)
        self._scan_sub = self.create_subscription(LaserScan, self._scan_topic, self._handle_scan, 10)
        self._timer = self.create_timer(0.05, self._watchdog_tick)

        self._last_user_cmd = Twist()
        self._last_command_time = self.get_clock().now()
        self._last_scan: Optional[LaserScan] = None
        self._timed_out = True
        self._last_published_signature: tuple[float, float, str] | None = None

        self.get_logger().info(
            "Safety layer ready. %s + %s -> %s (timeout=%.2fs, stop=%.2fm, slowdown=%.2fm)"
            % (
                self._input_cmd_vel_topic,
                self._scan_topic,
                self._output_cmd_vel_topic,
                self._command_timeout_sec,
                self._cfg.stop_distance_m,
                self._cfg.slowdown_distance_m,
            )
        )

    def _handle_user_cmd(self, msg: Twist) -> None:
        self._last_user_cmd = msg
        self._last_command_time = self.get_clock().now()
        self._timed_out = False
        self._publish_safe_cmd()

    def _handle_scan(self, msg: LaserScan) -> None:
        self._last_scan = msg
        self._publish_safe_cmd()

    def _watchdog_tick(self) -> None:
        elapsed = (self.get_clock().now() - self._last_command_time).nanoseconds / 1e9
        if elapsed >= self._command_timeout_sec:
            self._timed_out = True
        self._publish_safe_cmd()

    def _current_safety_state(self) -> SafetyState:
        if self._timed_out:
            return SafetyState(front_min_distance_m=None, mode="timeout_stop", detail="command timeout")

        front_min_distance_m: float | None = None
        if self._last_scan is not None:
            front_min_distance_m = front_min_range(
                self._last_scan.ranges,
                angle_min=float(self._last_scan.angle_min),
                angle_increment=float(self._last_scan.angle_increment),
                front_sector_half_angle_deg=self._cfg.front_sector_half_angle_deg,
                range_min=float(self._last_scan.range_min),
                range_max=float(self._last_scan.range_max),
            )

        if front_min_distance_m is not None and front_min_distance_m <= self._cfg.stop_distance_m:
            return SafetyState(
                front_min_distance_m=front_min_distance_m,
                mode="obstacle_stop",
                detail="front obstacle inside stop distance",
            )
        if front_min_distance_m is not None and front_min_distance_m < self._cfg.slowdown_distance_m:
            return SafetyState(
                front_min_distance_m=front_min_distance_m,
                mode="slowdown",
                detail="front obstacle inside slowdown distance",
            )
        return SafetyState(front_min_distance_m=front_min_distance_m, mode="pass", detail="nominal")

    def _publish_safe_cmd(self) -> None:
        state = self._current_safety_state()
        msg = Twist()
        msg.linear.x = apply_linear_safety(
            float(self._last_user_cmd.linear.x),
            front_min_distance_m=state.front_min_distance_m,
            cfg=self._cfg,
        )
        msg.angular.z = clamp_abs(float(self._last_user_cmd.angular.z), self._cfg.max_angular_speed_radps)

        if state.mode == "timeout_stop":
            msg.linear.x = 0.0
            msg.angular.z = 0.0

        self._cmd_pub.publish(msg)

        signature = (round(float(msg.linear.x), 4), round(float(msg.angular.z), 4), state.mode)
        if signature != self._last_published_signature:
            self._last_published_signature = signature
            self.get_logger().info(
                "safe_cmd linear=%.3f angular=%.3f mode=%s front_min=%s"
                % (
                    float(msg.linear.x),
                    float(msg.angular.z),
                    state.mode,
                    "none" if state.front_min_distance_m is None else f"{state.front_min_distance_m:.3f}",
                )
            )

        status = String()
        status.data = (
            f"mode={state.mode}; detail={state.detail}; "
            f"front_min={'none' if state.front_min_distance_m is None else f'{state.front_min_distance_m:.3f}'}; "
            f"linear={float(msg.linear.x):.3f}; angular={float(msg.angular.z):.3f}"
        )
        self._status_pub.publish(status)


def main(args: Optional[list[str]] = None) -> None:
    rclpy.init(args=args)
    node = SafetyCmdVel()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()
