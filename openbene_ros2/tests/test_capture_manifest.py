import json
import sys
from pathlib import Path
import tempfile
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from openbene_ros2.capture_manifest import load_capture_manifest


class CaptureManifestTests(unittest.TestCase):
    def test_load_manifest_resolves_paths_and_depth_frames(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            dataset_dir = Path(temp_dir)
            (dataset_dir / "images").mkdir()
            (dataset_dir / "depth").mkdir()
            (dataset_dir / "images" / "000007.jpg").write_bytes(b"jpg")
            (dataset_dir / "depth" / "000007.png").write_bytes(b"png")

            manifest_payload = {
                "w": 1920,
                "h": 1440,
                "fl_x": 1100.0,
                "fl_y": 1090.0,
                "cx": 960.0,
                "cy": 720.0,
                "depth_scale": 1000.0,
                "frames": [
                    {
                        "file_path": "images/000007.jpg",
                        "depth_file_path": "depth/000007.png",
                        "timestamp": 12.5,
                        "transform_matrix": [
                            [1.0, 0.0, 0.0, 0.0],
                            [0.0, 1.0, 0.0, 0.0],
                            [0.0, 0.0, 1.0, 0.0],
                            [0.0, 0.0, 0.0, 1.0],
                        ],
                    }
                ],
            }
            (dataset_dir / "transforms.json").write_text(
                json.dumps(manifest_payload),
                encoding="utf-8",
            )

            manifest = load_capture_manifest(dataset_dir)

            self.assertEqual(manifest.width, 1920)
            self.assertEqual(manifest.height, 1440)
            self.assertEqual(len(manifest.frames), 1)
            self.assertEqual(len(manifest.depth_frames), 1)
            self.assertEqual(manifest.frames[0].index, 7)
            self.assertTrue(manifest.frames[0].image_path.is_absolute())
            self.assertTrue(manifest.frames[0].depth_path.is_absolute())

    def test_load_manifest_supports_depth_only_frame_with_tracking_and_confidence(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            dataset_dir = Path(temp_dir)
            (dataset_dir / "depth").mkdir()
            (dataset_dir / "confidence").mkdir()
            (dataset_dir / "depth" / "000000.png").write_bytes(b"depth")
            (dataset_dir / "confidence" / "000000.png").write_bytes(b"confidence")

            manifest_payload = {
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
                        "timestamp": 3.0,
                        "transform_matrix": [
                            [1.0, 0.0, 0.0, 0.0],
                            [0.0, 1.0, 0.0, 0.0],
                            [0.0, 0.0, 1.0, 0.0],
                            [0.0, 0.0, 0.0, 1.0],
                        ],
                    }
                ],
            }
            (dataset_dir / "transforms.json").write_text(
                json.dumps(manifest_payload),
                encoding="utf-8",
            )

            manifest = load_capture_manifest(dataset_dir)
            self.assertEqual(len(manifest.depth_frames), 1)
            self.assertIsNone(manifest.frames[0].image_path)
            self.assertEqual(manifest.frames[0].tracking_state, "normal")
            self.assertEqual(manifest.frames[0].depth_source, "smoothed_scene_depth")
            self.assertTrue(manifest.frames[0].confidence_path is not None)
            self.assertTrue(manifest.frames[0].confidence_path.is_absolute())

    def test_manifest_without_transforms_raises(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            with self.assertRaises(FileNotFoundError):
                load_capture_manifest(temp_dir)


if __name__ == "__main__":
    unittest.main()
