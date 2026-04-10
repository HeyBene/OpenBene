"""Pure helpers for projecting OpenBene depth images into 2D laser-style scans."""

from __future__ import annotations

from dataclasses import dataclass
import math
from statistics import median


@dataclass(frozen=True)
class CameraModel:
    """A pinhole camera model in pixel units."""

    width: int
    height: int
    fl_x: float
    fl_y: float
    cx: float
    cy: float


@dataclass(frozen=True)
class LaserScanProjection:
    """A laser-style horizontal scan projected from a depth image."""

    angle_min: float
    angle_max: float
    angle_increment: float
    ranges: tuple[float, ...]


def scale_camera_model(camera_model: CameraModel, *, target_width: int, target_height: int) -> CameraModel:
    """Scale RGB-space intrinsics into the pixel grid of another image size."""
    if camera_model.width <= 0 or camera_model.height <= 0:
        raise ValueError("Camera model width and height must be positive.")
    if target_width <= 0 or target_height <= 0:
        raise ValueError("Target width and height must be positive.")

    scale_x = target_width / camera_model.width
    scale_y = target_height / camera_model.height
    return CameraModel(
        width=target_width,
        height=target_height,
        fl_x=camera_model.fl_x * scale_x,
        fl_y=camera_model.fl_y * scale_y,
        cx=camera_model.cx * scale_x,
        cy=camera_model.cy * scale_y,
    )


def pixel_column_to_angle(column: int, camera_model: CameraModel) -> float:
    """Return the horizontal bearing angle for a pixel column."""
    if camera_model.fl_x <= 0:
        raise ValueError("Camera fl_x must be positive.")
    return math.atan2(float(column) - camera_model.cx, camera_model.fl_x)


def _image_shape(depth_image: object) -> tuple[int, int]:
    try:
        height = len(depth_image)  # type: ignore[arg-type]
    except TypeError as exc:
        raise ValueError("Depth image must be a 2D array-like object.") from exc

    if height == 0:
        raise ValueError("Depth image must not be empty.")

    first_row = depth_image[0]  # type: ignore[index]
    width = len(first_row)
    if width == 0:
        raise ValueError("Depth image rows must not be empty.")

    return height, width


def project_depth_image_to_laserscan(
    depth_image: object,
    camera_model: CameraModel,
    *,
    depth_scale: float = 1000.0,
    confidence_image: object | None = None,
    confidence_min_value: int = 0,
    band_center_ratio: float = 0.5,
    band_height: int = 5,
    range_min_m: float = 0.15,
    range_max_m: float = 5.0,
) -> LaserScanProjection:
    """Project a horizontal band of a depth image into a 2D laser-style scan."""
    if depth_scale <= 0:
        raise ValueError("depth_scale must be positive.")
    if confidence_min_value < 0:
        raise ValueError("confidence_min_value must be >= 0.")
    if not 0.0 <= band_center_ratio <= 1.0:
        raise ValueError("band_center_ratio must stay inside [0.0, 1.0].")
    if band_height <= 0:
        raise ValueError("band_height must be positive.")
    if range_min_m < 0 or range_max_m <= 0 or range_min_m >= range_max_m:
        raise ValueError("range_min_m and range_max_m must define a valid positive interval.")

    image_height, image_width = _image_shape(depth_image)
    if image_width != camera_model.width or image_height != camera_model.height:
        raise ValueError("Depth image shape must match the supplied camera model.")
    if confidence_image is not None:
        confidence_height, confidence_width = _image_shape(confidence_image)
        if confidence_width != image_width or confidence_height != image_height:
            raise ValueError("confidence_image shape must match depth_image shape.")

    center_row = int(round((image_height - 1) * band_center_ratio))
    half_band = band_height // 2
    row_start = max(0, center_row - half_band)
    row_stop = min(image_height, center_row + half_band + 1)

    ranges: list[float] = []
    for column in range(image_width):
        valid_depth_values: list[float] = []
        for row in range(row_start, row_stop):
            if confidence_image is not None and int(confidence_image[row][column]) < confidence_min_value:  # type: ignore[index]
                continue
            value = float(depth_image[row][column])  # type: ignore[index]
            if math.isfinite(value) and value > 0.0:
                valid_depth_values.append(value)

        if not valid_depth_values:
            ranges.append(float("inf"))
            continue

        depth_raw = float(median(valid_depth_values))
        depth_z_m = depth_raw / depth_scale
        angle = pixel_column_to_angle(column, camera_model)
        range_m = depth_z_m / math.cos(angle)

        if range_m < range_min_m or range_m > range_max_m:
            ranges.append(float("inf"))
        else:
            ranges.append(range_m)

    angle_min = pixel_column_to_angle(0, camera_model)
    angle_max = pixel_column_to_angle(image_width - 1, camera_model)
    angle_increment = 0.0 if image_width <= 1 else (angle_max - angle_min) / (image_width - 1)

    return LaserScanProjection(
        angle_min=angle_min,
        angle_max=angle_max,
        angle_increment=angle_increment,
        ranges=tuple(ranges),
    )
