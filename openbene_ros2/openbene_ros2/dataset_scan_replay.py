from __future__ import annotations

from pathlib import Path
from typing import Optional

from geometry_msgs.msg import TransformStamped
from rclpy.node import Node
import rclpy
from sensor_msgs.msg import CameraInfo
from sensor_msgs.msg import LaserScan
from tf2_ros import TransformBroadcaster

from .capture_manifest import load_capture_manifest
from .depth_scan import CameraModel
from .depth_scan import project_depth_image_to_laserscan
from .depth_scan import scale_camera_model
from .planar_pose import planar_pose_from_opengl_camera_transform
from .planar_pose import quaternion_from_yaw


def _normalize_tracking_state(raw_state: str | None) -> str | None:
    if raw_state is None:
        return None
    normalized = raw_state.strip().lower()
    return normalized or None


def _parse_tracking_state_filter(raw_value: str) -> set[str]:
    return {state.strip().lower() for state in raw_value.split(",") if state.strip()}


def _normalize_depth_source(raw_source: str | None) -> str | None:
    if raw_source is None:
        return None
    normalized = raw_source.strip().lower()
    return normalized or None


def _parse_depth_source_filter(raw_value: str) -> set[str]:
    return {source.strip().lower() for source in raw_value.split(",") if source.strip()}


def select_replay_frames(frames, *, frame_start: int, frame_count: int, tail_frames: int):
    if tail_frames < 0:
        raise ValueError("tail_frames must be >= 0.")
    if frame_start < 0:
        raise ValueError("frame_start must be >= 0.")
    if frame_count < 0:
        raise ValueError("frame_count must be >= 0.")
    if not frames:
        return [], 0

    if tail_frames > 0:
        effective_start = max(0, len(frames) - tail_frames)
        selected = frames[effective_start:]
    else:
        effective_start = frame_start
        selected = frames[frame_start:]
        if frame_count > 0:
            selected = selected[:frame_count]

    if not selected:
        raise ValueError("Replay frame selection produced an empty window.")
    return selected, effective_start


