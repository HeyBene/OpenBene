from __future__ import annotations

import json
import os
from pathlib import Path
import re
from typing import Optional, Sequence

from ._sdk_bridge import SDK_INSTALL_HINT
from .capture_manifest import load_capture_manifest
from .planar_pose import planar_pose_from_opengl_camera_transform
from .planar_pose import quaternion_from_yaw


WINDOWS_DRIVE_PATH = re.compile(r"^[A-Za-z]:[\\/]")
RUNNING_ON_WINDOWS = os.name == "nt"


def resolve_local_path(path_value: str | Path) -> Path:
    raw_path = str(path_value).strip()
    if not raw_path:
        raise ValueError("path_value must not be empty.")

    if not RUNNING_ON_WINDOWS and WINDOWS_DRIVE_PATH.match(raw_path):
        drive_letter = raw_path[0].lower()
        suffix = raw_path[2:].replace("\\", "/")
        return Path(f"/mnt/{drive_letter}{suffix}").expanduser().resolve()

    return Path(raw_path).expanduser().resolve()


def rotation_matrix_to_quaternion(rotation: Sequence[Sequence[float]]) -> tuple[float, float, float, float]:
    trace = rotation[0][0] + rotation[1][1] + rotation[2][2]
    if trace > 0.0:
        s = (trace + 1.0) ** 0.5 * 2.0
        qw = 0.25 * s
        qx = (rotation[2][1] - rotation[1][2]) / s
        qy = (rotation[0][2] - rotation[2][0]) / s
        qz = (rotation[1][0] - rotation[0][1]) / s
    elif rotation[0][0] > rotation[1][1] and rotation[0][0] > rotation[2][2]:
        s = (1.0 + rotation[0][0] - rotation[1][1] - rotation[2][2]) ** 0.5 * 2.0
        qw = (rotation[2][1] - rotation[1][2]) / s
        qx = 0.25 * s
        qy = (rotation[0][1] + rotation[1][0]) / s
        qz = (rotation[0][2] + rotation[2][0]) / s
    elif rotation[1][1] > rotation[2][2]:
        s = (1.0 + rotation[1][1] - rotation[0][0] - rotation[2][2]) ** 0.5 * 2.0
        qw = (rotation[0][2] - rotation[2][0]) / s
        qx = (rotation[0][1] + rotation[1][0]) / s
        qy = 0.25 * s
        qz = (rotation[1][2] + rotation[2][1]) / s
    else:
        s = (1.0 + rotation[2][2] - rotation[0][0] - rotation[1][1]) ** 0.5 * 2.0
        qw = (rotation[1][0] - rotation[0][1]) / s
        qx = (rotation[0][2] + rotation[2][0]) / s
        qy = (rotation[1][2] + rotation[2][1]) / s
        qz = 0.25 * s
    return qx, qy, qz, qw


def transform_to_translation_quaternion(
    transform_matrix: Sequence[Sequence[float]],
) -> tuple[tuple[float, float, float], tuple[float, float, float, float]]:
    if len(transform_matrix) != 4 or any(len(row) != 4 for row in transform_matrix):
        raise ValueError("transform_matrix must be a 4x4 matrix.")

    rotation = [[float(transform_matrix[i][j]) for j in range(3)] for i in range(3)]
    translation = (
        float(transform_matrix[0][3]),
        float(transform_matrix[1][3]),
        float(transform_matrix[2][3]),
    )
    quaternion = rotation_matrix_to_quaternion(rotation)
    return translation, quaternion


def compose_transform_matrices(
    lhs: Sequence[Sequence[float]],
    rhs: Sequence[Sequence[float]],
) -> tuple[tuple[float, float, float, float], ...]:
    if len(lhs) != 4 or any(len(row) != 4 for row in lhs):
        raise ValueError("lhs must be a 4x4 matrix.")
    if len(rhs) != 4 or any(len(row) != 4 for row in rhs):
        raise ValueError("rhs must be a 4x4 matrix.")

    return tuple(
        tuple(sum(float(lhs[i][k]) * float(rhs[k][j]) for k in range(4)) for j in range(4))
        for i in range(4)
    )


