import json
import sys
from pathlib import Path
import tempfile
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from openbene_ros2.session_doctor import build_session_report


class SessionDoctorTests(unittest.TestCase):
    def test_report_marks_depth_only_session_as_usable(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            dataset_dir = Path(temp_dir)
            (dataset_dir / "depth").mkdir()
            (dataset_dir / "confidence").mkdir()
            (dataset_dir / "depth" / "000000.png").write_bytes(b"depth")
            (dataset_dir / "confidence" / "000000.png").write_bytes(b"confidence")
            (dataset_dir / "transforms.json").write_text(
                json.dumps(
                    {
                        "w": 256,
                        "h": 192,
                        "fl_x": 130.0,
                        "fl_y": 130.0,
                        "cx": 128.0,
                        "cy": 96.0,
                        "depth_scale": 1000.0,
                        "frames": [
                            {
                                "depth_file_path": "depth/000000.png",
                                "confidence_file_path": "confidence/000000.png",
                                "tracking_state": "normal",
                                "depth_source": "smoothed_scene_depth",
                                "timestamp": 1.0,
                                "transform_matrix": [
                                    [1.0, 0.0, 0.0, 0.0],
                                    [0.0, 1.0, 0.0, 0.0],
                                    [0.0, 0.0, 1.0, 0.0],
                                    [0.0, 0.0, 0.0, 1.0],
                                ],
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )

            report = "\n".join(build_session_report(dataset_dir))
            self.assertIn("[OK] session is usable for the current 2D ROS2 scan pipeline.", report)
            self.assertIn("tracking_state_breakdown=normal=1", report)
            self.assertIn("depth_source_breakdown=smoothed_scene_depth=1", report)
            self.assertNotIn("no frames are marked with depth_source=smoothed_scene_depth", report)

    def test_report_warns_when_tracking_and_confidence_are_missing(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            dataset_dir = Path(temp_dir)
            (dataset_dir / "depth").mkdir()
            (dataset_dir / "depth" / "000000.png").write_bytes(b"depth")
            (dataset_dir / "transforms.json").write_text(
                json.dumps(
                    {
                        "w": 256,
                        "h": 192,
                        "fl_x": 130.0,
                        "fl_y": 130.0,
                        "cx": 128.0,
                        "cy": 96.0,
                        "depth_scale": 1000.0,
                        "frames": [
                            {
                                "depth_file_path": "depth/000000.png",
                                "timestamp": 1.0,
                                "transform_matrix": [
                                    [1.0, 0.0, 0.0, 0.0],
                                    [0.0, 1.0, 0.0, 0.0],
                                    [0.0, 0.0, 1.0, 0.0],
                                    [0.0, 0.0, 0.0, 1.0],
                                ],
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )

            report = "\n".join(build_session_report(dataset_dir))
            self.assertIn("[WARN] tracking_state is missing for all frames.", report)
            self.assertIn("[WARN] no readable confidence frames were found.", report)
            self.assertIn("[WARN] depth_source is missing for all frames.", report)
            self.assertIn("[OK] session is usable for the current 2D ROS2 scan pipeline.", report)


if __name__ == "__main__":
    unittest.main()
