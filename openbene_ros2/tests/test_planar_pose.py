import math
import sys
from pathlib import Path
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from openbene_ros2.planar_pose import planar_pose_from_opengl_camera_transform
from openbene_ros2.planar_pose import quaternion_from_yaw


class PlanarPoseTests(unittest.TestCase):
    def test_identity_pose_projects_to_origin_with_negative_half_pi_heading(self) -> None:
        pose = planar_pose_from_opengl_camera_transform(
            (
                (1.0, 0.0, 0.0, 0.0),
                (0.0, 1.0, 0.0, 0.0),
                (0.0, 0.0, 1.0, 0.0),
                (0.0, 0.0, 0.0, 1.0),
            )
        )

        self.assertAlmostEqual(pose.x, 0.0)
        self.assertAlmostEqual(pose.y, 0.0)
        self.assertAlmostEqual(pose.yaw, -math.pi / 2.0)

    def test_translation_and_yaw_are_projected_from_world_xz_plane(self) -> None:
        yaw = 0.3
        sin_yaw = math.sin(yaw)
        cos_yaw = math.cos(yaw)

        pose = planar_pose_from_opengl_camera_transform(
            (
                (sin_yaw, 0.0, -cos_yaw, 1.25),
                (0.0, 1.0, 0.0, 9.0),
                (-cos_yaw, 0.0, -sin_yaw, -2.5),
                (0.0, 0.0, 0.0, 1.0),
            )
        )

        self.assertAlmostEqual(pose.x, 1.25)
        self.assertAlmostEqual(pose.y, -2.5)
        self.assertAlmostEqual(pose.yaw, yaw)

    def test_quaternion_from_yaw_uses_ros_z_axis_rotation(self) -> None:
        qx, qy, qz, qw = quaternion_from_yaw(math.pi)
        self.assertAlmostEqual(qx, 0.0)
        self.assertAlmostEqual(qy, 0.0)
        self.assertAlmostEqual(qz, 1.0)
        self.assertAlmostEqual(qw, 0.0, places=6)


if __name__ == "__main__":
    unittest.main()