def relocalization_transform_to_initial_pose(
    transform_matrix: Sequence[Sequence[float]],
    session_dir: str | Path,
    *,
    frame_index: int = 0,
) -> tuple[tuple[float, float, float], tuple[float, float, float, float]]:
    manifest = load_capture_manifest(session_dir)
    seed_frames = manifest.depth_frames or manifest.frames
    if not seed_frames:
        raise ValueError(f"Dataset '{manifest.dataset_dir}' does not contain any frames.")
    if frame_index < 0 or frame_index >= len(seed_frames):
        raise IndexError(
            f"frame_index={frame_index} is out of range for dataset '{manifest.dataset_dir}' "
            f"with {len(seed_frames)} usable frame(s)."
        )

    combined_transform = compose_transform_matrices(transform_matrix, seed_frames[frame_index].transform_matrix)
    planar_pose = planar_pose_from_opengl_camera_transform(combined_transform)
    quaternion = quaternion_from_yaw(planar_pose.yaw)
    return (planar_pose.x, planar_pose.y, 0.0), quaternion


def classify_relocalization_state(
    fitness: float,
    rmse: float,
    *,
    success_fitness_threshold: float,
    success_rmse_threshold: float,
    warning_fitness_threshold: float,
    warning_rmse_threshold: float,
) -> str:
    if fitness >= success_fitness_threshold and rmse <= success_rmse_threshold:
        return "success"
    if fitness >= warning_fitness_threshold and rmse <= warning_rmse_threshold:
        return "warning"
    return "failed"


def _normalize_transform_matrix(
    transform_matrix: Sequence[Sequence[float]],
    *,
    field_name: str,
) -> tuple[tuple[float, float, float, float], ...]:
    if len(transform_matrix) != 4 or any(len(row) != 4 for row in transform_matrix):
        raise ValueError(f"Field '{field_name}' must be a 4x4 matrix.")
    return tuple(tuple(float(value) for value in row) for row in transform_matrix)


def load_relocalization_report(report_path: str | Path) -> dict[str, object]:
    report_file = resolve_local_path(report_path)
    if not report_file.exists():
        raise FileNotFoundError(f"Relocalization report not found: {report_file}")

    payload = json.loads(report_file.read_text(encoding="utf-8"))
    required_fields = [
        "session_dir",
        "map_pointcloud",
        "global_fitness",
        "global_rmse",
        "icp_fitness",
        "icp_rmse",
        "fine_icp_fitness",
        "fine_icp_rmse",
        "global_transformation",
        "transformation",
    ]
    missing_fields = [field for field in required_fields if field not in payload]
    if missing_fields:
        raise ValueError(
            "Relocalization report is missing required field(s): "
            + ", ".join(sorted(missing_fields))
        )

    return {
        "session_dir": str(resolve_local_path(payload["session_dir"])),
        "map_pointcloud": str(resolve_local_path(payload["map_pointcloud"])),
        "target_submap_mode": str(payload.get("target_submap_mode", "full_map")),
        "target_submap_radius": float(payload.get("target_submap_radius", 0.0)),
        "target_submap_step": float(payload.get("target_submap_step", 0.0)),
        "target_submap_candidate_count": int(payload.get("target_submap_candidate_count", 0)),
        "target_submap_selected_index": int(payload.get("target_submap_selected_index", -1)),
        "target_submap_center": tuple(float(value) for value in payload.get("target_submap_center", [0.0, 0.0, 0.0])),
        "target_retrieval_method": str(payload.get("target_retrieval_method", "none")),
        "target_retrieval_top_k": int(payload.get("target_retrieval_top_k", 0)),
        "target_retrieval_selected_rank": int(payload.get("target_retrieval_selected_rank", -1)),
        "target_retrieval_score": float(payload.get("target_retrieval_score", 0.0)),
        "target_prior_method": str(payload.get("target_prior_method", "none")),
        "target_prior_center": tuple(float(value) for value in payload.get("target_prior_center", [0.0, 0.0, 0.0])),
        "target_prior_radius": float(payload.get("target_prior_radius", 0.0)),
        "target_prior_weight": float(payload.get("target_prior_weight", 0.0)),
        "target_prior_selected_distance": float(payload.get("target_prior_selected_distance", -1.0)),
        "global_method": str(payload.get("global_method", "unknown")),
        "global_fitness": float(payload["global_fitness"]),
        "global_rmse": float(payload["global_rmse"]),
        "global_support_method": str(payload.get("global_support_method", "unknown")),
        "global_support_score": float(payload.get("global_support_score", 0.0)),
        "coarse_init_method": str(payload.get("coarse_init_method", "unknown")),
        "coarse_fitness": float(payload.get("coarse_fitness", 0.0)),
        "coarse_rmse": float(payload.get("coarse_rmse", 0.0)),
        "icp_fitness": float(payload["icp_fitness"]),
        "icp_rmse": float(payload["icp_rmse"]),
        "fine_icp_fitness": float(payload["fine_icp_fitness"]),
        "fine_icp_rmse": float(payload["fine_icp_rmse"]),
        "global_transformation": _normalize_transform_matrix(
            payload["global_transformation"],
            field_name="global_transformation",
        ),
        "transformation": _normalize_transform_matrix(
            payload["transformation"],
            field_name="transformation",
        ),
        "report_path": str(report_file),
        "source": "precomputed_report",
        "source_frame_start": int(payload.get("source_frame_start", 0)),
        "source_frame_count": int(payload.get("source_frame_count", 0)),
        "source_tail_frames": int(payload.get("source_tail_frames", 0)),
        "source_effective_frame_start": int(payload.get("source_effective_frame_start", 0)),
        "source_effective_frame_count": int(payload.get("source_effective_frame_count", 0)),
    }


