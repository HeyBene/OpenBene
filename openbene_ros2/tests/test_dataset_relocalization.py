import json
import sys
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from openbene_ros2.dataset_relocalization import classify_relocalization_state
from openbene_ros2.dataset_relocalization import compose_transform_matrices
from openbene_ros2.dataset_relocalization import load_relocalization_report
from openbene_ros2.dataset_relocalization import relocalization_transform_to_initial_pose
from openbene_ros2.dataset_relocalization import resolve_local_path
from openbene_ros2.dataset_relocalization import transform_to_translation_quaternion
from openbene_ros2.planar_pose import planar_pose_from_opengl_camera_transform
from openbene_ros2.planar_pose import quaternion_from_yaw


class DatasetRelocalizationTests(unittest.TestCase):
    def test_transform_to_translation_quaternion_returns_pose_components(self) -> None:
        translation, quaternion = transform_to_translation_quaternion(
            (
                (1.0, 0.0, 0.0, 1.25),
                (0.0, 1.0, 0.0, -2.5),
                (0.0, 0.0, 1.0, 0.75),
                (0.0, 0.0, 0.0, 1.0),
            )
        )

        self.assertEqual(translation, (1.25, -2.5, 0.75))
        self.assertAlmostEqual(quaternion[0], 0.0)
        self.assertAlmostEqual(quaternion[1], 0.0)
        self.assertAlmostEqual(quaternion[2], 0.0)
        self.assertAlmostEqual(quaternion[3], 1.0)

    def test_compose_transform_matrices_multiplies_translations(self) -> None:
        composed = compose_transform_matrices(
            (
                (1.0, 0.0, 0.0, 1.0),
                (0.0, 1.0, 0.0, 2.0),
                (0.0, 0.0, 1.0, 3.0),
                (0.0, 0.0, 0.0, 1.0),
            ),
            (
                (1.0, 0.0, 0.0, 0.5),
                (0.0, 1.0, 0.0, -0.5),
                (0.0, 0.0, 1.0, 1.5),
                (0.0, 0.0, 0.0, 1.0),
            ),
        )

        self.assertEqual(composed[0][3], 1.5)
        self.assertEqual(composed[1][3], 1.5)
        self.assertEqual(composed[2][3], 4.5)

    def test_relocalization_transform_to_initial_pose_uses_first_depth_frame(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            session_dir = Path(tmpdir) / "session"
            session_dir.mkdir()
            frame_transform = (
                (0.0, 0.0, -1.0, 1.25),
                (0.0, 1.0, 0.0, 0.0),
                (1.0, 0.0, 0.0, -2.5),
                (0.0, 0.0, 0.0, 1.0),
            )
            (session_dir / "transforms.json").write_text(
                json.dumps(
                    {
                        "w": 10,
                        "h": 10,
                        "fl_x": 1.0,
                        "fl_y": 1.0,
                        "cx": 0.0,
                        "cy": 0.0,
                        "frames": [
                            {
                                "file_path": "images/000000.jpg",
                                "depth_file_path": "depth/000000.png",
                                "timestamp": 0.0,
                                "transform_matrix": frame_transform,
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )

            position, orientation = relocalization_transform_to_initial_pose(
                (
                    (1.0, 0.0, 0.0, 0.0),
                    (0.0, 1.0, 0.0, 0.0),
                    (0.0, 0.0, 1.0, 0.0),
                    (0.0, 0.0, 0.0, 1.0),
                ),
                session_dir,
            )

        expected_planar_pose = planar_pose_from_opengl_camera_transform(frame_transform)
        expected_orientation = quaternion_from_yaw(expected_planar_pose.yaw)
        self.assertEqual(position, (1.25, -2.5, 0.0))
        self.assertEqual(orientation, expected_orientation)

    def test_classify_relocalization_state_reports_success(self) -> None:
        state = classify_relocalization_state(
            0.72,
            0.03,
            success_fitness_threshold=0.35,
            success_rmse_threshold=0.08,
            warning_fitness_threshold=0.15,
            warning_rmse_threshold=0.20,
        )
        self.assertEqual(state, "success")

    def test_classify_relocalization_state_reports_warning(self) -> None:
        state = classify_relocalization_state(
            0.20,
            0.12,
            success_fitness_threshold=0.35,
            success_rmse_threshold=0.08,
            warning_fitness_threshold=0.15,
            warning_rmse_threshold=0.20,
        )
        self.assertEqual(state, "warning")

    def test_classify_relocalization_state_reports_failed(self) -> None:
        state = classify_relocalization_state(
            0.05,
            0.25,
            success_fitness_threshold=0.35,
            success_rmse_threshold=0.08,
            warning_fitness_threshold=0.15,
            warning_rmse_threshold=0.20,
        )
        self.assertEqual(state, "failed")

    def test_load_relocalization_report_parses_precomputed_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            report_path = Path(tmpdir) / "relocalization_report.json"
            report_path.write_text(
                json.dumps(
                    {
                        "session_dir": "/tmp/session",
                        "map_pointcloud": "/tmp/map.ply",
                        "target_submap_mode": "local_submap",
                        "target_submap_radius": 3.0,
                        "target_submap_step": 1.5,
                        "target_submap_candidate_count": 11,
                        "target_submap_selected_index": 4,
                        "target_submap_center": [1.0, -0.5, 2.0],
                        "target_retrieval_method": "fpfh_shape_descriptor",
                        "target_retrieval_top_k": 4,
                        "target_retrieval_selected_rank": 1,
                        "target_retrieval_score": 0.123,
                        "target_prior_method": "planar_distance_bias",
                        "target_prior_center": [1.5, -0.5, 2.5],
                        "target_prior_radius": 2.0,
                        "target_prior_weight": 0.2,
                        "target_prior_selected_distance": 0.4,
                        "global_method": "fgr",
                        "global_fitness": 0.0,
                        "global_rmse": 0.0,
                        "global_support_method": "bev_corr_scan_context_yaw",
                        "global_support_score": 0.41,
                        "coarse_init_method": "identity",
                        "coarse_fitness": 0.42,
                        "coarse_rmse": 0.03,
                        "icp_fitness": 0.93,
                        "icp_rmse": 0.0081,
                        "fine_icp_fitness": 0.8967,
                        "fine_icp_rmse": 0.0070,
                        "source_frame_start": 12,
                        "source_frame_count": 24,
                        "source_tail_frames": 0,
                        "source_effective_frame_start": 12,
                        "source_effective_frame_count": 24,
                        "global_transformation": [
                            [1.0, 0.0, 0.0, 0.1],
                            [0.0, 1.0, 0.0, 0.2],
                            [0.0, 0.0, 1.0, 0.3],
                            [0.0, 0.0, 0.0, 1.0],
                        ],
                        "transformation": [
                            [1.0, 0.0, 0.0, 1.1],
                            [0.0, 1.0, 0.0, 1.2],
                            [0.0, 0.0, 1.0, 1.3],
                            [0.0, 0.0, 0.0, 1.0],
                        ],
                    }
                ),
                encoding="utf-8",
            )

            payload = load_relocalization_report(report_path)

        self.assertEqual(payload["source"], "precomputed_report")
        self.assertEqual(payload["session_dir"], str(Path("/tmp/session").expanduser().resolve()))
        self.assertEqual(payload["map_pointcloud"], str(Path("/tmp/map.ply").expanduser().resolve()))
        self.assertEqual(payload["report_path"], str(report_path.resolve()))
        self.assertEqual(payload["target_submap_mode"], "local_submap")
        self.assertEqual(payload["target_submap_radius"], 3.0)
        self.assertEqual(payload["target_submap_step"], 1.5)
        self.assertEqual(payload["target_submap_candidate_count"], 11)
        self.assertEqual(payload["target_submap_selected_index"], 4)
        self.assertEqual(payload["target_submap_center"], (1.0, -0.5, 2.0))
        self.assertEqual(payload["target_retrieval_method"], "fpfh_shape_descriptor")
        self.assertEqual(payload["target_retrieval_top_k"], 4)
        self.assertEqual(payload["target_retrieval_selected_rank"], 1)
        self.assertEqual(payload["target_retrieval_score"], 0.123)
        self.assertEqual(payload["target_prior_method"], "planar_distance_bias")
        self.assertEqual(payload["target_prior_center"], (1.5, -0.5, 2.5))
        self.assertEqual(payload["target_prior_radius"], 2.0)
        self.assertEqual(payload["target_prior_weight"], 0.2)
        self.assertEqual(payload["target_prior_selected_distance"], 0.4)
        self.assertEqual(payload["global_method"], "fgr")
        self.assertEqual(payload["global_support_method"], "bev_corr_scan_context_yaw")
        self.assertAlmostEqual(payload["global_support_score"], 0.41)
        self.assertEqual(payload["coarse_init_method"], "identity")
        self.assertAlmostEqual(payload["fine_icp_fitness"], 0.8967)
        self.assertAlmostEqual(payload["coarse_fitness"], 0.42)
        self.assertAlmostEqual(payload["coarse_rmse"], 0.03)
        self.assertEqual(payload["transformation"][0][3], 1.1)
        self.assertEqual(payload["source_frame_start"], 12)
        self.assertEqual(payload["source_frame_count"], 24)
        self.assertEqual(payload["source_tail_frames"], 0)
        self.assertEqual(payload["source_effective_frame_start"], 12)
        self.assertEqual(payload["source_effective_frame_count"], 24)

    def test_resolve_local_path_converts_windows_drive_path_on_posix(self) -> None:
        with patch("openbene_ros2.dataset_relocalization.RUNNING_ON_WINDOWS", False):
            resolved = resolve_local_path(r"C:\Users\jiken\Desktop\OpenBene\dataset\transforms.json")

        self.assertEqual(
            resolved,
            Path("/mnt/c/Users/jiken/Desktop/OpenBene/dataset/transforms.json").resolve(),
        )

    def test_load_relocalization_report_rejects_missing_fields(self) -> None:
        with tempfile.TemporaryDirectory() as tmpdir:
            report_path = Path(tmpdir) / "relocalization_report.json"
            report_path.write_text(json.dumps({"session_dir": "/tmp/session"}), encoding="utf-8")

            with self.assertRaisesRegex(ValueError, "missing required field"):
                load_relocalization_report(report_path)


if __name__ == "__main__":
    unittest.main()
