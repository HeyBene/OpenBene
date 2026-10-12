import unittest

from openbene_nav.harness import run_episode
from openbene_nav.model import Pose2D
from openbene_nav.router import Router
from openbene_nav.simulation import Obstacle, SimConfig

from tests.support import load_map


class EpisodeTests(unittest.TestCase):
    def setUp(self):
        self.map_data = load_map()
        self.router = Router(self.map_data)

    def test_full_episode_to_room_101(self):
        route = self.router.route_to_room("loc_entrance", "Room 101")
        result = run_episode(self.map_data, route, trace_every_s=5.0)
        self.assertTrue(result.arrived, result.report())
        self.assertEqual(result.used_markers, ["mk_entrance", "mk_junction", "mk_room101"])
        self.assertGreaterEqual(result.anchor_fixes, 3)
        self.assertLess(result.position_error_m, 0.25)
        self.assertLess(result.distance_to_goal_m, 0.6)

    def test_full_episode_to_room_102(self):
        route = self.router.route_to_room("loc_entrance", "Room 102")
        result = run_episode(self.map_data, route, trace_every_s=5.0)
        self.assertTrue(result.arrived, result.report())
        self.assertEqual(result.used_markers, ["mk_entrance", "mk_junction", "mk_room102"])
        self.assertLess(result.position_error_m, 0.25)

    def test_episode_is_reported_with_turn_by_turn_changes(self):
        route = self.router.route_to_room("loc_entrance", "Room 101")
        result = run_episode(self.map_data, route, trace_every_s=5.0)
        self.assertTrue(any("arrived" in change for change in result.state_changes))
        self.assertGreater(result.elapsed_s, 10.0)

    def test_episode_is_independent_of_the_ar_world_origin(self):
        route = self.router.route_to_room("loc_entrance", "Room 102")
        first = run_episode(
            self.map_data,
            route,
            trace_every_s=5.0,
            ar_from_map=Pose2D.from_deg(-12.0, 4.0, -115.0),
        )
        second = run_episode(
            self.map_data,
            route,
            trace_every_s=5.0,
            ar_from_map=Pose2D.from_deg(30.0, 30.0, 179.0),
        )
        self.assertTrue(first.arrived, first.report())
        self.assertTrue(second.arrived, second.report())
        self.assertAlmostEqual(first.travelled_m, second.travelled_m, delta=0.05)
        self.assertAlmostEqual(first.true_pose.x, second.true_pose.x, delta=0.05)
        self.assertAlmostEqual(first.true_pose.y, second.true_pose.y, delta=0.05)

    def test_obstacle_blocks_then_the_route_finishes(self):
        route = self.router.route_to_room("loc_entrance", "Room 101")
        result = run_episode(
            self.map_data,
            route,
            obstacles=[Obstacle(x=2.0, y=0.0, radius_m=0.30, clear_after_s=15.0)],
            trace_every_s=5.0,
        )
        self.assertTrue(result.arrived, result.report())
        states = [change.split(" -> ")[1].split(" ")[0] for change in result.state_changes]
        self.assertIn("blocked", states)

    def test_pose_error_stays_bounded_in_the_corridor(self):
        route = self.router.route_to_room("loc_entrance", "Room 102")
        result = run_episode(self.map_data, route, trace_every_s=1.0)
        self.assertTrue(result.arrived, result.report())
        worst = max(event.error_m for event in result.trace)
        self.assertLess(worst, 0.6)

    def test_noisy_markers_still_finish_the_route(self):
        route = self.router.route_to_room("loc_entrance", "Room 101")
        config = SimConfig(marker_noise_xy_m=0.06, marker_noise_yaw_deg=4.0)
        result = run_episode(self.map_data, route, sim_config=config, trace_every_s=5.0)
        self.assertTrue(result.arrived, result.report())
        self.assertLess(result.distance_to_goal_m, 0.6)


if __name__ == "__main__":
    unittest.main()