class DatasetScanReplay(Node):
    """Replay an OpenBene LiDAR capture dataset as a ROS 2 `/scan` topic."""

    def __init__(self) -> None:
        super().__init__("openbene_dataset_scan_replay")

        self.declare_parameter("dataset_dir", "")
        self.declare_parameter("scan_topic", "/scan")
        self.declare_parameter("camera_info_topic", "/openbene/camera_info")
        self.declare_parameter("frame_id", "openbene_depth_frame")
        self.declare_parameter("publish_period_sec", 0.2)
        self.declare_parameter("band_center_ratio", 0.5)
        self.declare_parameter("band_height", 5)
        self.declare_parameter("range_min_m", 0.15)
        self.declare_parameter("range_max_m", 5.0)
        self.declare_parameter("confidence_min_value", 1)
        self.declare_parameter("accepted_tracking_states", "normal")
        self.declare_parameter("allow_missing_tracking_state", True)
        self.declare_parameter("accepted_depth_sources", "")
        self.declare_parameter("allow_missing_depth_source", True)
        self.declare_parameter("repeat", True)
        self.declare_parameter("publish_camera_info", True)
        self.declare_parameter("publish_odom_tf", False)
        self.declare_parameter("odom_frame", "odom")
        self.declare_parameter("base_frame", "openbene_base")
        self.declare_parameter("frame_start", 0)
        self.declare_parameter("frame_count", 0)
        self.declare_parameter("tail_frames", 0)

        dataset_dir = str(self.get_parameter("dataset_dir").value).strip()
        if not dataset_dir:
            raise ValueError("Parameter 'dataset_dir' must point to an OpenBene capture session.")

        try:
            import cv2
        except Exception as exc:
            self.get_logger().error(
                "Failed to import cv2. Install the local SDK first with "
                "'python3 -m pip install -e /path/to/OpenBene/openbene_sdk'."
            )
            raise RuntimeError("Missing runtime dependency: cv2") from exc

        self._cv2 = cv2
        self._manifest = load_capture_manifest(Path(dataset_dir))
        self._camera_model = CameraModel(
            width=self._manifest.width,
            height=self._manifest.height,
            fl_x=self._manifest.fl_x,
            fl_y=self._manifest.fl_y,
            cx=self._manifest.cx,
            cy=self._manifest.cy,
        )

        depth_frames = [
            frame for frame in self._manifest.depth_frames if frame.depth_path and frame.depth_path.exists()
        ]
        if not depth_frames:
            raise ValueError(
                f"Dataset '{self._manifest.dataset_dir}' does not contain any existing depth PNG frames."
            )
        self._depth_frames, self._effective_frame_start = select_replay_frames(
            depth_frames,
            frame_start=int(self.get_parameter("frame_start").value),
            frame_count=int(self.get_parameter("frame_count").value),
            tail_frames=int(self.get_parameter("tail_frames").value),
        )

        self._scan_topic = str(self.get_parameter("scan_topic").value)
        self._camera_info_topic = str(self.get_parameter("camera_info_topic").value)
        self._frame_id = str(self.get_parameter("frame_id").value)
        self._publish_period_sec = float(self.get_parameter("publish_period_sec").value)
        self._band_center_ratio = float(self.get_parameter("band_center_ratio").value)
        self._band_height = int(self.get_parameter("band_height").value)
        self._range_min_m = float(self.get_parameter("range_min_m").value)
        self._range_max_m = float(self.get_parameter("range_max_m").value)
        self._confidence_min_value = int(self.get_parameter("confidence_min_value").value)
        self._accepted_tracking_states = _parse_tracking_state_filter(
            str(self.get_parameter("accepted_tracking_states").value)
        )
        self._allow_missing_tracking_state = bool(self.get_parameter("allow_missing_tracking_state").value)
        self._accepted_depth_sources = _parse_depth_source_filter(
            str(self.get_parameter("accepted_depth_sources").value)
        )
        self._allow_missing_depth_source = bool(self.get_parameter("allow_missing_depth_source").value)
        self._repeat = bool(self.get_parameter("repeat").value)
        self._publish_camera_info = bool(self.get_parameter("publish_camera_info").value)
        self._publish_odom_tf = bool(self.get_parameter("publish_odom_tf").value)
        self._odom_frame = str(self.get_parameter("odom_frame").value)
        self._base_frame = str(self.get_parameter("base_frame").value)

        self._scan_publisher = self.create_publisher(LaserScan, self._scan_topic, 10)
        self._camera_info_publisher = self.create_publisher(CameraInfo, self._camera_info_topic, 10)
        self._tf_broadcaster = TransformBroadcaster(self) if self._publish_odom_tf else None

        self._frame_cursor = 0
        self._published_count = 0
        self._skipped_tracking_state_count = 0
        self._skipped_depth_source_count = 0
        self._timer = self.create_timer(self._publish_period_sec, self._tick)

        self.get_logger().info(
            "Loaded dataset '%s' with %d depth frame(s) starting at frame index %d. Publishing LaserScan on '%s'."
            % (self._manifest.dataset_dir, len(self._depth_frames), self._effective_frame_start, self._scan_topic)
        )

    def _tick(self) -> None:
        frame = self._depth_frames[self._frame_cursor]
        assert frame.depth_path is not None

        if not self._is_tracking_state_accepted(frame.tracking_state):
            self._skipped_tracking_state_count += 1
            if self._skipped_tracking_state_count == 1 or self._skipped_tracking_state_count % 20 == 0:
                self.get_logger().info(
                    "Skipped %d frame(s) due to tracking_state filter. latest='%s'"
                    % (self._skipped_tracking_state_count, str(frame.tracking_state))
                )
            self._advance_frame()
            return

        if not self._is_depth_source_accepted(frame.depth_source):
            self._skipped_depth_source_count += 1
            if self._skipped_depth_source_count == 1 or self._skipped_depth_source_count % 20 == 0:
                self.get_logger().info(
                    "Skipped %d frame(s) due to depth_source filter. latest='%s'"
                    % (self._skipped_depth_source_count, str(frame.depth_source))
                )
            self._advance_frame()
            return

        depth_image = self._cv2.imread(str(frame.depth_path), self._cv2.IMREAD_UNCHANGED)
        if depth_image is None:
            self.get_logger().warning(f"Failed to read depth image: {frame.depth_path}")
            self._advance_frame()
            return

        if len(depth_image.shape) != 2:
            self.get_logger().warning(
                f"Depth image must be single-channel. Got shape {depth_image.shape} at {frame.depth_path}"
            )
            self._advance_frame()
            return

        depth_height, depth_width = int(depth_image.shape[0]), int(depth_image.shape[1])
        scaled_camera = scale_camera_model(
            self._camera_model,
            target_width=depth_width,
            target_height=depth_height,
        )

        confidence_image = None
        if frame.confidence_path is not None and frame.confidence_path.exists():
            confidence_image = self._cv2.imread(str(frame.confidence_path), self._cv2.IMREAD_UNCHANGED)
            if confidence_image is None:
                self.get_logger().warning(f"Failed to read confidence image: {frame.confidence_path}")

        projection = project_depth_image_to_laserscan(
            depth_image,
            scaled_camera,
            depth_scale=self._manifest.depth_scale,
            confidence_image=confidence_image,
            confidence_min_value=self._confidence_min_value,
            band_center_ratio=self._band_center_ratio,
            band_height=self._band_height,
            range_min_m=self._range_min_m,
            range_max_m=self._range_max_m,
        )

        stamp = self.get_clock().now().to_msg()
        scan_msg = LaserScan()
        scan_msg.header.stamp = stamp
        scan_msg.header.frame_id = self._frame_id
        scan_msg.angle_min = projection.angle_min
        scan_msg.angle_max = projection.angle_max
        scan_msg.angle_increment = projection.angle_increment
        scan_msg.time_increment = 0.0
        scan_msg.scan_time = self._publish_period_sec
        scan_msg.range_min = self._range_min_m
        scan_msg.range_max = self._range_max_m
        scan_msg.ranges = list(projection.ranges)
        self._scan_publisher.publish(scan_msg)

        if self._publish_camera_info:
            camera_info_msg = CameraInfo()
            camera_info_msg.header.stamp = stamp
            camera_info_msg.header.frame_id = self._frame_id
            camera_info_msg.width = depth_width
            camera_info_msg.height = depth_height
            camera_info_msg.distortion_model = "plumb_bob"
            camera_info_msg.k = [
                scaled_camera.fl_x,
                0.0,
                scaled_camera.cx,
                0.0,
                scaled_camera.fl_y,
                scaled_camera.cy,
                0.0,
                0.0,
                1.0,
            ]
            camera_info_msg.p = [
                scaled_camera.fl_x,
                0.0,
                scaled_camera.cx,
                0.0,
                0.0,
                scaled_camera.fl_y,
                scaled_camera.cy,
                0.0,
                0.0,
                0.0,
                1.0,
                0.0,
            ]
            self._camera_info_publisher.publish(camera_info_msg)

        if self._tf_broadcaster is not None:
            self._publish_odom_transform(frame, stamp)

        self._published_count += 1
        if self._published_count == 1:
            self.get_logger().info(
                f"Published first scan frame from {frame.depth_path.name} with {len(projection.ranges)} range bins."
            )

        self._advance_frame()

    def _advance_frame(self) -> None:
        self._frame_cursor += 1
        if self._frame_cursor < len(self._depth_frames):
            return

        if self._repeat:
            self._frame_cursor = 0
            self.get_logger().info("Reached end of dataset; replaying from the beginning.")
            return

        self.get_logger().info("Reached end of dataset; stopping replay timer.")
        self._timer.cancel()

    def _publish_odom_transform(self, frame, stamp) -> None:
        planar_pose = planar_pose_from_opengl_camera_transform(frame.transform_matrix)
        qx, qy, qz, qw = quaternion_from_yaw(planar_pose.yaw)

        tf_msg = TransformStamped()
        tf_msg.header.stamp = stamp
        tf_msg.header.frame_id = self._odom_frame
        tf_msg.child_frame_id = self._base_frame
        tf_msg.transform.translation.x = planar_pose.x
        tf_msg.transform.translation.y = planar_pose.y
        tf_msg.transform.translation.z = 0.0
        tf_msg.transform.rotation.x = qx
        tf_msg.transform.rotation.y = qy
        tf_msg.transform.rotation.z = qz
        tf_msg.transform.rotation.w = qw
        self._tf_broadcaster.sendTransform(tf_msg)

    def _is_tracking_state_accepted(self, tracking_state: str | None) -> bool:
        normalized = _normalize_tracking_state(tracking_state)
        if normalized is None:
            return self._allow_missing_tracking_state
        if not self._accepted_tracking_states:
            return True
        return normalized in self._accepted_tracking_states

    def _is_depth_source_accepted(self, depth_source: str | None) -> bool:
        normalized = _normalize_depth_source(depth_source)
        if normalized is None:
            return self._allow_missing_depth_source
        if not self._accepted_depth_sources:
            return True
        return normalized in self._accepted_depth_sources


def main(args: Optional[list[str]] = None) -> None:
    rclpy.init(args=args)
    node = DatasetScanReplay()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()
