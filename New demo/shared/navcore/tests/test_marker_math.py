"""Round-trip tests for the monocular marker pose used by the phone apps.

A synthetic pinhole camera looks at a printed sheet lying on the floor. The
corner pixels are projected from the true sheet pose, then handed to the
estimator exactly like ARCore/ML Kit and ARKit/Vision would, and the recovered
pose is compared with the pose that generated the scene.
"""

import math
import unittest

from openbene_nav.marker_math import (
    CameraIntrinsics,
    RigidTransform,
    device_in_ar,
    image_pose_of_sheet,
    marker_in_ar_from_image_pose,
    marker_pose_from_quad,
    project_corners,
    sheet_corners_world,
    solve_camera_height,
)
from openbene_nav.model import Pose2D, wrap_rad


def scene(
    camera_height_m=0.40,
    camera_pitch_deg=-35.0,
    camera_yaw_deg=0.0,
    sheet_distance_m=1.2,
    sheet_yaw_deg=90.0,
    sheet_size_m=0.12,
    lateral_m=0.0,
):
    """A camera looking down the -z axis at a sheet on the floor.

    By default the printed arrow points the same way the camera faces, which is
    how the demo sheets are taped down: the robot approaches along the arrow.
    """

    intrinsics = CameraIntrinsics(fx=1420.0, fy=1420.0, cx=960.0, cy=720.0, width=1920, height=1440)
    camera_pose = RigidTransform.from_yaw_pitch_roll(
        position=(lateral_m, camera_height_m, 0.0),
        yaw_deg=camera_yaw_deg,
        pitch_deg=camera_pitch_deg,
    )
    sheet = Pose2D(0.0, sheet_distance_m, math.radians(sheet_yaw_deg))
    corners_world = sheet_corners_world(sheet, sheet_size_m)
    pixels = project_corners(corners_world, intrinsics, camera_pose)
    if pixels is None:
        raise AssertionError("scene geometry does not project")
    return intrinsics, camera_pose, sheet, pixels


