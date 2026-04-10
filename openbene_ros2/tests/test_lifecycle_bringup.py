import sys
from pathlib import Path
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from openbene_ros2.lifecycle_bringup import ACTIVATE_TRANSITION_ID
from openbene_ros2.lifecycle_bringup import CONFIGURE_TRANSITION_ID
from openbene_ros2.lifecycle_bringup import normalize_node_names


class LifecycleBringupTests(unittest.TestCase):
    def test_normalize_node_names_strips_empty_values(self) -> None:
        self.assertEqual(normalize_node_names([" map_server ", "", " amcl "]), ["map_server", "amcl"])

    def test_normalize_node_names_rejects_empty_result(self) -> None:
        with self.assertRaisesRegex(ValueError, "managed_nodes"):
            normalize_node_names(["", "   "])

    def test_transition_ids_match_expected_ros_lifecycle_constants(self) -> None:
        self.assertEqual(CONFIGURE_TRANSITION_ID, 1)
        self.assertEqual(ACTIVATE_TRANSITION_ID, 3)


if __name__ == "__main__":
    unittest.main()