def main(args: Optional[list[str]] = None) -> None:
    import rclpy
    from geometry_msgs.msg import PoseStamped
    from rclpy.node import Node
    from rclpy.qos import DurabilityPolicy, HistoryPolicy, QoSProfile, ReliabilityPolicy
    from std_msgs.msg import Float32, String

    def make_pose_msg_from_transform(transform_matrix, *, stamp, frame_id: str) -> PoseStamped:
        translation, quaternion = transform_to_translation_quaternion(transform_matrix)
        return make_pose_msg_from_components(
            translation,
            quaternion,
            stamp=stamp,
            frame_id=frame_id,
        )

    def make_pose_msg_from_components(position, orientation, *, stamp, frame_id: str) -> PoseStamped:
        msg = PoseStamped()
        msg.header.stamp = stamp
        msg.header.frame_id = frame_id
        msg.pose.position.x = float(position[0])
        msg.pose.position.y = float(position[1])
        msg.pose.position.z = float(position[2])
        msg.pose.orientation.x = float(orientation[0])
        msg.pose.orientation.y = float(orientation[1])
        msg.pose.orientation.z = float(orientation[2])
        msg.pose.orientation.w = float(orientation[3])
        return msg

    class DatasetRelocalization(Node):
        """Run one-shot session relocalization and publish the result as ROS 2 topics."""

        def __init__(self) -> None:
            super().__init__("openbene_dataset_relocalization")

            self.declare_parameter("report_path", "")
            self.declare_parameter("session_dir", "")
            self.declare_parameter("map_pointcloud", "")
            self.declare_parameter("world_frame", "openbene_map")
            self.declare_parameter("initial_guess_topic", "/openbene/relocalization/initial_guess")
            self.declare_parameter("refined_pose_topic", "/openbene/relocalization/refined_pose")
            self.declare_parameter(
                "refined_initial_pose_topic",
                "/openbene/relocalization/refined_initial_pose",
            )
            self.declare_parameter("fitness_topic", "/openbene/relocalization/fitness")
            self.declare_parameter("status_topic", "/openbene/relocalization/status")
            self.declare_parameter("output_report_path", "")
            self.declare_parameter("initial_pose_frame_index", 0)
            self.declare_parameter("voxel_size", 0.03)
            self.declare_parameter("crop_radius", 2.5)
            self.declare_parameter("source_stride", 8)
            self.declare_parameter("source_near_depth", 0.15)
            self.declare_parameter("source_far_depth", 2.0)
            self.declare_parameter("source_frame_start", 0)
            self.declare_parameter("source_frame_count", 0)
            self.declare_parameter("source_tail_frames", 0)
            self.declare_parameter("target_prior_enabled", False)
            self.declare_parameter("target_prior_center_x", 0.0)
            self.declare_parameter("target_prior_center_z", 0.0)
            self.declare_parameter("target_prior_radius", 0.0)
            self.declare_parameter("target_prior_weight", 0.0)
            self.declare_parameter("success_fitness_threshold", 0.35)
            self.declare_parameter("success_rmse_threshold", 0.08)
            self.declare_parameter("warning_fitness_threshold", 0.15)
            self.declare_parameter("warning_rmse_threshold", 0.20)

            self._report_path = str(self.get_parameter("report_path").value).strip()
            self._session_dir = str(self.get_parameter("session_dir").value).strip()
            self._map_pointcloud = str(self.get_parameter("map_pointcloud").value).strip()
            self._world_frame = str(self.get_parameter("world_frame").value)
            self._output_report_path = str(self.get_parameter("output_report_path").value).strip()

            if not self._report_path:
                if not self._session_dir:
                    raise ValueError(
                        "Parameter 'session_dir' must point to an OpenBene capture session "
                        "when 'report_path' is not provided."
                    )
                if not self._map_pointcloud:
                    raise ValueError(
                        "Parameter 'map_pointcloud' must point to a map_tsdf_pointcloud.ply file "
                        "when 'report_path' is not provided."
                    )

            qos = QoSProfile(
                history=HistoryPolicy.KEEP_LAST,
                depth=1,
                reliability=ReliabilityPolicy.RELIABLE,
                durability=DurabilityPolicy.TRANSIENT_LOCAL,
            )
            self._initial_guess_publisher = self.create_publisher(
                PoseStamped,
                str(self.get_parameter("initial_guess_topic").value),
                qos,
            )
            self._refined_pose_publisher = self.create_publisher(
                PoseStamped,
                str(self.get_parameter("refined_pose_topic").value),
                qos,
            )
            self._refined_initial_pose_publisher = self.create_publisher(
                PoseStamped,
                str(self.get_parameter("refined_initial_pose_topic").value),
                qos,
            )
            self._fitness_publisher = self.create_publisher(
                Float32,
                str(self.get_parameter("fitness_topic").value),
                qos,
            )
            self._status_publisher = self.create_publisher(
                String,
                str(self.get_parameter("status_topic").value),
                qos,
            )

            self._timer = self.create_timer(0.1, self._run_once)
            self._finished = False

        def _publish_status(self, payload: dict[str, object]) -> None:
            msg = String()
            msg.data = json.dumps(payload, ensure_ascii=True)
            self._status_publisher.publish(msg)

        def _publish_error(self, message: str) -> None:
            self.get_logger().error(message)
            self._publish_status({"state": "error", "detail": message})

        def _run_once(self) -> None:
            if self._finished:
                return
            self._finished = True
            self._timer.cancel()

            if self._report_path:
                try:
                    result_payload = load_relocalization_report(self._report_path)
                except Exception as exc:
                    self._publish_error(f"Failed to load relocalization report: {exc}")
                    return
            else:
                try:
                    from openbene.relocalization import (
                        relocalize_session_against_pointcloud,
                        write_relocalization_report,
                    )
                except ModuleNotFoundError as exc:
                    missing = exc.name or str(exc)
                    if missing == "openbene" or missing.startswith("openbene."):
                        self._publish_error(
                            "Dataset relocalization requires the local OpenBene SDK. "
                            f"Install it with: {SDK_INSTALL_HINT}"
                        )
                        return
                    self._publish_error(f"Dataset relocalization missing dependency '{missing}': {exc}")
                    return
                except Exception as exc:
                    self._publish_error(f"Failed to import relocalization helpers: {exc}")
                    return

                try:
                    target_prior_center = None
                    if bool(self.get_parameter("target_prior_enabled").value):
                        target_prior_center = (
                            float(self.get_parameter("target_prior_center_x").value),
                            float(self.get_parameter("target_prior_center_z").value),
                        )
                    result = relocalize_session_against_pointcloud(
                        Path(self._session_dir).expanduser().resolve(),
                        Path(self._map_pointcloud).expanduser().resolve(),
                        voxel_size=float(self.get_parameter("voxel_size").value),
                        crop_radius=float(self.get_parameter("crop_radius").value),
                        source_stride=int(self.get_parameter("source_stride").value),
                        source_near_depth=float(self.get_parameter("source_near_depth").value),
                        source_far_depth=float(self.get_parameter("source_far_depth").value),
                        source_frame_start=int(self.get_parameter("source_frame_start").value),
                        source_frame_count=int(self.get_parameter("source_frame_count").value),
                        source_tail_frames=int(self.get_parameter("source_tail_frames").value),
                        target_prior_center=target_prior_center,
                        target_prior_radius=float(self.get_parameter("target_prior_radius").value),
                        target_prior_weight=float(self.get_parameter("target_prior_weight").value),
                    )
                    report_path = write_relocalization_report(result, self._output_report_path or None)
                    result_payload = {
                        "session_dir": str(result.session_dir),
                        "map_pointcloud": str(result.map_pointcloud),
                        "source_frame_start": int(result.source_frame_start),
                        "source_frame_count": int(result.source_frame_count),
                        "source_tail_frames": int(result.source_tail_frames),
                        "source_effective_frame_start": int(result.source_effective_frame_start),
                        "source_effective_frame_count": int(result.source_effective_frame_count),
                        "target_submap_mode": str(result.target_submap_mode),
                        "target_submap_radius": float(result.target_submap_radius),
                        "target_submap_step": float(result.target_submap_step),
                        "target_submap_candidate_count": int(result.target_submap_candidate_count),
                        "target_submap_selected_index": int(result.target_submap_selected_index),
                        "target_submap_center": tuple(float(value) for value in result.target_submap_center),
                        "target_retrieval_method": str(result.target_retrieval_method),
                        "target_retrieval_top_k": int(result.target_retrieval_top_k),
                        "target_retrieval_selected_rank": int(result.target_retrieval_selected_rank),
                        "target_retrieval_score": float(result.target_retrieval_score),
                        "target_prior_method": str(result.target_prior_method),
                        "target_prior_center": tuple(float(value) for value in result.target_prior_center),
                        "target_prior_radius": float(result.target_prior_radius),
                        "target_prior_weight": float(result.target_prior_weight),
                        "target_prior_selected_distance": float(result.target_prior_selected_distance),
                        "global_method": str(result.global_method),
                        "global_fitness": float(result.global_fitness),
                        "global_rmse": float(result.global_rmse),
                        "global_support_method": str(result.global_support_method),
                        "global_support_score": float(result.global_support_score),
                        "coarse_init_method": str(result.coarse_init_method),
                        "coarse_fitness": float(result.coarse_fitness),
                        "coarse_rmse": float(result.coarse_rmse),
                        "icp_fitness": float(result.icp_fitness),
                        "icp_rmse": float(result.icp_rmse),
                        "fine_icp_fitness": float(result.fine_icp_fitness),
                        "fine_icp_rmse": float(result.fine_icp_rmse),
                        "global_transformation": result.global_transformation,
                        "transformation": result.transformation,
                        "report_path": str(report_path),
                        "source": "computed",
                    }
                except Exception as exc:
                    self._publish_error(f"Relocalization failed: {exc}")
                    return

            status_state = classify_relocalization_state(
                float(result_payload["fine_icp_fitness"]),
                float(result_payload["fine_icp_rmse"]),
                success_fitness_threshold=float(self.get_parameter("success_fitness_threshold").value),
                success_rmse_threshold=float(self.get_parameter("success_rmse_threshold").value),
                warning_fitness_threshold=float(self.get_parameter("warning_fitness_threshold").value),
                warning_rmse_threshold=float(self.get_parameter("warning_rmse_threshold").value),
            )

            stamp = self.get_clock().now().to_msg()
            self._initial_guess_publisher.publish(
                make_pose_msg_from_transform(
                    result_payload["global_transformation"],
                    stamp=stamp,
                    frame_id=self._world_frame,
                )
            )
            self._refined_pose_publisher.publish(
                make_pose_msg_from_transform(
                    result_payload["transformation"],
                    stamp=stamp,
                    frame_id=self._world_frame,
                )
            )
            try:
                effective_frame_start = int(result_payload.get("source_effective_frame_start", 0))
                initial_pose_position, initial_pose_orientation = relocalization_transform_to_initial_pose(
                    result_payload["transformation"],
                    result_payload["session_dir"],
                    frame_index=effective_frame_start + int(self.get_parameter("initial_pose_frame_index").value),
                )
            except Exception as exc:
                self._publish_error(f"Failed to derive initial pose from relocalization result: {exc}")
                return

            self._refined_initial_pose_publisher.publish(
                make_pose_msg_from_components(
                    initial_pose_position,
                    initial_pose_orientation,
                    stamp=stamp,
                    frame_id=self._world_frame,
                )
            )

            fitness_msg = Float32()
            fitness_msg.data = float(result_payload["fine_icp_fitness"])
            self._fitness_publisher.publish(fitness_msg)

            self._publish_status(
                {
                    "state": status_state,
                    "session_dir": str(result_payload["session_dir"]),
                    "map_pointcloud": str(result_payload["map_pointcloud"]),
                    "report_path": str(result_payload["report_path"]),
                    "source": str(result_payload["source"]),
                    "target_submap_mode": str(result_payload.get("target_submap_mode", "full_map")),
                    "target_submap_radius": float(result_payload.get("target_submap_radius", 0.0)),
                    "target_submap_step": float(result_payload.get("target_submap_step", 0.0)),
                    "target_submap_candidate_count": int(result_payload.get("target_submap_candidate_count", 0)),
                    "target_submap_selected_index": int(result_payload.get("target_submap_selected_index", -1)),
                    "target_submap_center": list(result_payload.get("target_submap_center", (0.0, 0.0, 0.0))),
                    "target_retrieval_method": str(result_payload.get("target_retrieval_method", "none")),
                    "target_retrieval_top_k": int(result_payload.get("target_retrieval_top_k", 0)),
                    "target_retrieval_selected_rank": int(result_payload.get("target_retrieval_selected_rank", -1)),
                    "target_retrieval_score": float(result_payload.get("target_retrieval_score", 0.0)),
                    "target_prior_method": str(result_payload.get("target_prior_method", "none")),
                    "target_prior_center": list(result_payload.get("target_prior_center", (0.0, 0.0, 0.0))),
                    "target_prior_radius": float(result_payload.get("target_prior_radius", 0.0)),
                    "target_prior_weight": float(result_payload.get("target_prior_weight", 0.0)),
                    "target_prior_selected_distance": float(result_payload.get("target_prior_selected_distance", -1.0)),
                    "global_method": str(result_payload.get("global_method", "unknown")),
                    "global_fitness": float(result_payload["global_fitness"]),
                    "global_rmse": float(result_payload["global_rmse"]),
                    "global_support_method": str(result_payload.get("global_support_method", "unknown")),
                    "global_support_score": float(result_payload.get("global_support_score", 0.0)),
                    "coarse_init_method": str(result_payload.get("coarse_init_method", "unknown")),
                    "coarse_fitness": float(result_payload.get("coarse_fitness", 0.0)),
                    "coarse_rmse": float(result_payload.get("coarse_rmse", 0.0)),
                    "icp_fitness": float(result_payload["icp_fitness"]),
                    "icp_rmse": float(result_payload["icp_rmse"]),
                    "fine_icp_fitness": float(result_payload["fine_icp_fitness"]),
                    "fine_icp_rmse": float(result_payload["fine_icp_rmse"]),
                    "source_frame_start": int(result_payload.get("source_frame_start", 0)),
                    "source_frame_count": int(result_payload.get("source_frame_count", 0)),
                    "source_tail_frames": int(result_payload.get("source_tail_frames", 0)),
                    "source_effective_frame_start": int(result_payload.get("source_effective_frame_start", 0)),
                    "source_effective_frame_count": int(result_payload.get("source_effective_frame_count", 0)),
                    "refined_initial_pose": {
                        "frame_id": self._world_frame,
                        "position": list(initial_pose_position),
                        "orientation": list(initial_pose_orientation),
                    },
                }
            )

            self.get_logger().info(
                "Relocalization finished with state '%s'. fine_icp_fitness=%.4f fine_icp_rmse=%.4f report=%s source=%s"
                % (
                    status_state,
                    float(result_payload["fine_icp_fitness"]),
                    float(result_payload["fine_icp_rmse"]),
                    str(result_payload["report_path"]),
                    str(result_payload["source"]),
                )
            )

    rclpy.init(args=args)
    node = DatasetRelocalization()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()
