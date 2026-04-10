import sys
from pathlib import Path
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from openbene_ros2.relocalization_initialpose_bridge import build_planar_covariance
from openbene_ros2.relocalization_initialpose_bridge import normalize_simple_pose


class RelocalizationInitialPoseBridgeTests(unittest.TestCase):
    def test_build_planar_covariance_sets_expected_entries(self) -> None:
        covariance = build_planar_covariance(
            xy_stddev=0.15,
            yaw_stddev=0.25,
            z_stddev=0.05,
            roll_pitch_stddev=0.1,
        )

        self.assertEqual(len(covariance), 36)
        self.assertAlmostEqual(covariance[0], 0.0225)
        self.assertAlmostEqual(covariance[7], 0.0225)
        self.assertAlmostEqual(covariance[14], 0.0025)
        self.assertAlmostEqual(covariance[21], 0.01)
        self.assertAlmostEqual(covariance[28], 0.01)
        self.assertAlmostEqual(covariance[35], 0.0625)

    def test_normalize_simple_pose_flattens_z_when_requested(self) -> None:
        pose = normalize_simple_pose(
            frame_id="map",
            position=(1.0, 2.0, 3.0),
            orientation=(0.0, 0.0, 0.1, 0.99),
            force_zero_z=True,
        )

        self.assertEqual(pose.frame_id, "map")
        self.assertEqual(pose.position, (1.0, 2.0, 0.0))
        self.assertEqual(pose.orientation, (0.0, 0.0, 0.1, 0.99))

    def test_normalize_simple_pose_rejects_bad_shapes(self) -> None:
        with self.assertRaisesRegex(ValueError, "position"):
            normalize_simple_pose(
                frame_id="map",
                position=(1.0, 2.0),
                orientation=(0.0, 0.0, 0.0, 1.0),
                force_zero_z=False,
            )

        with self.assertRaisesRegex(ValueError, "orientation"):
            normalize_simple_pose(
                frame_id="map",
                position=(1.0, 2.0, 3.0),
                orientation=(0.0, 0.0, 1.0),
                force_zero_z=False,
            )


if __name__ == "__main__":
    unittest.main()
