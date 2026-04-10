import sys
from pathlib import Path
import tempfile
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
if str(PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(PACKAGE_ROOT))

from openbene_ros2.map_doctor import build_map_report


def _write_text_map(path: Path, rows: list[list[int]]) -> None:
    height = len(rows)
    width = len(rows[0]) if rows else 0
    body = "\n".join(" ".join(str(value) for value in row) for row in rows)
    path.write_text(f"P2\n{width} {height}\n255\n{body}\n", encoding="ascii")


class MapDoctorTests(unittest.TestCase):
    def test_good_map_reports_healthy(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            image_path = temp_path / "openbene_map.pgm"
            yaml_path = temp_path / "openbene_map.yaml"

            rows: list[list[int]] = []
            for y in range(40):
                row: list[int] = []
                for x in range(40):
                    if x in {0, 39} or y in {0, 39}:
                        row.append(0)
                    else:
                        row.append(254)
                rows.append(row)

            _write_text_map(image_path, rows)
            yaml_path.write_text(
                "\n".join(
                    [
                        "image: openbene_map.pgm",
                        "resolution: 0.05",
                        "origin: [-1.0, -1.0, 0.0]",
                        "negate: 0",
                        "occupied_thresh: 0.65",
                        "free_thresh: 0.25",
                        "mode: trinary",
                    ]
                ),
                encoding="utf-8",
            )

            report = "\n".join(build_map_report(yaml_path))
            self.assertIn("[OK] saved map looks healthy for the current 2D localization pipeline.", report)
            self.assertIn("[INFO] map_extent_m=2.00 x 2.00", report)
            self.assertIn("[INFO] known_ratio=100.0%", report)

    def test_small_map_warns_about_extent(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            image_path = temp_path / "small_map.pgm"
            yaml_path = temp_path / "small_map.yaml"

            rows = [[0 if x in {0, 9} or y in {0, 9} else 254 for x in range(10)] for y in range(10)]
            _write_text_map(image_path, rows)
            yaml_path.write_text(
                "\n".join(
                    [
                        "image: small_map.pgm",
                        "resolution: 0.05",
                        "origin: [0.0, 0.0, 0.0]",
                        "mode: trinary",
                    ]
                ),
                encoding="utf-8",
            )

            report = "\n".join(build_map_report(yaml_path))
            self.assertIn("[WARN] map extent is small.", report)
            self.assertIn("[WARN] known mapped area is small.", report)

    def test_prefix_path_and_relative_image_are_supported(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            maps_dir = temp_path / "maps"
            maps_dir.mkdir()
            image_path = maps_dir / "relative_map.pgm"
            yaml_path = temp_path / "relative_map.yaml"

            rows = [[0 if x in {0, 39} or y in {0, 39} else 254 for x in range(40)] for y in range(40)]
            _write_text_map(image_path, rows)
            yaml_path.write_text(
                "\n".join(
                    [
                        "image: maps/relative_map.pgm",
                        "resolution: 0.05",
                        "origin: [0.0, 0.0, 0.0]",
                        "mode: trinary",
                    ]
                ),
                encoding="utf-8",
            )

            report = "\n".join(build_map_report(temp_path / "relative_map"))
            self.assertIn(f"[INFO] image_path={image_path.resolve()}", report)
            self.assertIn("[OK] saved map looks healthy for the current 2D localization pipeline.", report)

    def test_binary_pgm_with_crlf_header_is_readable(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            image_path = temp_path / "binary_map.pgm"
            yaml_path = temp_path / "binary_map.yaml"

            pixels = bytes(
                0 if x in {0, 39} or y in {0, 39} else 254
                for y in range(40)
                for x in range(40)
            )
            image_path.write_bytes(b"P5\r\n40 40\r\n255\r\n" + pixels)
            yaml_path.write_text(
                "\n".join(
                    [
                        "image: binary_map.pgm",
                        "resolution: 0.05",
                        "origin: [0.0, 0.0, 0.0]",
                        "mode: trinary",
                    ]
                ),
                encoding="utf-8",
            )

            report = "\n".join(build_map_report(yaml_path))
            self.assertIn("[INFO] occupied_cells=156 (9.8%)", report)
            self.assertIn("[OK] saved map looks healthy for the current 2D localization pipeline.", report)

    def test_sparse_obstacles_warn_about_weak_structure(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            image_path = temp_path / "sparse_map.pgm"
            yaml_path = temp_path / "sparse_map.yaml"

            rows = [[254 for _ in range(40)] for _ in range(40)]
            rows[0][0] = 0
            rows[39][39] = 0
            _write_text_map(image_path, rows)
            yaml_path.write_text(
                "\n".join(
                    [
                        "image: sparse_map.pgm",
                        "resolution: 0.05",
                        "origin: [0.0, 0.0, 0.0]",
                        "mode: trinary",
                    ]
                ),
                encoding="utf-8",
            )

            report = "\n".join(build_map_report(yaml_path))
            self.assertIn("[WARN] obstacle structure is sparse relative to known area. AMCL-style localization may be weak.", report)
            self.assertIn("[OK] saved map is readable, but it still shows some quality risks.", report)


if __name__ == "__main__":
    unittest.main()
