import math
import unittest

from openbene_nav.model import Pose2D
from openbene_nav.pose import ArObservation, PoseEstimator

from tests.support import load_map, localize


class PoseEstimatorTests(unittest.TestCase):
    def setUp(self):
        self.map_data = load_map()

    def test_alignment_recovers_true_pose_for_any_ar_frame(self):
        # The AR world is rotated and shifted relative to the map frame, so the
        # alignment has to cancel that offset exactly.
        ar_from_map = Pose2D.from_deg(3.5, -2.0, 37.0)
        estimator = PoseEstimator(self.map_data)
        marker = self.map_data.marker("mk_junction")
        true_pose = Pose2D.from_deg(4.4, 0.35, 12.0)
        observation = ArObservation(
            marker_id="mk_junction",
            marker_in_ar=ar_from_map.compose(marker.pose),
            device_in_ar=ar_from_map.compose(true_pose),
        )
        pose = estimator.align(observation)
        self.assertTrue(estimator.aligned)
        self.assertAlmostEqual(pose.x, true_pose.x, places=9)
        self.assertAlmostEqual(pose.y, true_pose.y, places=9)
        self.assertAlmostEqual(pose.yaw_deg, true_pose.yaw_deg, places=9)
        self.assertEqual(estimator.drift_m, 0.0)
        self.assertEqual(estimator.last_marker_id, "mk_junction")

    def test_ar_updates_follow_the_aligned_frame(self):
        estimator = PoseEstimator(self.map_data)
        localize(self.map_data, estimator, "mk_entrance", Pose2D.from_deg(0.4, 0.1, 5.0))
        pose = estimator.update_from_ar(Pose2D.from_deg(0.9, 0.1, 5.0))
        self.assertAlmostEqual(pose.x, 0.9, places=9)
        self.assertAlmostEqual(pose.yaw_deg, 5.0, places=9)

    def test_update_from_ar_before_alignment_returns_none(self):
        estimator = PoseEstimator(self.map_data)
        self.assertIsNone(estimator.update_from_ar(Pose2D.from_deg(1.0, 0.0, 0.0)))

    def test_odometry_straight_line(self):
        estimator = PoseEstimator(self.map_data, wheel_base_m=0.30, wheel_radius_m=0.0325)
        localize(self.map_data, estimator, "mk_entrance", Pose2D.from_deg(0.0, 0.0, 0.0))
        circumference = 2.0 * math.pi * 0.0325
        rpm = 60.0 * 0.5 / circumference
        estimator.integrate_odometry(rpm, rpm, 1.0)
        self.assertAlmostEqual(estimator.pose.x, 0.5, places=6)
        self.assertAlmostEqual(estimator.pose.y, 0.0, places=6)
        self.assertAlmostEqual(estimator.drift_m, 0.5, places=6)

    def test_odometry_rotation_in_place(self):
        estimator = PoseEstimator(self.map_data, wheel_base_m=0.30, wheel_radius_m=0.0325)
        localize(self.map_data, estimator, "mk_entrance", Pose2D.from_deg(0.0, 0.0, 0.0))
        circumference = 2.0 * math.pi * 0.0325
        rpm = 60.0 * 0.15 / circumference
        estimator.integrate_odometry(-rpm, rpm, 1.0)
        self.assertAlmostEqual(estimator.pose.x, 0.0, places=6)
        self.assertAlmostEqual(estimator.pose.y, 0.0, places=6)
        self.assertAlmostEqual(estimator.pose.yaw_deg, math.degrees(0.3 / 0.30), places=3)

    def test_alignment_resets_drift(self):
        estimator = PoseEstimator(self.map_data)
        localize(self.map_data, estimator, "mk_entrance", Pose2D.from_deg(0.0, 0.0, 0.0))
        estimator.integrate_odometry(100.0, 100.0, 1.0)
        self.assertGreater(estimator.drift_m, 0.0)
        localize(self.map_data, estimator, "mk_junction", Pose2D.from_deg(5.0, 0.0, 0.0))
        self.assertEqual(estimator.drift_m, 0.0)

    def test_require_pose_raises_without_alignment(self):
        estimator = PoseEstimator(self.map_data)
        with self.assertRaises(RuntimeError):
            estimator.require_pose()

    def test_reset_clears_alignment(self):
        estimator = PoseEstimator(self.map_data)
        localize(self.map_data, estimator, "mk_entrance")
        estimator.reset()
        self.assertFalse(estimator.aligned)
        self.assertIsNone(estimator.pose)


if __name__ == "__main__":
    unittest.main()
