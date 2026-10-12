"""Check the monocular marker pose against a synthetic pinhole camera.

    python shared/tools/verify_marker_math.py

The same algorithm is ported to Android (MarkerGeometry.kt) and iOS
(MarkerGeometry.swift). This script is the executable specification: it builds a
scene with a known camera pose and a known sheet pose, projects the four corners
of the printed code into pixels, and then lets the estimator recover the pose the
way the phone apps do. If the recovered pose matches the scene the port is
correct.
"""

from __future__ import annotations

import argparse
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "navcore"))

from openbene_nav.marker_math import (  # noqa: E402
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
from openbene_nav.model import Pose2D, wrap_rad  # noqa: E402

INTRINSICS = CameraIntrinsics(fx=1420.0, fy=1420.0, cx=960.0, cy=720.0, width=1920, height=1440)


def check(camera_height_m, camera_pitch_deg, camera_yaw_deg, distance_m, sheet_yaw_deg, use_floor_plane):
    camera = RigidTransform.from_yaw_pitch_roll(
        position=(0.0, camera_height_m, 0.0),
        yaw_deg=camera_yaw_deg,
        pitch_deg=camera_pitch_deg,
    )
    sheet = Pose2D(0.0, distance_m, math.radians(sheet_yaw_deg))
    pixels = project_corners(sheet_corners_world(sheet, 0.12), INTRINSICS, camera)
    if pixels is None:
        return None

    floor_y = 0.0 if use_floor_plane else None
    recovered = marker_pose_from_quad(
        pixels,
        INTRINSICS,
        camera,
        floor_y=floor_y,
        quad_size_m=0.12,
        centre_offset_along_y_m=0.0,
    )
    if recovered is None:
        return None

    height = solve_camera_height(pixels, INTRINSICS, camera, quad_size_m=0.12)
    return {
        "position_error_m": recovered.distance_to(sheet),
        "yaw_error_deg": math.degrees(abs(Pose2D_wrap(recovered.yaw_rad - sheet.yaw_rad))),
        "height_error_m": None if height is None else abs(height - camera_height_m),
        "device_yaw_deg": math.degrees(device_in_ar(camera).yaw_rad),
    }


def Pose2D_wrap(angle):
    from openbene_nav.model import wrap_rad

    return wrap_rad(angle)


def check_image_anchor():
    """ARCore and ARKit report the sheet pose directly; projecting it must give
    back the pose the map records, so the anchor fix and the QR fix agree."""

    worst_position = 0.0
    worst_yaw = 0.0
    for sheet_x in (-1.5, 0.0, 2.0):
        for sheet_y in (-0.5, 1.2):
            for sheet_yaw_deg in (-180.0, -90.0, -35.0, 0.0, 45.0, 90.0, 135.0, 180.0):
                sheet = Pose2D(sheet_x, sheet_y, math.radians(sheet_yaw_deg))
                recovered = marker_in_ar_from_image_pose(image_pose_of_sheet(sheet))
                worst_position = max(worst_position, recovered.distance_to(sheet))
                worst_yaw = max(
                    worst_yaw,
                    math.degrees(abs(wrap_rad(recovered.yaw_rad - sheet.yaw_rad))),
                )
    return worst_position, worst_yaw


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Verify the marker pose math")
    parser.parse_args(argv)

    print("camera: height / pitch / yaw, sheet: distance / yaw -> recovered pose error")
    print("")
    header = "{:>6} {:>7} {:>6} {:>8} {:>6} {:>6} {:>11} {:>9} {:>10}".format(
        "height", "pitch", "cyaw", "dist", "syaw", "floor", "pos err m", "yaw err", "height err"
    )
    print(header)
    print("-" * len(header))

    worst_position = 0.0
    worst_yaw = 0.0
    worst_height = 0.0
    for camera_height in (0.30, 0.40, 0.55):
        for pitch in (-45.0, -35.0, -25.0):
            for camera_yaw in (-30.0, 0.0, 30.0):
                for distance in (0.7, 1.2, 2.0):
                    for sheet_yaw in (0.0, 45.0, 90.0, 135.0):
                        for use_floor in (True, False):
                            result = check(camera_height, pitch, camera_yaw, distance, sheet_yaw, use_floor)
                            if result is None:
                                print("scene did not resolve: ", camera_height, pitch, camera_yaw, distance, sheet_yaw)
                                return 1
                            worst_position = max(worst_position, result["position_error_m"])
                            worst_yaw = max(worst_yaw, result["yaw_error_deg"])
                            if result["height_error_m"] is not None:
                                worst_height = max(worst_height, result["height_error_m"])
                            print(
                                "{:6.2f} {:7.1f} {:6.1f} {:8.2f} {:6.1f} {:>6} {:11.4f} {:9.4f} {:10.4f}".format(
                                    camera_height,
                                    pitch,
                                    camera_yaw,
                                    distance,
                                    sheet_yaw,
                                    "yes" if use_floor else "solved",
                                    result["position_error_m"],
                                    result["yaw_error_deg"],
                                    result["height_error_m"] or 0.0,
                                )
                            )

    print("")
    print("worst position error : {:.4f} m".format(worst_position))
    print("worst yaw error      : {:.4f} deg".format(worst_yaw))
    print("worst height error   : {:.4f} m".format(worst_height))

    anchor_position, anchor_yaw = check_image_anchor()
    print("image anchor round trip: {:.4f} m, {:.4f} deg".format(anchor_position, anchor_yaw))

    ok = (
        worst_position < 0.01
        and worst_yaw < 0.5
        and worst_height < 0.01
        and anchor_position < 1e-6
        and anchor_yaw < 1e-6
    )
    print("")
    print("result: " + ("ok" if ok else "out of tolerance"))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