class MarkerMathTest(unittest.TestCase):

    def assert_pose_close(self, recovered, expected, yaw_tol_deg=1.5, position_tol_m=0.02):
        self.assertIsNotNone(recovered)
        self.assertLess(recovered.distance_to(expected), position_tol_m)
        error_deg = math.degrees(abs(wrap_rad(recovered.yaw_rad - expected.yaw_rad)))
        self.assertLess(error_deg, yaw_tol_deg)

    def test_known_floor_exact_round_trip(self):
        intrinsics, camera_pose, sheet, pixels = scene()
        recovered = marker_pose_from_quad(
            pixels,
            intrinsics,
            camera_pose,
            floor_y=0.0,
            centre_offset_along_y_m=0.0,
        )
        self.assert_pose_close(recovered, sheet)

    def test_floor_height_solved_from_printed_size(self):
        for camera_height in (0.30, 0.40, 0.55):
            for distance in (0.8, 1.2, 1.8):
                intrinsics, camera_pose, sheet, pixels = scene(
                    camera_height_m=camera_height,
                    sheet_distance_m=distance,
                )
                recovered = marker_pose_from_quad(
                    pixels,
                    intrinsics,
                    camera_pose,
                    quad_size_m=0.12,
                    assumed_height_m=0.40,
                    centre_offset_along_y_m=0.0,
                )
                self.assert_pose_close(recovered, sheet)

    def test_solved_height_matches_scene(self):
        intrinsics, camera_pose, _, pixels = scene(camera_height_m=0.55, sheet_distance_m=1.5)
        height = solve_camera_height(pixels, intrinsics, camera_pose, quad_size_m=0.12)
        self.assertIsNotNone(height)
        self.assertAlmostEqual(height, 0.55, delta=0.01)

    def test_sheet_rotation_is_recovered(self):
        for sheet_yaw in (-90.0, -45.0, 0.0, 30.0, 90.0):
            intrinsics, camera_pose, sheet, pixels = scene(sheet_yaw_deg=sheet_yaw)
            recovered = marker_pose_from_quad(
                pixels,
                intrinsics,
                camera_pose,
                floor_y=0.0,
                centre_offset_along_y_m=0.0,
            )
            self.assert_pose_close(recovered, sheet, yaw_tol_deg=3.0)

    def test_small_heading_offset_passes_the_gate(self):
        intrinsics, camera_pose, sheet, pixels = scene(sheet_yaw_deg=110.0)
        recovered = marker_pose_from_quad(
            pixels,
            intrinsics,
            camera_pose,
            floor_y=0.0,
            centre_offset_along_y_m=0.0,
            device_yaw_rad=device_in_ar(camera_pose).yaw_rad,
        )
        self.assert_pose_close(recovered, sheet, yaw_tol_deg=3.0)

    def test_unordered_corners_use_device_heading(self):
        intrinsics, camera_pose, _, pixels = scene(camera_yaw_deg=0.0, sheet_yaw_deg=0.0)
        recovered = marker_pose_from_quad(
            pixels,
            intrinsics,
            camera_pose,
            floor_y=0.0,
            ordered=False,
            device_yaw_rad=device_in_ar(camera_pose).yaw_rad,
            centre_offset_along_y_m=0.0,
        )
        self.assertIsNotNone(recovered)
        self.assertAlmostEqual(
            math.degrees(recovered.yaw_rad),
            math.degrees(device_in_ar(camera_pose).yaw_rad),
            delta=1e-6,
        )

    def test_yaw_gate_rejects_wrong_corner_order(self):
        intrinsics, camera_pose, _, pixels = scene()
        rotated = [pixels[1], pixels[2], pixels[3], pixels[0]]  # corner list rotated by 90 deg
        device_yaw = device_in_ar(camera_pose).yaw_rad
        recovered = marker_pose_from_quad(
            rotated,
            intrinsics,
            camera_pose,
            floor_y=0.0,
            device_yaw_rad=device_yaw,
            centre_offset_along_y_m=0.0,
        )
        self.assertIsNotNone(recovered)
        self.assertAlmostEqual(recovered.yaw_rad, device_yaw, places=6)

    def test_marker_centre_offset_follows_the_arrow(self):
        intrinsics, camera_pose, sheet, pixels = scene(sheet_yaw_deg=0.0)
        centred = marker_pose_from_quad(
            pixels, intrinsics, camera_pose, floor_y=0.0, centre_offset_along_y_m=0.0
        )
        shifted = marker_pose_from_quad(
            pixels, intrinsics, camera_pose, floor_y=0.0, centre_offset_along_y_m=-0.0033
        )
        self.assert_pose_close(centred, sheet)
        # the arrow points along planar +x for yaw = 0, so the sheet centre sits
        # 3.3 mm behind the detected code centre
        self.assertAlmostEqual(shifted.x, centred.x - 0.0033, delta=1e-9)
        self.assertAlmostEqual(shifted.y, centred.y, delta=1e-9)

    def test_device_pose_uses_horizontal_heading(self):
        for camera_yaw in (-40.0, 0.0, 25.0):
            _, camera_pose, _, _ = scene(camera_yaw_deg=camera_yaw, camera_pitch_deg=-30.0)
            planar = device_in_ar(camera_pose)
            # pitch must not leak into the planar pose
            self.assertAlmostEqual(planar.x, 0.0, delta=1e-6)
            self.assertAlmostEqual(planar.y, 0.0, delta=1e-6)
            self.assertAlmostEqual(planar.yaw_deg, 90.0 + camera_yaw, delta=1e-6)

    def test_image_anchor_round_trip(self):
        for sheet_yaw in (-180.0, -135.0, -90.0, -45.0, 0.0, 30.0, 90.0, 180.0):
            sheet = Pose2D(0.4, 1.1, math.radians(sheet_yaw))
            recovered = marker_in_ar_from_image_pose(image_pose_of_sheet(sheet, floor_y=0.0))
            self.assertAlmostEqual(recovered.x, sheet.x, places=9)
            self.assertAlmostEqual(recovered.y, sheet.y, places=9)
            self.assertAlmostEqual(
                math.degrees(wrap_rad(recovered.yaw_rad - sheet.yaw_rad)), 0.0, places=6
            )

    def test_image_anchor_normal_points_up(self):
        anchor = image_pose_of_sheet(Pose2D(0.0, 0.0, math.radians(20.0)), floor_y=0.3)
        normal = anchor.rotate((0.0, 1.0, 0.0))
        self.assertAlmostEqual(normal[0], 0.0, places=9)
        self.assertAlmostEqual(normal[1], 1.0, places=9)
        self.assertAlmostEqual(normal[2], 0.0, places=9)
        self.assertAlmostEqual(anchor.y, 0.3, places=9)

    def test_image_anchor_axes_match_the_qr_corner_order(self):
        # The anchor's local +X is the image +x axis and its local +Z runs from
        # the top edge to the bottom edge, which is the corner order the QR path
        # assumes: top left, top right, bottom right, bottom left.
        sheet = Pose2D(0.7, -0.4, math.radians(20.0))
        anchor = image_pose_of_sheet(sheet, floor_y=0.0)
        half = 0.06
        corners = sheet_corners_world(sheet, 0.12)
        for local, expected in zip(
            ((-half, 0.0, -half), (half, 0.0, -half), (half, 0.0, half), (-half, 0.0, half)),
            corners,
        ):
            actual = anchor.transform_point(local)
            for index in range(3):
                self.assertAlmostEqual(actual[index], expected[index], places=9)

    def test_image_anchor_and_qr_paths_agree(self):
        # The two fixes the apps can produce for one sheet must land on one pose.
        intrinsics, camera_pose, sheet, pixels = scene(sheet_yaw_deg=35.0)
        from_quad = marker_pose_from_quad(
            pixels, intrinsics, camera_pose, floor_y=0.0, centre_offset_along_y_m=0.0
        )
        from_anchor = marker_in_ar_from_image_pose(image_pose_of_sheet(sheet, floor_y=0.0))
        self.assert_pose_close(from_quad, sheet)
        self.assert_pose_close(from_anchor, sheet)
        self.assertLess(from_quad.distance_to(from_anchor), 0.02)
        self.assertLess(
            math.degrees(abs(wrap_rad(from_quad.yaw_rad - from_anchor.yaw_rad))), 1.5
        )


if __name__ == "__main__":
    unittest.main()
