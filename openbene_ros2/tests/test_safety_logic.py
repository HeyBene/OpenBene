import sys
from pathlib import Path
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from openbene_ros2.safety_logic import SafetyConfig
from openbene_ros2.safety_logic import apply_linear_safety
from openbene_ros2.safety_logic import clamp_abs
from openbene_ros2.safety_logic import front_min_range


class SafetyLogicTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cfg = SafetyConfig()

    def test_front_min_range_ignores_outside_sector(self) -> None:
        nearest = front_min_range(
            [0.5, 0.25, 0.6, 0.8, 0.3],
            angle_min=-1.0,
            angle_increment=0.5,
            front_sector_half_angle_deg=20.0,
            range_min=0.1,
            range_max=5.0,
        )
        self.assertAlmostEqual(nearest or 0.0, 0.6)

    def test_front_min_range_returns_none_when_no_valid_value(self) -> None:
        nearest = front_min_range(
            [float("inf"), 8.0, 0.05],
            angle_min=-0.1,
            angle_increment=0.1,
            front_sector_half_angle_deg=30.0,
            range_min=0.1,
            range_max=5.0,
        )
        self.assertIsNone(nearest)

    def test_apply_linear_safety_stops_inside_stop_distance(self) -> None:
        self.assertEqual(
            apply_linear_safety(0.12, front_min_distance_m=0.19, cfg=self.cfg),
            0.0,
        )

    def test_apply_linear_safety_scales_down_inside_slowdown_band(self) -> None:
        slowed = apply_linear_safety(0.15, front_min_distance_m=0.275, cfg=self.cfg)
        self.assertGreater(slowed, 0.0)
        self.assertLess(slowed, 0.15)
        self.assertAlmostEqual(slowed, 0.075, places=3)

    def test_apply_linear_safety_clamps_speed_even_without_scan(self) -> None:
        self.assertEqual(
            apply_linear_safety(0.5, front_min_distance_m=None, cfg=self.cfg),
            self.cfg.max_linear_speed_mps,
        )

    def test_reverse_motion_is_not_blocked_by_front_obstacle(self) -> None:
        self.assertEqual(
            apply_linear_safety(-0.1, front_min_distance_m=0.1, cfg=self.cfg),
            -0.1,
        )

    def test_clamp_abs_limits_rotation(self) -> None:
        self.assertEqual(clamp_abs(1.0, 0.5), 0.5)
        self.assertEqual(clamp_abs(-1.0, 0.5), -0.5)


if __name__ == "__main__":
    unittest.main()
