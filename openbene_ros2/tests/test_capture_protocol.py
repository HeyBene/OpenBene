import json
import sys
from pathlib import Path
import tempfile
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from openbene_ros2.capture_protocol import CaptureProtocolProcessor


class CaptureProtocolTests(unittest.TestCase):
    def test_handshake_matches_latest_receiver_capabilities(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            processor = CaptureProtocolProcessor(temp_dir)
            handshake = processor.handshake_payload()

            self.assertEqual(handshake["status"], "connected")
            self.assertEqual(handshake["receiver_state"], "ready")
            self.assertEqual(handshake["output_dir"], str(Path(temp_dir).resolve()))
            self.assertIn("session_manifest", handshake["capabilities"])
            self.assertIn("pointcloud_v1", handshake["capabilities"])
            self.assertIn("live_localization_v1", handshake["capabilities"])

    def test_depth_frame_upload_writes_dataset_and_emits_event(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            depth_events = []
            processor = CaptureProtocolProcessor(temp_dir, on_depth_frame=depth_events.append)

            session_started = processor.handle_text_message(
                json.dumps(
                    {
                        "type": "session_start",
                        "session_id": "abc123",
                        "session_name": "office_scan",
                        "session_mode": "Auto",
                    }
                )
            )
            self.assertEqual(session_started[0]["status"], "session_started")
            self.assertTrue(session_started[0]["output_dir"].endswith("office_scan"))

            processor.handle_text_message(
                json.dumps(
                    {
                        "type": "frame",
                        "index": 0,
                        "timestamp": 1.25,
                        "fl_x": 1000.0,
                        "fl_y": 1000.0,
                        "cx": 960.0,
                        "cy": 720.0,
                        "w": 1920,
                        "h": 1440,
                        "has_depth": True,
                        "depth_width": 256,
                        "depth_height": 192,
                        "transform_matrix": [
                            [1.0, 0.0, 0.0, 0.0],
                            [0.0, 1.0, 0.0, 0.0],
                            [0.0, 0.0, 1.0, 0.0],
                            [0.0, 0.0, 0.0, 1.0],
                        ],
                    }
                )
            )
            processor.handle_binary_message(b"fake-jpeg-data")
            processor.handle_binary_message(b"fake-depth-png")

            session_dir = processor.current_session_dir
            assert session_dir is not None
            self.assertTrue((session_dir / "images" / "000000.jpg").exists())
            self.assertTrue((session_dir / "depth" / "000000.png").exists())
            self.assertEqual(processor.frame_count, 1)
            self.assertEqual(len(depth_events), 1)
            self.assertEqual(depth_events[0].depth_png_bytes, b"fake-depth-png")
            self.assertEqual(depth_events[0].session_name, "office_scan")
            self.assertIsNotNone(depth_events[0].image_path)
            self.assertIsNone(depth_events[0].confidence_path)

            session_ending = processor.handle_text_message(
                json.dumps(
                    {
                        "type": "session_end",
                        "session_id": "abc123",
                        "session_name": "office_scan",
                        "session_mode": "Auto",
                    }
                )
            )
            self.assertEqual(session_ending[0]["status"], "session_ending")
            session_saved = processor.handle_binary_message(b'{"frames": []}')
            self.assertEqual(session_saved[0]["status"], "session_saved")
            self.assertEqual(session_saved[0]["received_frames"], 1)
            self.assertEqual(session_saved[0]["output_dir"], str(session_dir))
            self.assertTrue((session_dir / "transforms.json").exists())

    def test_finalize_if_needed_writes_generated_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            processor = CaptureProtocolProcessor(temp_dir)
            processor.handle_text_message(
                json.dumps(
                    {
                        "type": "session_start",
                        "session_id": "abc123",
                        "session_name": "manual_session",
                        "session_mode": "Manual",
                    }
                )
            )
            processor.handle_text_message(
                json.dumps(
                    {
                        "type": "frame",
                        "index": 7,
                        "timestamp": 3.5,
                        "fl_x": 500.0,
                        "fl_y": 510.0,
                        "cx": 320.0,
                        "cy": 240.0,
                        "w": 640,
                        "h": 480,
                        "has_depth": False,
                        "transform_matrix": [
                            [1.0, 0.0, 0.0, 0.0],
                            [0.0, 1.0, 0.0, 0.0],
                            [0.0, 0.0, 1.0, 0.0],
                            [0.0, 0.0, 0.0, 1.0],
                        ],
                    }
                )
            )
            processor.handle_binary_message(b"frame-jpeg")
            processor.finalize_if_needed()

            session_dir = processor.current_session_dir
            assert session_dir is not None
            manifest = json.loads((session_dir / "transforms.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["session_name"], "manual_session")
            self.assertEqual(manifest["frames"][0]["file_path"], "images/000007.jpg")
            self.assertNotIn("depth_file_path", manifest["frames"][0])

    def test_live_depth_only_frame_with_confidence_and_tracking(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            depth_events = []
            processor = CaptureProtocolProcessor(temp_dir, on_depth_frame=depth_events.append)

            processor.handle_text_message(
                json.dumps(
                    {
                        "type": "session_start",
                        "session_id": "live001",
                        "session_name": "live_localization",
                        "session_mode": "localization",
                    }
                )
            )
            processor.handle_text_message(
                json.dumps(
                    {
                        "type": "frame",
                        "index": 2,
                        "timestamp": 8.0,
                        "fl_x": 1000.0,
                        "fl_y": 1000.0,
                        "cx": 960.0,
                        "cy": 720.0,
                        "w": 1920,
                        "h": 1440,
                        "transfer_mode": "live",
                        "has_image": False,
                        "has_depth": True,
                        "has_confidence": True,
                        "depth_width": 256,
                        "depth_height": 192,
                        "confidence_width": 256,
                        "confidence_height": 192,
                        "tracking_state": "normal",
                        "depth_source": "smoothed_scene_depth",
                        "transform_matrix": [
                            [1.0, 0.0, 0.0, 0.0],
                            [0.0, 1.0, 0.0, 0.0],
                            [0.0, 0.0, 1.0, 0.0],
                            [0.0, 0.0, 0.0, 1.0],
                        ],
                    }
                )
            )
            processor.handle_binary_message(b"fake-depth-only-png")
            processor.handle_binary_message(b"fake-confidence-png")
            processor.finalize_if_needed()

            session_dir = processor.current_session_dir
            assert session_dir is not None
            self.assertFalse((session_dir / "images" / "000002.jpg").exists())
            self.assertTrue((session_dir / "depth" / "000002.png").exists())
            self.assertTrue((session_dir / "confidence" / "000002.png").exists())
            self.assertEqual(len(depth_events), 1)
            self.assertIsNone(depth_events[0].image_path)
            self.assertEqual(depth_events[0].tracking_state, "normal")
            self.assertEqual(depth_events[0].depth_source, "smoothed_scene_depth")
            self.assertEqual(depth_events[0].confidence_png_bytes, b"fake-confidence-png")

            manifest = json.loads((session_dir / "transforms.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["frames"][0]["tracking_state"], "normal")
            self.assertEqual(manifest["frames"][0]["depth_source"], "smoothed_scene_depth")
            self.assertEqual(manifest["frames"][0]["confidence_file_path"], "confidence/000002.png")


if __name__ == "__main__":
    unittest.main()
