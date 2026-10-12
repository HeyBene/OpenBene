"""Tests for the follow (tracking) controller."""

import unittest

from openbene_nav.follow import FollowConfig, box_from_pixels, follow_command


class FollowTest(unittest.TestCase):

    def test_no_detection_stops(self):
        command = follow_command(None, FollowConfig(), None, 0.0)
        self.assertEqual((command.left, command.right), (0.0, 0.0))
        self.assertIn("searching", command.action)

    def test_lost_target_stops(self):
        command = follow_command(None, FollowConfig(), None, 3.0)
        self.assertEqual((command.left, command.right), (0.0, 0.0))
        self.assertIn("lost", command.action)

    def test_obstacle_stops_even_with_a_target(self):
        command = follow_command((0.5, 0.5, 0.2, 0.2), FollowConfig(), 30.0, 0.0)
        self.assertEqual((command.left, command.right), (0.0, 0.0))
        self.assertIn("obstacle", command.action)

    def test_turns_towards_the_target(self):
        right = follow_command((0.8, 0.5, 0.2, 0.6), FollowConfig())
        self.assertLess(right.left, 0.0)
        self.assertGreater(right.right, 0.0)
        self.assertIn("right", right.action)

        left = follow_command((0.2, 0.5, 0.2, 0.6), FollowConfig())
        self.assertGreater(left.left, 0.0)
        self.assertLess(left.right, 0.0)
        self.assertIn("left", left.action)

    def test_holds_distance_inside_the_deadband(self):
        command = follow_command((0.5, 0.5, 0.2, 0.55), FollowConfig())
        self.assertEqual((command.left, command.right), (0.0, 0.0))
        self.assertIn("holding", command.action)

    def test_backs_off_when_too_close(self):
        command = follow_command((0.5, 0.5, 0.4, 0.95), FollowConfig())
        self.assertEqual((command.left, command.right), (0.0, 0.0))
        self.assertIn("close", command.action)

    def test_drives_forward_when_far(self):
        command = follow_command((0.5, 0.5, 0.1, 0.2), FollowConfig())
        self.assertGreater(command.left, 0.0)
        self.assertGreater(command.right, 0.0)
        self.assertIn("closing", command.action)

    def test_steers_while_closing_in(self):
        command = follow_command((0.58, 0.5, 0.1, 0.2), FollowConfig())
        self.assertGreater(command.right, command.left)
        self.assertGreater(command.left, 0.0)

    def test_box_from_pixels_normalises(self):
        box = box_from_pixels(480.0, 360.0, 1440.0, 1080.0, 1920.0, 1440.0)
        self.assertAlmostEqual(box[0], 0.5, places=6)
        self.assertAlmostEqual(box[1], 0.5, places=6)
        self.assertAlmostEqual(box[2], 0.5, places=6)
        self.assertAlmostEqual(box[3], 0.5, places=6)


if __name__ == "__main__":
    unittest.main()
