from __future__ import annotations

import asyncio
import json
from queue import Empty
from queue import Queue
import threading
from typing import Optional

from geometry_msgs.msg import TransformStamped
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import CameraInfo
from sensor_msgs.msg import LaserScan
from tf2_ros import TransformBroadcaster

from .capture_protocol import CaptureProtocolProcessor
from .capture_protocol import DepthFrameEvent
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


class LiveCaptureScanServer(Node):
    """Receive OpenBene LiDAR uploads over WebSocket and publish `/scan` in real time."""

    def __init__(self) -> None:
        super().__init__("openbene_live_capture_scan_server")

        self.declare_parameter("host", "0.0.0.0")
        self.declare_parameter("port", 8765)
        self.declare_parameter("output_root_dir", "~/openbene_captured_sessions")
        self.declare_parameter("scan_topic", "/scan")
        self.declare_parameter("camera_info_topic", "/openbene/camera_info")
        self.declare_parameter("frame_id", "openbene_depth_frame")
        self.declare_parameter("band_center_ratio", 0.5)
        self.declare_parameter("band_height", 5)
        self.declare_parameter("range_min_m", 0.15)
        self.declare_parameter("range_max_m", 5.0)
        self.declare_parameter("confidence_min_value", 1)
        self.declare_parameter("accepted_tracking_states", "normal")
        self.declare_parameter("allow_missing_tracking_state", True)
        self.declare_parameter("accepted_depth_sources", "")
        self.declare_parameter("allow_missing_depth_source", True)
        self.declare_parameter("publish_camera_info", True)
        self.declare_parameter("publish_odom_tf", False)
        self.declare_parameter("odom_frame", "odom")
        self.declare_parameter("base_frame", "openbene_base")

        try:
            import cv2
            import numpy
            import websockets
        except Exception as exc:
            self.get_logger().error(
                "Missing runtime dependency for live capture server. Install the local SDK first with "
                "'python3 -m pip install -e /path/to/OpenBene/openbene_sdk'."
            )
            raise RuntimeError("Missing runtime dependency for live capture server.") from exc

        self._cv2 = cv2
        self._numpy = numpy
        self._websockets = websockets

        self._host = str(self.get_parameter("host").value)
        self._port = int(self.get_parameter("port").value)
        self._output_root_dir = str(self.get_parameter("output_root_dir").value)
        self._scan_topic = str(self.get_parameter("scan_topic").value)
        self._camera_info_topic = str(self.get_parameter("camera_info_topic").value)
        self._frame_id = str(self.get_parameter("frame_id").value)
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
        self._publish_camera_info = bool(self.get_parameter("publish_camera_info").value)
        self._publish_odom_tf = bool(self.get_parameter("publish_odom_tf").value)
        self._odom_frame = str(self.get_parameter("odom_frame").value)
        self._base_frame = str(self.get_parameter("base_frame").value)

        self._scan_publisher = self.create_publisher(LaserScan, self._scan_topic, 10)
        self._camera_info_publisher = self.create_publisher(CameraInfo, self._camera_info_topic, 10)
        self._tf_broadcaster = TransformBroadcaster(self) if self._publish_odom_tf else None

        self._event_queue: Queue[tuple[str, object]] = Queue()
        self._server_loop: asyncio.AbstractEventLoop | None = None
        self._stop_future: asyncio.Future | None = None
        self._server_thread = threading.Thread(target=self._server_thread_main, daemon=True)
        self._server_thread.start()
        self._queue_timer = self.create_timer(0.05, self._drain_event_queue)
        self._published_scan_count = 0
        self._skipped_tracking_state_count = 0
        self._skipped_depth_source_count = 0

    def destroy_node(self) -> bool:
        if self._server_loop is not None and self._stop_future is not None:
            self._server_loop.call_soon_threadsafe(self._request_server_shutdown)
        if self._server_thread.is_alive():
            self._server_thread.join(timeout=2.0)
        return super().destroy_node()

    def _server_thread_main(self) -> None:
        async def _run_server_forever() -> None:
            self._server_loop = asyncio.get_running_loop()
            self._stop_future = self._server_loop.create_future()

            async with self._websockets.serve(self._handle_connection, self._host, self._port):
                self._event_queue.put(
                    (
                        "log",
                        (
                            "info",
                            f"Live capture server listening on ws://{self._host}:{self._port} and writing sessions under {self._output_root_dir}",
                        ),
                    )
                )
                await self._stop_future

        try:
            asyncio.run(_run_server_forever())
        finally:
            self._server_loop = None
            self._stop_future = None

    def _request_server_shutdown(self) -> None:
        if self._stop_future is not None and not self._stop_future.done():
            self._stop_future.set_result(None)

    async def _handle_connection(self, websocket) -> None:
        remote = websocket.remote_address
        remote_label = f"{remote[0]}:{remote[1]}" if remote else "unknown"
        self._event_queue.put(("log", ("info", f"iPhone device connected from {remote_label}.")))

        processor = CaptureProtocolProcessor(
            self._output_root_dir,
            on_depth_frame=self._enqueue_depth_frame,
        )
        await websocket.send(json.dumps(processor.handshake_payload()))

        try:
            async for message in websocket:
                try:
                    if isinstance(message, str):
                        responses = processor.handle_text_message(message)
                    else:
                        responses = processor.handle_binary_message(message)
                except Exception as exc:
                    self._event_queue.put(("log", ("error", f"Capture protocol error: {exc}")))
                    await websocket.send(json.dumps({"status": "error", "detail": str(exc)}))
                    continue

                for response in responses:
                    await websocket.send(json.dumps(response))
        except self._websockets.exceptions.ConnectionClosed:
            self._event_queue.put(("log", ("info", f"Connection closed for {remote_label}.")))
        finally:
            try:
                processor.finalize_if_needed()
            except Exception as exc:
                self._event_queue.put(("log", ("warning", f"Failed to finalize capture session: {exc}")))

    def _enqueue_depth_frame(self, event: DepthFrameEvent) -> None:
        self._event_queue.put(("depth_frame", event))

    def _drain_event_queue(self) -> None:
        while True:
            try:
                event_type, payload = self._event_queue.get_nowait()
            except Empty:
                return

            if event_type == "log":
                level, message = payload  # type: ignore[misc]
                logger = self.get_logger()
                if level == "error":
                    logger.error(str(message))
                elif level == "warning":
                    logger.warning(str(message))
                else:
                    logger.info(str(message))
                continue

            if event_type == "depth_frame":
                self._publish_depth_frame(payload)  # type: ignore[arg-type]

    def _publish_depth_frame(self, event: DepthFrameEvent) -> None:
        if not self._is_tracking_state_accepted(event.tracking_state):
            self._skipped_tracking_state_count += 1
            if self._skipped_tracking_state_count == 1 or self._skipped_tracking_state_count % 20 == 0:
                self.get_logger().info(
                    "Skipped %d frame(s) due to tracking_state filter. latest='%s'"
                    % (self._skipped_tracking_state_count, str(event.tracking_state))
                )
            return

        if not self._is_depth_source_accepted(event.depth_source):
            self._skipped_depth_source_count += 1
            if self._skipped_depth_source_count == 1 or self._skipped_depth_source_count % 20 == 0:
                self.get_logger().info(
                    "Skipped %d frame(s) due to depth_source filter. latest='%s'"
                    % (self._skipped_depth_source_count, str(event.depth_source))
                )
            return

        encoded = self._numpy.frombuffer(event.depth_png_bytes, dtype=self._numpy.uint8)
        depth_image = self._cv2.imdecode(encoded, self._cv2.IMREAD_UNCHANGED)
        if depth_image is None:
            self.get_logger().warning(
                f"Failed to decode depth PNG for frame {event.index} in session {event.session_name}."
            )
            return

        if len(depth_image.shape) != 2:
            self.get_logger().warning(
                f"Depth frame {event.index} in session {event.session_name} is not single-channel."
            )
            return

        depth_height = int(depth_image.shape[0])
        depth_width = int(depth_image.shape[1])
        camera_model = CameraModel(
            width=event.width,
            height=event.height,
            fl_x=event.fl_x,
            fl_y=event.fl_y,
            cx=event.cx,
            cy=event.cy,
        )
        scaled_camera = scale_camera_model(
            camera_model,
            target_width=depth_width,
            target_height=depth_height,
        )

        confidence_image = None
        if event.confidence_png_bytes is not None:
            confidence_encoded = self._numpy.frombuffer(event.confidence_png_bytes, dtype=self._numpy.uint8)
            confidence_image = self._cv2.imdecode(confidence_encoded, self._cv2.IMREAD_UNCHANGED)
            if confidence_image is None:
                self.get_logger().warning(
                    f"Failed to decode confidence PNG for frame {event.index} in session {event.session_name}."
                )

        projection = project_depth_image_to_laserscan(
            depth_image,
            scaled_camera,
            depth_scale=event.depth_scale,
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
        scan_msg.scan_time = 0.0
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
            self._publish_odom_transform(event, stamp)

        self._published_scan_count += 1
        if self._published_scan_count == 1:
            self.get_logger().info(
                f"Published first live scan from session '{event.session_name}' frame {event.index}."
            )

    def _publish_odom_transform(self, event: DepthFrameEvent, stamp) -> None:
        planar_pose = planar_pose_from_opengl_camera_transform(event.transform_matrix)
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
    node = LiveCaptureScanServer()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()
