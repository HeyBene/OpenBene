"""Pose of a floor marker from camera pixels, shared by both demo apps.

The AR sessions (ARCore on Android, ARKit on iOS) give the camera pose in an
arbitrary, gravity aligned world frame: y points up, the horizontal plane is the
floor. When the image tracker only reports the marker identity (QR fallback) the
marker pose still has to be recovered, and this module does it from the four
detected corners:

* every corner pixel is turned into a camera space ray with the pinhole model;
* the rays are rotated into the AR world frame with the camera transform;
* each ray is intersected with the floor plane, which yields the marker quad in
  world coordinates;
* the quad gives the marker centre and the marker image +y axis, and both are
  projected onto the horizontal plane exactly like the image tracker poses.

The floor height is normally taken from the detected AR plane. Without a plane
the known physical size of the printed code is used to solve the camera height:
intersecting the rays with a guessed plane scales the quad linearly, so one
measurement corrects the guess.

The image trackers do not need that recovery step: ARCore and ARKit both report
the sheet pose directly. ``marker_in_ar_from_image_pose`` only projects that pose
onto the floor plane so both fixes feed the estimator in the same form.

``OpenBotAnchorNav/MarkerGeometry.kt`` (Kotlin) and ``MarkerGeometry.swift``
(Swift) are ports of this file; keep the three in step.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Iterable, List, Optional, Sequence, Tuple

from .model import Pose2D, wrap_rad

Vec3 = Tuple[float, float, float]
Mat3 = Tuple[float, float, float, float, float, float, float, float, float]


@dataclass(frozen=True)
class CameraIntrinsics:
    """Pinhole intrinsics of one camera image, in pixels."""

    fx: float
    fy: float
    cx: float
    cy: float
    width: int
    height: int

    @staticmethod
    def from_horizontal_fov(width: int, height: int, hfov_deg: float = 60.0) -> "CameraIntrinsics":
        """Fallback intrinsics when the AR session cannot report them."""

        focal = (0.5 * float(width)) / math.tan(math.radians(hfov_deg) * 0.5)
        return CameraIntrinsics(focal, focal, 0.5 * float(width), 0.5 * float(height), int(width), int(height))


@dataclass(frozen=True)
class RigidTransform:
    """Position plus a row-major 3x3 rotation, the camera pose in AR space."""

    x: float
    y: float
    z: float
    rotation: Mat3

    @staticmethod
    def from_yaw_pitch_roll(
        position: Vec3,
        yaw_deg: float = 0.0,
        pitch_deg: float = 0.0,
        roll_deg: float = 0.0,
    ) -> "RigidTransform":
        """Helper for tests and simulations: R = Ry(yaw) * Rx(pitch) * Rz(roll)."""

        yaw = math.radians(yaw_deg)
        pitch = math.radians(pitch_deg)
        roll = math.radians(roll_deg)
        cy, sy = math.cos(yaw), math.sin(yaw)
        cp, sp = math.cos(pitch), math.sin(pitch)
        cr, sr = math.cos(roll), math.sin(roll)

        # Ry(yaw)
        ry = (cy, 0.0, sy, 0.0, 1.0, 0.0, -sy, 0.0, cy)
        # Rx(pitch)
        rx = (1.0, 0.0, 0.0, 0.0, cp, -sp, 0.0, sp, cp)
        # Rz(roll)
        rz = (cr, -sr, 0.0, sr, cr, 0.0, 0.0, 0.0, 1.0)
        return RigidTransform(position[0], position[1], position[2], mat3_mul(mat3_mul(ry, rx), rz))

    @property
    def position(self) -> Vec3:
        return (self.x, self.y, self.z)

    def rotate(self, vector: Vec3) -> Vec3:
        return mat3_apply(self.rotation, vector)

    def transform_point(self, point: Vec3) -> Vec3:
        rotated = self.rotate(point)
        return (rotated[0] + self.x, rotated[1] + self.y, rotated[2] + self.z)


def mat3_mul(left: Mat3, right: Mat3) -> Mat3:
    out: List[float] = []
    for row in range(3):
        for column in range(3):
            out.append(sum(left[row * 3 + k] * right[k * 3 + column] for k in range(3)))
    return tuple(out)  # type: ignore[return-value]


def mat3_apply(matrix: Mat3, vector: Vec3) -> Vec3:
    x, y, z = vector
    return (
        matrix[0] * x + matrix[1] * y + matrix[2] * z,
        matrix[3] * x + matrix[4] * y + matrix[5] * z,
        matrix[6] * x + matrix[7] * y + matrix[8] * z,
    )


def normalize(vector: Vec3) -> Vec3:
    length = math.sqrt(vector[0] ** 2 + vector[1] ** 2 + vector[2] ** 2)
    if length <= 1e-9:
        raise ValueError("cannot normalize a zero vector")
    return (vector[0] / length, vector[1] / length, vector[2] / length)


def pixel_ray(intrinsics: CameraIntrinsics, u: float, v: float) -> Vec3:
    """Camera space direction of a pixel; the camera looks down its own -z axis."""

    return normalize(((u - intrinsics.cx) / intrinsics.fx, -(v - intrinsics.cy) / intrinsics.fy, -1.0))


def project_point(intrinsics: CameraIntrinsics, camera_point: Vec3) -> Optional[Tuple[float, float]]:
    """Inverse of pixel_ray, used by the tests and the simulator."""

    depth = -camera_point[2]
    if depth <= 1e-6:
        return None
    return (
        intrinsics.cx + intrinsics.fx * camera_point[0] / depth,
        intrinsics.cy - intrinsics.fy * camera_point[1] / depth,
    )


def intersect_floor(origin: Vec3, direction: Vec3, floor_y: float) -> Optional[Vec3]:
    """Intersect a ray with the horizontal plane at floor_y."""

    if direction[1] > -1e-3:
        return None
    distance = (floor_y - origin[1]) / direction[1]
    if distance <= 0.0:
        return None
    return (
        origin[0] + distance * direction[0],
        origin[1] + distance * direction[1],
        origin[2] + distance * direction[2],
    )


def quad_on_floor(
    corners: Sequence[Tuple[float, float]],
    intrinsics: CameraIntrinsics,
    camera_pose: RigidTransform,
    floor_y: float,
) -> Optional[List[Vec3]]:
    """Project the four detected corners onto the floor plane."""

    quad: List[Vec3] = []
    for u, v in corners:
        ray = camera_pose.rotate(pixel_ray(intrinsics, u, v))
        hit = intersect_floor(camera_pose.position, ray, floor_y)
        if hit is None:
            return None
        quad.append(hit)
    return quad


def mean_edge_length(quad: Sequence[Vec3]) -> float:
    total = 0.0
    count = 0
    for index in range(len(quad)):
        first = quad[index]
        second = quad[(index + 1) % len(quad)]
        total += math.dist(first, second)
        count += 1
    return total / count if count else 0.0


def planar_yaw_of_direction(direction: Vec3) -> float:
    """Heading of a world direction in the AR plane frame (x = world x, y = -world z)."""

    return math.atan2(-direction[2], direction[0])


def planar_pose_of_point(position: Vec3, yaw_rad: float) -> Pose2D:
    return Pose2D(position[0], -position[2], wrap_rad(yaw_rad))


def image_pose_of_sheet(sheet: Pose2D, floor_y: float = 0.0) -> RigidTransform:
    """The pose an AR image tracker reports for a floor sheet, for the tests.

    ARCore (``AugmentedImage.getCenterPose``) and ARKit (``ARImageAnchor``)
    describe a tracked print the same way: the print lies in the pose's local
    X-Z plane, +X runs from the left edge of the print to its right edge, +Y is
    the sheet normal pointing up out of the floor, and +Z runs from the top edge
    of the print to its bottom edge. The printed arrow is the image +y axis, so
    it is the local -Z axis.
    """

    cos_y = math.cos(sheet.yaw_rad)
    sin_y = math.sin(sheet.yaw_rad)
    # The columns of the rotation are the world images of the local X, Y and Z
    # axes; the tuple itself is row major, so it is written row by row.
    right = (sin_y, 0.0, cos_y)
    normal = (0.0, 1.0, 0.0)
    down = (-cos_y, 0.0, sin_y)
    rotation: Mat3 = (
        right[0], normal[0], down[0],
        right[1], normal[1], down[1],
        right[2], normal[2], down[2],
    )
    return RigidTransform(sheet.x, floor_y, -sheet.y, rotation)


def marker_in_ar_from_image_pose(image_pose: RigidTransform) -> Pose2D:
    """Planar marker pose from an AR image-anchor pose.

    The printed arrow is the pose's local -Z axis and the sheet centre is the
    pose translation; see [image_pose_of_sheet] for the axis convention. Only
    the horizontal projection is kept, exactly like the QR path.
    """

    arrow = image_pose.rotate((0.0, 0.0, -1.0))
    horizontal = (arrow[0], 0.0, arrow[2])
    if math.hypot(horizontal[0], horizontal[2]) < 1e-6:
        yaw = 0.0
    else:
        yaw = planar_yaw_of_direction(horizontal)
    return planar_pose_of_point(image_pose.position, yaw)


def device_in_ar(camera_pose: RigidTransform) -> Pose2D:
    """Planar pose of the camera: position plus the heading of its view axis."""

    forward = camera_pose.rotate((0.0, 0.0, -1.0))
    horizontal = (forward[0], 0.0, forward[2])
    if math.hypot(horizontal[0], horizontal[2]) < 1e-6:
        yaw = 0.0
    else:
        yaw = planar_yaw_of_direction(horizontal)
    return planar_pose_of_point(camera_pose.position, yaw)


def solve_camera_height(
    corners: Sequence[Tuple[float, float]],
    intrinsics: CameraIntrinsics,
    camera_pose: RigidTransform,
    quad_size_m: float,
    assumed_height_m: float = 0.40,
    iterations: int = 3,
) -> Optional[float]:
    """Camera height above the floor, solved from the printed size of the code.

    Intersecting the corner rays with a plane at the guessed height scales the
    quad linearly, so the ratio between the printed and the measured edge length
    corrects the guess in one step; the extra iterations only absorb noise.
    """

    height = assumed_height_m
    for _ in range(max(1, iterations)):
        quad = quad_on_floor(corners, intrinsics, camera_pose, camera_pose.position[1] - height)
        if quad is None:
            return None
        measured = mean_edge_length(quad)
        if measured <= 1e-6:
            return None
        height = height * (quad_size_m / measured)
        if height <= 0.02 or height > 3.0:
            return None
    return height


def marker_pose_from_quad(
    corners: Sequence[Tuple[float, float]],
    intrinsics: CameraIntrinsics,
    camera_pose: RigidTransform,
    floor_y: Optional[float] = None,
    quad_size_m: float = 0.12,
    assumed_height_m: float = 0.40,
    centre_offset_along_y_m: float = -0.0033,
    ordered: bool = True,
    device_yaw_rad: Optional[float] = None,
    yaw_gate_deg: float = 60.0,
) -> Optional[Pose2D]:
    """Marker pose in the AR plane frame, from four detected corner pixels.

    corners is expected clockwise from the top-left corner of the code as
    printed, which is what ML Kit returns and what Vision returns for QR
    symbols. When the corner order is not trusted (ordered=False) the heading is
    taken from device_yaw_rad instead: on this demo the robot always rotates to
    face the marker before it scans, so the device heading is a usable stand-in.
    """

    if len(corners) != 4:
        return None

    if floor_y is None:
        height = solve_camera_height(corners, intrinsics, camera_pose, quad_size_m, assumed_height_m)
        if height is None:
            height = assumed_height_m
        floor_y = camera_pose.position[1] - height

    quad = quad_on_floor(corners, intrinsics, camera_pose, floor_y)
    if quad is None:
        return None

    centre = (
        sum(point[0] for point in quad) / 4.0,
        sum(point[1] for point in quad) / 4.0,
        sum(point[2] for point in quad) / 4.0,
    )

    if ordered:
        top_mid = midpoint(quad[0], quad[1])
        bottom_mid = midpoint(quad[3], quad[2])
        up = (top_mid[0] - bottom_mid[0], top_mid[1] - bottom_mid[1], top_mid[2] - bottom_mid[2])
        if math.hypot(up[0], up[2]) < 1e-6:
            return None
        yaw = planar_yaw_of_direction((up[0], 0.0, up[2]))
        if device_yaw_rad is not None and abs(wrap_rad(yaw - device_yaw_rad)) > math.radians(yaw_gate_deg):
            yaw = device_yaw_rad
    else:
        if device_yaw_rad is None:
            return None
        yaw = device_yaw_rad

    centre = (
        centre[0] + centre_offset_along_y_m * math.cos(yaw),
        centre[1],
        centre[2] - centre_offset_along_y_m * math.sin(yaw),
    )
    return planar_pose_of_point(centre, yaw)


def midpoint(first: Vec3, second: Vec3) -> Vec3:
    return ((first[0] + second[0]) * 0.5, (first[1] + second[1]) * 0.5, (first[2] + second[2]) * 0.5)


def project_corners(
    corners_world: Iterable[Vec3],
    intrinsics: CameraIntrinsics,
    camera_pose: RigidTransform,
) -> Optional[List[Tuple[float, float]]]:
    """World points to pixels; the inverse of the estimator, used by the tests."""

    pixels: List[Tuple[float, float]] = []
    for point in corners_world:
        # camera space: rotate by R^T (P - t)
        delta = (
            point[0] - camera_pose.x,
            point[1] - camera_pose.y,
            point[2] - camera_pose.z,
        )
        rotation = camera_pose.rotation
        camera_point = (
            rotation[0] * delta[0] + rotation[3] * delta[1] + rotation[6] * delta[2],
            rotation[1] * delta[0] + rotation[4] * delta[1] + rotation[7] * delta[2],
            rotation[2] * delta[0] + rotation[5] * delta[1] + rotation[8] * delta[2],
        )
        pixel = project_point(intrinsics, camera_point)
        if pixel is None:
            return None
        pixels.append(pixel)
    return pixels


def sheet_corners_world(sheet_pose: Pose2D, size_m: float) -> List[Vec3]:
    """The four corners of a floor sheet, in the world frame of the tests.

    The planar pose is lifted back into the world frame used by the AR sessions:
    world x = planar x, world z = -planar y, floor at y = 0. Corner order is the
    code order: top-left, top-right, bottom-right, bottom-left.

    ``sheet_pose.yaw_rad`` is the direction of the printed arrow, which is the
    sheet frame +y axis (map convention), so local coordinates map to the map
    frame as ``local y -> (cos yaw, sin yaw)`` and ``local x -> (sin yaw, -cos yaw)``.
    """

    half = size_m * 0.5
    cos_y = math.cos(sheet_pose.yaw_rad)
    sin_y = math.sin(sheet_pose.yaw_rad)
    corners: List[Vec3] = []
    for local_x, local_y in ((-half, half), (half, half), (half, -half), (-half, -half)):
        planar_x = sheet_pose.x + sin_y * local_x + cos_y * local_y
        planar_y = sheet_pose.y - cos_y * local_x + sin_y * local_y
        corners.append((planar_x, 0.0, -planar_y))
    return corners


def world_from_planar(pose: Pose2D) -> Vec3:
    """A planar pose as a world point, for the tests."""

    return (pose.x, 0.0, -pose.y)
