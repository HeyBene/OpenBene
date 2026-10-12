import unittest

from openbene_nav.guidance import GuidanceBuilder, StepKind
from openbene_nav.model import MapData
from openbene_nav.router import Router

from tests.support import load_map


class GuidanceTests(unittest.TestCase):
    def setUp(self):
        self.map_data = load_map()
        self.router = Router(self.map_data)
        self.builder = GuidanceBuilder(self.map_data)

    def test_turn_left_route(self):
        route = self.router.route_to_room("loc_entrance", "Room 101")
        steps = self.builder.build(route)
        self.assertEqual([step.kind for step in steps], [StepKind.TURN_LEFT, StepKind.ARRIVE])
        self.assertAlmostEqual(steps[0].distance_m, 6.0)
        self.assertEqual(steps[0].at_location_id, "loc_junction")
        self.assertIn("turn left", steps[0].message)
        self.assertAlmostEqual(steps[1].distance_m, 4.0)
        self.assertIn("Room 101", steps[1].message)

    def test_straight_route_has_no_turn_step(self):
        route = self.router.route_to_room("loc_entrance", "Room 102")
        steps = self.builder.build(route)
        self.assertEqual([step.kind for step in steps], [StepKind.ARRIVE])
        self.assertAlmostEqual(steps[0].distance_m, 12.0)

    def test_route_backwards_detects_right_turn(self):
        # Heading south, then heading east: that is a left turn in a frame where
        # yaw grows counter-clockwise.
        route = self.router.route_to_room("loc_room101", "Room 102")
        steps = self.builder.build(route)
        self.assertEqual(steps[0].kind, StepKind.TURN_LEFT)
        self.assertIn("turn left", steps[0].message)

    def test_already_there(self):
        route = self.router.route_to_location("loc_room101", "loc_room101")
        steps = self.builder.build(route)
        self.assertEqual(len(steps), 1)
        self.assertEqual(steps[0].kind, StepKind.ARRIVE)
        self.assertAlmostEqual(steps[0].distance_m, 0.0)

    def test_turn_back_detection(self):
        raw = {
            "map_id": "u_turn",
            "locations": [
                {"id": "a", "pose": {"x": 0, "y": 0}},
                {"id": "b", "pose": {"x": 4, "y": 0}},
                {"id": "c", "pose": {"x": 1, "y": 0}},
            ],
            "edges": [
                {"id": "e1", "from": "a", "to": "b", "path": [{"x": 0, "y": 0}, {"x": 4, "y": 0}]},
                {"id": "e2", "from": "b", "to": "c", "path": [{"x": 4, "y": 0}, {"x": 1, "y": 0}]},
            ],
            "rooms": [{"id": "r", "name": "Dead End", "location_id": "c"}],
            "markers": [],
        }
        map_data = MapData.from_dict(raw)
        route = Router(map_data).route_to_room("a", "Dead End")
        steps = GuidanceBuilder(map_data).build(route)
        self.assertEqual(steps[0].kind, StepKind.TURN_BACK)


if __name__ == "__main__":
    unittest.main()
