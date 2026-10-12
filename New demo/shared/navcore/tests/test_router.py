import unittest

from openbene_nav.model import MapData
from openbene_nav.router import Router

from tests.support import load_map


class RouterTests(unittest.TestCase):
    def setUp(self):
        self.map_data = load_map()
        self.router = Router(self.map_data)

    def test_route_to_room_101(self):
        route = self.router.route_to_room("loc_entrance", "Room 101")
        self.assertIsNotNone(route)
        self.assertEqual(route.location_sequence(), ["loc_entrance", "loc_junction", "loc_room101"])
        self.assertAlmostEqual(route.total_distance_m, 10.0)
        self.assertEqual(len(route.legs), 2)
        self.assertEqual(route.room.id, "room_101")

    def test_route_to_room_102(self):
        route = self.router.route_to_room("loc_entrance", "Room 102")
        self.assertEqual(route.location_sequence(), ["loc_entrance", "loc_junction", "loc_room102"])
        self.assertAlmostEqual(route.total_distance_m, 12.0)

    def test_route_from_room_to_room(self):
        route = self.router.route_to_room("loc_room101", "Room 102")
        self.assertEqual(route.location_sequence(), ["loc_room101", "loc_junction", "loc_room102"])
        self.assertAlmostEqual(route.total_distance_m, 10.0)

    def test_same_location_route_is_empty(self):
        route = self.router.route_to_location("loc_room101", "loc_room101")
        self.assertEqual(route.legs, ())
        self.assertAlmostEqual(route.total_distance_m, 0.0)
        self.assertEqual(len(route.polyline), 1)

    def test_unknown_room_returns_none(self):
        self.assertIsNone(self.router.route_to_room("loc_entrance", "Room 999"))

    def test_unknown_location_raises(self):
        with self.assertRaises(KeyError):
            self.router.route_to_location("loc_nope", "loc_entrance")

    def test_unreachable_location_returns_none(self):
        raw = {
            "map_id": "two_islands",
            "locations": [
                {"id": "a", "pose": {"x": 0, "y": 0}},
                {"id": "b", "pose": {"x": 5, "y": 0}},
            ],
            "edges": [],
            "rooms": [],
            "markers": [],
        }
        router = Router(MapData.from_dict(raw))
        self.assertIsNone(router.route_to_location("a", "b"))

    def test_closest_of_several_rooms_with_same_name(self):
        raw = {
            "map_id": "two_wcs",
            "locations": [
                {"id": "start", "pose": {"x": 0, "y": 0}},
                {"id": "near", "pose": {"x": 1, "y": 0}},
                {"id": "far", "pose": {"x": 20, "y": 0}},
            ],
            "edges": [
                {"id": "e1", "from": "start", "to": "near", "path": [{"x": 0, "y": 0}, {"x": 1, "y": 0}]},
                {"id": "e2", "from": "near", "to": "far", "path": [{"x": 1, "y": 0}, {"x": 20, "y": 0}]},
            ],
            "rooms": [
                {"id": "wc_far", "name": "WC", "location_id": "far"},
                {"id": "wc_near", "name": "WC", "location_id": "near"},
            ],
            "markers": [],
        }
        route = Router(MapData.from_dict(raw)).route_to_room("start", "WC")
        self.assertEqual(route.destination_location_id, "near")
        self.assertAlmostEqual(route.total_distance_m, 1.0)


if __name__ == "__main__":
    unittest.main()
