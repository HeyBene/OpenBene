import sys
from pathlib import Path
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from openbene_ros2.kinematics import clamp
from openbene_ros2.kinematics import twist_to_drive


class KinematicsTests(unittest.TestCase):
    def test_clamp_inside_range(self) -> None:
        self.assertEqual(clamp(0.25), 0.25)

    def test_clamp_upper_bound(self) -> None:
        self.assertEqual(clamp(5.0), 1.0)

    def test_clamp_lower_bound(self) -> None:
        self.assertEqual(clamp(-5.0), -1.0)

    def test_forward_motion_maps_evenly(self) -> None:
        left, right = twist_to_drive(0.3, 0.0)
        self.assertAlmostEqual(left, 0.3)
        self.assertAlmostEqual(right, 0.3)

    def test_positive_angular_velocity_turns_left_arc(self) -> None:
        left, right = twist_to_drive(0.3, 0.5, angular_scale=0.6)
        self.assertAlmostEqual(left, 0.0)
        self.assertAlmostEqual(right, 0.6)

    def test_negative_angular_velocity_turns_right_arc(self) -> None:
        left, right = twist_to_drive(0.3, -0.5, angular_scale=0.6)
        self.assertAlmostEqual(left, 0.6)
        self.assertAlmostEqual(right, 0.0)

    def test_output_is_clamped(self) -> None:
        left, right = twist_to_drive(1.0, 1.0, linear_scale=1.0, angular_scale=1.0)
        self.assertEqual(left, 0.0)
        self.assertEqual(right, 1.0)


if __name__ == "__main__":
    unittest.main()
