import math
import unittest

from openbene_nav.executor import ExecutorConfig, ExecutorState
from openbene_nav.model import Pose2D
from openbene_nav.router import Router

from tests.support import build_executor, drive_to, load_map, localize


class ExecutorTests(unittest.TestCase):
    def setUp(self):
        self.map_data = load_map()
        self.router = Router(self.map_data)
        self.route = self.router.route_to_room("loc_entrance", "Room 101")

    def _start_localized(self, config=None):
        estimator, link, executor = build_executor(self.map_data, config)
        executor.start(self.route)
        localize(self.map_data, estimator, "mk_entrance", Pose2D.from_deg(0.0, 0.0, 0.0))
        executor.note_marker("mk_entrance")
        return estimator, link, executor

    def test_start_without_alignment_asks_for_marker_and_rotates(self):
        estimator, link, executor = build_executor(self.map_data)
        executor.start(self.route)
        self.assertEqual(executor.state, ExecutorState.NEED_ANCHOR)
        self.assertEqual(executor.expected_marker_id, "mk_entrance")
        executor.tick(0.05, 0.0)
        self.assertEqual(executor.state, ExecutorState.NEED_ANCHOR)
        self.assertAlmostEqual(link.last_command["left"], -link.last_command["right"])
        self.assertNotAlmostEqual(link.last_command["left"], 0.0)

    def test_scan_timeout_fails(self):
        config = ExecutorConfig(scan_timeout_s=2.0)
        estimator, link, executor = build_executor(self.map_data, config)
        executor.start(self.route)
        executor.tick(0.05, 0.0)
        executor.tick(0.05, 1.0)
        executor.tick(0.05, 3.0)
        self.assertEqual(executor.state, ExecutorState.FAILED)

    def test_marker_note_starts_driving(self):
        estimator, link, executor = self._start_localized()
        self.assertEqual(executor.state, ExecutorState.DRIVING)
        self.assertIn("mk_entrance", executor.used_markers)

    def test_waypoints_advance_as_the_pose_moves(self):
        estimator, link, executor = self._start_localized()
        self.assertEqual(executor.point_index, 0)
        drive_to(executor, estimator, [Pose2D.from_deg(0.0, 0.0, 0.0)])
        self.assertEqual(executor.point_index, 1)
        drive_to(executor, estimator, [Pose2D.from_deg(3.0, 0.0, 0.0)], start_time=0.1)
        self.assertEqual(executor.leg_index, 0)
        self.assertEqual(executor.point_index, 2)
        status = drive_to(executor, estimator, [Pose2D.from_deg(6.0, 0.0, 0.0)], start_time=0.2)
        self.assertEqual(status.state, ExecutorState.SCANNING)
        self.assertEqual(executor.point_index, 2)
        executor.note_marker("mk_junction")
        self.assertEqual(executor.leg_index, 1)
        self.assertEqual(executor.point_index, 0)

    def test_leg_end_without_marker_fix_scans_and_resumes(self):
        estimator, link, executor = self._start_localized()
        drive_to(
            executor,
            estimator,
            [
                Pose2D.from_deg(0.0, 0.0, 0.0),
                Pose2D.from_deg(3.0, 0.0, 0.0),
                Pose2D.from_deg(6.0, 0.0, 0.0),
            ],
        )
        self.assertEqual(executor.state, ExecutorState.SCANNING)
        self.assertEqual(executor.expected_marker_id, "mk_junction")
        executor.note_marker("mk_junction")
        self.assertEqual(executor.state, ExecutorState.DRIVING)
        self.assertEqual(executor.leg_index, 1)

    def test_marker_seen_on_the_way_avoids_the_scan(self):
        estimator, link, executor = self._start_localized()
        drive_to(executor, estimator, [Pose2D.from_deg(0.0, 0.0, 0.0)])
        localize(self.map_data, estimator, "mk_junction", Pose2D.from_deg(5.0, 0.0, 0.0))
        executor.note_marker("mk_junction")
        drive_to(
            executor,
            estimator,
            [Pose2D.from_deg(3.0, 0.0, 0.0), Pose2D.from_deg(6.0, 0.0, 0.0)],
            start_time=0.1,
        )
        self.assertEqual(executor.state, ExecutorState.DRIVING)
        self.assertEqual(executor.leg_index, 1)

    def test_obstacle_blocks_then_resumes(self):
        estimator, link, executor = self._start_localized()
        link.telemetry.sonar_cm = 20.0
        status = executor.tick(0.05, 0.0)
        self.assertEqual(status.state, ExecutorState.BLOCKED)
        self.assertAlmostEqual(link.last_command["left"], 0.0)
        link.telemetry.sonar_cm = 120.0
        status = executor.tick(0.05, 0.1)
        self.assertEqual(status.state, ExecutorState.DRIVING)

    def test_bumper_fails_the_route(self):
        estimator, link, executor = self._start_localized()
        link.telemetry.bumper = "7"
        status = executor.tick(0.05, 0.0)
        self.assertEqual(status.state, ExecutorState.FAILED)
        self.assertAlmostEqual(link.last_command["left"], 0.0)

    def test_drift_with_a_reachable_marker_requests_an_anchor(self):
        estimator, link, executor = self._start_localized()
        estimator.pose = Pose2D.from_deg(5.2, 0.0, 0.0)
        estimator.drift_m = 5.0
        status = executor.tick(0.05, 0.0)
        self.assertEqual(status.state, ExecutorState.NEED_ANCHOR)
        self.assertEqual(status.expected_marker_id, "mk_junction")

    def test_drift_far_from_markers_only_warns(self):
        estimator, link, executor = self._start_localized()
        estimator.pose = Pose2D.from_deg(3.0, 0.0, 0.0)
        estimator.drift_m = 5.0
        status = executor.tick(0.05, 0.0)
        self.assertEqual(status.state, ExecutorState.DRIVING)
        self.assertTrue(status.drift_warning)

    def test_steering_points_at_the_waypoint(self):
        estimator, link, executor = self._start_localized()
        drive_to(executor, estimator, [Pose2D.from_deg(0.0, 0.0, 0.0)])
        drive_to(executor, estimator, [Pose2D.from_deg(2.0, 0.0, 0.0)], start_time=0.1)
        command = link.last_command
        self.assertGreater(command["left"] + command["right"], 0.0)
        self.assertAlmostEqual(command["left"], command["right"], places=6)

    def test_turn_in_place_when_the_heading_is_off(self):
        estimator, link, executor = self._start_localized()
        drive_to(executor, estimator, [Pose2D.from_deg(0.0, 0.0, 0.0)])
        drive_to(
            executor,
            estimator,
            [Pose2D.from_deg(2.0, 0.0, -90.0)],
            start_time=0.1,
        )
        command = link.last_command
        self.assertAlmostEqual(command["left"], -command["right"], places=6)
        self.assertNotAlmostEqual(command["left"], 0.0)

    def test_arrival_stops_the_robot(self):
        estimator, link, executor = self._start_localized()
        drive_to(
            executor,
            estimator,
            [
                Pose2D.from_deg(0.0, 0.0, 0.0),
                Pose2D.from_deg(3.0, 0.0, 0.0),
                Pose2D.from_deg(6.0, 0.0, 0.0),
            ],
        )
        executor.note_marker("mk_junction")
        status = drive_to(
            executor,
            estimator,
            [
                Pose2D.from_deg(6.0, 0.0, 90.0),
                Pose2D.from_deg(6.0, 2.0, 90.0),
                Pose2D.from_deg(6.0, 4.0, 90.0),
            ],
            start_time=0.2,
        )
        self.assertEqual(status.state, ExecutorState.ARRIVED)
        self.assertAlmostEqual(link.last_command["left"], 0.0)
        self.assertIn("Room 101", status.message)

    def test_remaining_distance_shrinks(self):
        estimator, link, executor = self._start_localized()
        first = drive_to(executor, estimator, [Pose2D.from_deg(0.0, 0.0, 0.0)]).distance_remaining_m
        second = drive_to(
            executor, estimator, [Pose2D.from_deg(5.0, 0.0, 0.0)], start_time=0.1
        ).distance_remaining_m
        self.assertGreater(first, second)


if __name__ == "__main__":
    unittest.main()
