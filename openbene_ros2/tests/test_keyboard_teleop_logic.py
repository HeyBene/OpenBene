import sys
from pathlib import Path
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from openbene_ros2.keyboard_teleop_logic import KeyboardTeleopConfig
from openbene_ros2.keyboard_teleop_logic import command_for_key


class KeyboardTeleopLogicTests(unittest.TestCase):
    def setUp(self) -> None:
        self.cfg = KeyboardTeleopConfig()

    def test_forward_mapping(self) -> None:
        command = command_for_key("w", cfg=self.cfg)
        self.assertIsNotNone(command)
        self.assertAlmostEqual(command.linear_x, 0.12)
        self.assertAlmostEqual(command.angular_z, 0.0)
        self.assertEqual(command.label, "forward")

    def test_uppercase_key_is_supported(self) -> None:
        command = command_for_key("W", cfg=self.cfg)
        self.assertIsNotNone(command)
        self.assertEqual(command.label, "forward")

    def test_arc_left_mapping(self) -> None:
        command = command_for_key("q", cfg=self.cfg)
        self.assertIsNotNone(command)
        self.assertAlmostEqual(command.linear_x, 0.072)
        self.assertAlmostEqual(command.angular_z, 0.4)
        self.assertEqual(command.label, "arc_left")

    def test_stop_mapping_for_space(self) -> None:
        command = command_for_key(" ", cfg=self.cfg)
        self.assertIsNotNone(command)
        self.assertEqual(command.linear_x, 0.0)
        self.assertEqual(command.angular_z, 0.0)
        self.assertEqual(command.label, "stop")

    def test_unknown_key_returns_none(self) -> None:
        self.assertIsNone(command_for_key("z", cfg=self.cfg))
        self.assertIsNone(command_for_key("ab", cfg=self.cfg))


if __name__ == "__main__":
    unittest.main()
