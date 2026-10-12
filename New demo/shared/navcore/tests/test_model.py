import math
import unittest

from openbene_nav.model import Pose2D, wrap_deg, wrap_rad

from tests.support import load_map


class PoseTests(unittest.TestCase):
    def test_wrap_deg(self):
        self.assertAlmostEqual(wrap_deg(190.0), -170.0)
        self.assertAlmostEqual(wrap_deg(-190.0), 170.0)
        self.assertAlmostEqual(wrap_deg(45.0), 45.0)

    def test_wrap_rad(self):
        self.assertAlmostEqual(wrap_rad(math.radians(190.0)), math.radians(-170.0))

    def test_compose_and_inverse_round_trip(self):
        base = Pose2D.from_deg(2.0, -1.0, 35.0)
        child = Pose2D.from_deg(1.5, 0.25, -12.0)
        world = base.compose(child)
        recovered = base.inverse().compose(world)
        self.assertAlmostEqual(recovered.x, child.x, places=9)
        self.assertAlmostEqual(recovered.y, child.y, places=9)
        self.assertAlmostEqual(recovered.yaw_deg, child.yaw_deg, places=9)

    def test_translated_moves_along_heading(self):
        pose = Pose2D.from_deg(0.0, 0.0, 90.0)
        moved = pose.translated(2.0)
        self.assertAlmostEqual(moved.x, 0.0, places=9)
        self.assertAlmostEqual(moved.y, 2.0, places=9)

    def test_heading_error_is_signed(self):
        pose = Pose2D.from_deg(0.0, 0.0, 0.0)
        left = Pose2D.from_deg(0.0, 1.0, 0.0)
        right = Pose2D.from_deg(0.0, -1.0, 0.0)
        self.assertAlmostEqual(math.degrees(pose.heading_error_to(left)), 90.0)
        self.assertAlmostEqual(math.degrees(pose.heading_error_to(right)), -90.0)


class MapDataTests(unittest.TestCase):
    def setUp(self):
        self.map_data = load_map()

    def test_markers_locations_and_rooms(self):
        self.assertEqual(len(self.map_data.markers), 4)
        self.assertEqual(len(self.map_data.locations), 4)
        self.assertEqual(len(self.map_data.rooms), 2)
        self.assertEqual(self.map_data.marker("mk_junction").payload, "openbene:mk_junction")

    def test_marker_lookup_by_payload(self):
        marker = self.map_data.marker_for_payload("openbene:mk_room101")
        self.assertIsNotNone(marker)
        self.assertEqual(marker.id, "mk_room101")
        self.assertIsNone(self.map_data.marker_for_payload("nope"))

    def test_location_marker_binding(self):
        location = self.map_data.location("loc_junction")
        self.assertEqual(location.marker_id, "mk_junction")
        self.assertEqual(self.map_data.location_with_marker("mk_junction").id, "loc_junction")

    def test_edge_distance_and_orientation(self):
        edge = self.map_data.edges_from("loc_entrance")[0]
        self.assertEqual(edge.id, "e_entrance_junction")
        self.assertAlmostEqual(edge.distance_m(), 6.0)
        forward = edge.path_from("loc_entrance")
        backward = edge.path_from("loc_junction")
        self.assertAlmostEqual(forward[0].x, 0.0)
        self.assertAlmostEqual(backward[0].x, 6.0)
        self.assertEqual(edge.other_end("loc_entrance"), "loc_junction")

    def test_rooms_named_is_case_insensitive(self):
        self.assertEqual(len(self.map_data.rooms_named("room 101")), 1)
        self.assertEqual(self.map_data.room_names(), ["Room 101", "Room 102"])

    def test_nearest_location(self):
        nearest = self.map_data.nearest_location(Pose2D.from_deg(5.6, 3.7, 0.0))
        self.assertEqual(nearest.id, "loc_room101")


if __name__ == "__main__":
    unittest.main()
