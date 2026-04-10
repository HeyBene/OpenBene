from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, Sequence


def build_planar_covariance(
    *,
    xy_stddev: float,
    yaw_stddev: float,
    z_stddev: float = 0.0,
    roll_pitch_stddev: float = 0.0,
) -> list[float]:
    covariance = [0.0] * 36
    covariance[0] = float(xy_stddev) ** 2
    covariance[7] = float(xy_stddev) ** 2
    covariance[14] = float(z_stddev) ** 2
    covariance[21] = float(roll_pitch_stddev) ** 2
    covariance[28] = float(roll_pitch_stddev) ** 2
    covariance[35] = float(yaw_stddev) ** 2
    return covariance


@dataclass(frozen=True)
class SimplePose:
    frame_id: str
    position: tuple[float, float, float]
    orientation: tuple[float, float, float, float]


def normalize_simple_pose(
    *,
    frame_id: str,
    position: Sequence[float],
    orientation: Sequence[float],
    force_zero_z: bool,
) -> SimplePose:
    if len(position) != 3:
        raise ValueError("position must contain exactly 3 values.")
    if len(orientation) != 4:
        raise ValueError("orientation must contain exactly 4 values.")

    z_value = 0.0 if force_zero_z else float(position[2])
    return SimplePose(
        frame_id=str(frame_id),
        position=(float(position[0]), float(position[1]), z_value),
        orientation=(
            float(orientation[0]),
            float(orientation[1]),
            float(orientation[2]),
            float(orientation[3]),
        ),
    )


def main(args: Optional[list[str]] = None) -> None:
    import rclpy
    from rclpy.executors import ExternalShutdownException
    from geometry_msgs.msg import PoseStamped, PoseWithCovarianceStamped
    from rclpy.node import Node
    from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy

    class RelocalizationInitialPoseBridge(Node):
        def __init__(self) -> None:
            super().__init__("openbene_relocalization_initialpose_bridge")

            self.declare_parameter("source_pose_topic", "/openbene/relocalization/refined_initial_pose")
            self.declare_parameter("initialpose_topic", "/initialpose")
            self.declare_parameter("target_frame", "")
            self.declare_parameter("xy_stddev", 0.15)
            self.declare_parameter("yaw_stddev", 0.25)
            self.declare_parameter("z_stddev", 0.0)
            self.declare_parameter("roll_pitch_stddev", 0.0)
            self.declare_parameter("force_zero_z", True)
            self.declare_parameter("use_zero_stamp", True)
            self.declare_parameter("repeat_count", 3)
            self.declare_parameter("repeat_interval_sec", 0.35)

            self._source_pose_topic = str(self.get_parameter("source_pose_topic").value)
            self._initialpose_topic = str(self.get_parameter("initialpose_topic").value)
            self._target_frame = str(self.get_parameter("target_frame").value).strip()
            self._force_zero_z = bool(self.get_parameter("force_zero_z").value)
            self._use_zero_stamp = bool(self.get_parameter("use_zero_stamp").value)
            self._repeat_count = max(1, int(self.get_parameter("repeat_count").value))
            self._repeat_interval_sec = max(0.05, float(self.get_parameter("repeat_interval_sec").value))
            self._covariance = build_planar_covariance(
                xy_stddev=float(self.get_parameter("xy_stddev").value),
                yaw_stddev=float(self.get_parameter("yaw_stddev").value),
                z_stddev=float(self.get_parameter("z_stddev").value),
                roll_pitch_stddev=float(self.get_parameter("roll_pitch_stddev").value),
            )

            self._pending_pose: Optional[SimplePose] = None
            self._remaining_repeats = 0
            self._last_signature: Optional[tuple[str, tuple[float, float, float], tuple[float, float, float, float]]] = None

            pose_qos = QoSProfile(
                history=HistoryPolicy.KEEP_LAST,
                depth=1,
                reliability=ReliabilityPolicy.RELIABLE,
                durability=DurabilityPolicy.TRANSIENT_LOCAL,
            )
            self._publisher = self.create_publisher(PoseWithCovarianceStamped, self._initialpose_topic, 10)
            self._subscription = self.create_subscription(
                PoseStamped,
                self._source_pose_topic,
                self._on_pose,
                pose_qos,
            )
            self._repeat_timer = self.create_timer(self._repeat_interval_sec, self._on_repeat_timer)
            self._repeat_timer.cancel()

            self.get_logger().info(
                "Initial pose bridge ready. Waiting for PoseStamped on '%s' and publishing PoseWithCovarianceStamped on '%s'."
                % (self._source_pose_topic, self._initialpose_topic)
            )

        def _publish_initial_pose(self, pose: SimplePose) -> None:
            msg = PoseWithCovarianceStamped()
            if self._use_zero_stamp:
                msg.header.stamp.sec = 0
                msg.header.stamp.nanosec = 0
            else:
                msg.header.stamp = self.get_clock().now().to_msg()
            msg.header.frame_id = self._target_frame or pose.frame_id
            msg.pose.pose.position.x = pose.position[0]
            msg.pose.pose.position.y = pose.position[1]
            msg.pose.pose.position.z = pose.position[2]
            msg.pose.pose.orientation.x = pose.orientation[0]
            msg.pose.pose.orientation.y = pose.orientation[1]
            msg.pose.pose.orientation.z = pose.orientation[2]
            msg.pose.pose.orientation.w = pose.orientation[3]
            msg.pose.covariance = self._covariance
            self._publisher.publish(msg)

        def _on_pose(self, msg: PoseStamped) -> None:
            pose = normalize_simple_pose(
                frame_id=self._target_frame or msg.header.frame_id,
                position=(msg.pose.position.x, msg.pose.position.y, msg.pose.position.z),
                orientation=(
                    msg.pose.orientation.x,
                    msg.pose.orientation.y,
                    msg.pose.orientation.z,
                    msg.pose.orientation.w,
                ),
                force_zero_z=self._force_zero_z,
            )
            signature = (pose.frame_id, pose.position, pose.orientation)
            if signature == self._last_signature:
                return

            self._last_signature = signature
            self._pending_pose = pose
            self._remaining_repeats = self._repeat_count - 1
            self._publish_initial_pose(pose)

            if self._remaining_repeats > 0:
                self._repeat_timer.reset()

            self.get_logger().info(
                "Published /initialpose seed in frame '%s' at x=%.3f y=%.3f z=%.3f using %s timestamp mode."
                % (
                    pose.frame_id,
                    pose.position[0],
                    pose.position[1],
                    pose.position[2],
                    "zero" if self._use_zero_stamp else "current",
                )
            )

        def _on_repeat_timer(self) -> None:
            if self._pending_pose is None or self._remaining_repeats <= 0:
                self._repeat_timer.cancel()
                return

            self._publish_initial_pose(self._pending_pose)
            self._remaining_repeats -= 1
            if self._remaining_repeats <= 0:
                self._repeat_timer.cancel()

    rclpy.init(args=args)
    node = RelocalizationInitialPoseBridge()
    try:
        rclpy.spin(node)
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()
