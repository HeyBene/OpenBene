import math
import sys
from pathlib import Path
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from openbene_ros2.depth_scan import CameraModel
from openbene_ros2.depth_scan import pixel_column_to_angle
from openbene_ros2.depth_scan import project_depth_image_to_laserscan
from openbene_ros2.depth_scan import scale_camera_model


class DepthScanTests(unittest.TestCase):
    def test_scale_camera_model_scales_intrinsics(self) -> None:
        scaled = scale_camera_model(
            CameraModel(width=1920, height=1440, fl_x=1000.0, fl_y=900.0, cx=960.0, cy=720.0),
            target_width=256,
            target_height=192,
        )
        self.assertAlmostEqual(scaled.fl_x, 133.3333333333)
        self.assertAlmostEqual(scaled.fl_y, 120.0)
        self.assertAlmostEqual(scaled.cx, 128.0)
        self.assertAlmostEqual(scaled.cy, 96.0)

    def test_flat_depth_image_projects_center_column_to_forward_range(self) -> None:
        camera = CameraModel(width=5, height=3, fl_x=2.0, fl_y=2.0, cx=2.0, cy=1.0)
        depth_image = [
            [2000, 2000, 2000, 2000, 2000],
            [2000, 2000, 2000, 2000, 2000],
            [2000, 2000, 2000, 2000, 2000],
        ]

        projection = project_depth_image_to_laserscan(
            depth_image,
            camera,
            depth_scale=1000.0,
            band_center_ratio=0.5,
            band_height=1,
            range_min_m=0.1,
            range_max_m=10.0,
        )

        self.assertAlmostEqual(projection.ranges[2], 2.0)
        self.assertGreater(projection.ranges[0], projection.ranges[2])
        self.assertAlmostEqual(projection.angle_min, pixel_column_to_angle(0, camera))
        self.assertAlmostEqual(projection.angle_max, pixel_column_to_angle(4, camera))

    def test_invalid_depth_values_become_infinite_ranges(self) -> None:
        camera = CameraModel(width=4, height=3, fl_x=4.0, fl_y=4.0, cx=1.5, cy=1.0)
        depth_image = [
            [0, 0, 0, 0],
            [1000, 0, 2000, 0],
            [0, 0, 0, 0],
        ]

        projection = project_depth_image_to_laserscan(
            depth_image,
            camera,
            depth_scale=1000.0,
            band_center_ratio=0.5,
            band_height=1,
            range_min_m=0.1,
            range_max_m=10.0,
        )

        self.assertTrue(math.isinf(projection.ranges[1]))
        self.assertTrue(math.isinf(projection.ranges[3]))
        self.assertAlmostEqual(projection.ranges[0], 1.0680004682)
        self.assertAlmostEqual(projection.ranges[2], 2.0155644371)

    def test_confidence_filter_removes_low_confidence_depth(self) -> None:
        camera = CameraModel(width=3, height=3, fl_x=3.0, fl_y=3.0, cx=1.0, cy=1.0)
        depth_image = [
            [1000, 1000, 1000],
            [1000, 1000, 1000],
            [1000, 1000, 1000],
        ]
        confidence_image = [
            [2, 2, 2],
            [0, 2, 2],
            [2, 2, 2],
        ]

        projection = project_depth_image_to_laserscan(
            depth_image,
            camera,
            depth_scale=1000.0,
            confidence_image=confidence_image,
            confidence_min_value=1,
            band_center_ratio=0.5,
            band_height=1,
            range_min_m=0.1,
            range_max_m=5.0,
        )

        self.assertTrue(math.isinf(projection.ranges[0]))
        self.assertFalse(math.isinf(projection.ranges[1]))


if __name__ == "__main__":
    unittest.main()
