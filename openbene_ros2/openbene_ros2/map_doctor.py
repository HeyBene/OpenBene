from __future__ import annotations

import argparse
import ast
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class SavedMapMetadata:
    yaml_path: Path
    image_path: Path
    mode: str
    resolution: float
    origin: tuple[float, float, float]
    negate: int
    occupied_thresh: float
    free_thresh: float


@dataclass(frozen=True)
class PgmImage:
    width: int
    height: int
    max_value: int
    pixels: tuple[int, ...]


def _resolve_yaml_path(path_like: str | Path) -> Path:
    path = Path(path_like).expanduser()

    candidates: list[Path] = []
    if path.suffix.lower() == ".yaml":
        candidates.append(path)
    elif path.suffix.lower() == ".pgm":
        candidates.append(path.with_suffix(".yaml"))
    else:
        candidates.append(path.with_suffix(".yaml"))
        candidates.append(path)

    for candidate in candidates:
        if candidate.exists():
            return candidate

    raise FileNotFoundError(f"Could not find map yaml for input '{path_like}'.")


def _parse_simple_yaml(yaml_path: Path) -> SavedMapMetadata:
    values: dict[str, str] = {}
    for raw_line in yaml_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        values[key.strip()] = value.strip()

    image_value = values.get("image")
    resolution_value = values.get("resolution")
    origin_value = values.get("origin")
    if image_value is None or resolution_value is None or origin_value is None:
        raise ValueError(f"Map yaml '{yaml_path}' is missing required fields.")

    image_path = Path(image_value)
    if not image_path.is_absolute():
        image_path = (yaml_path.parent / image_path).resolve()

    origin_literal = ast.literal_eval(origin_value)
    if not isinstance(origin_literal, (list, tuple)) or len(origin_literal) != 3:
        raise ValueError(f"Map yaml '{yaml_path}' has invalid origin.")

    origin = tuple(float(value) for value in origin_literal)
    return SavedMapMetadata(
        yaml_path=yaml_path.resolve(),
        image_path=image_path,
        mode=values.get("mode", "trinary"),
        resolution=float(resolution_value),
        origin=origin,  # type: ignore[arg-type]
        negate=int(values.get("negate", "0")),
        occupied_thresh=float(values.get("occupied_thresh", "0.65")),
        free_thresh=float(values.get("free_thresh", "0.25")),
    )


def _read_pgm(path: Path) -> PgmImage:
    data = path.read_bytes()
    index = 0

    def read_token() -> str:
        nonlocal index
        while index < len(data):
            byte = data[index]
            if byte in b" \t\r\n":
                index += 1
                continue
            if byte == ord("#"):
                while index < len(data) and data[index] not in b"\r\n":
                    index += 1
                continue
            break
        if index >= len(data):
            raise ValueError(f"PGM '{path}' ended unexpectedly while reading the header.")

        start = index
        while index < len(data) and data[index] not in b" \t\r\n#":
            index += 1
        return data[start:index].decode("ascii")

    magic = read_token()
    width = int(read_token())
    height = int(read_token())
    max_value = int(read_token())

    if magic not in {"P2", "P5"}:
        raise ValueError(f"Unsupported PGM magic '{magic}' in '{path}'.")
    if max_value <= 0 or max_value > 255:
        raise ValueError(f"Unsupported PGM max value '{max_value}' in '{path}'.")

    if magic == "P2":
        pixels = [int(read_token()) for _ in range(width * height)]
    else:
        if index >= len(data) or data[index] not in b" \t\r\n":
            raise ValueError(f"Binary PGM '{path}' is missing raster separator whitespace.")
        if data[index] == ord("\r") and index + 1 < len(data) and data[index + 1] == ord("\n"):
            index += 2
        else:
            index += 1
        raster = data[index : index + width * height]
        if len(raster) != width * height:
            raise ValueError(f"Binary PGM '{path}' has incomplete raster data.")
        pixels = list(raster)

    return PgmImage(
        width=width,
        height=height,
        max_value=max_value,
        pixels=tuple(pixels),
    )


def _classify_pixel(value: int, metadata: SavedMapMetadata, image: PgmImage) -> str:
    if metadata.mode.lower() == "trinary":
        if value <= 5:
            return "occupied"
        if value >= max(250, image.max_value - 5):
            return "free"
        return "unknown"

    normalized = value / float(image.max_value)
    occupancy = normalized if metadata.negate else 1.0 - normalized
    if occupancy > metadata.occupied_thresh:
        return "occupied"
    if occupancy < metadata.free_thresh:
        return "free"
    return "unknown"


def build_map_report(path_like: str | Path) -> list[str]:
    yaml_path = _resolve_yaml_path(path_like)
    metadata = _parse_simple_yaml(yaml_path)
    image = _read_pgm(metadata.image_path)

    total_cells = image.width * image.height
    occupied = 0
    free = 0
    unknown = 0
    known_min_x = image.width
    known_min_y = image.height
    known_max_x = -1
    known_max_y = -1

    for flat_index, value in enumerate(image.pixels):
        category = _classify_pixel(value, metadata, image)
        if category == "occupied":
            occupied += 1
        elif category == "free":
            free += 1
        else:
            unknown += 1

        if category != "unknown":
            x = flat_index % image.width
            y = flat_index // image.width
            known_min_x = min(known_min_x, x)
            known_min_y = min(known_min_y, y)
            known_max_x = max(known_max_x, x)
            known_max_y = max(known_max_y, y)

    known = occupied + free
    width_m = image.width * metadata.resolution
    height_m = image.height * metadata.resolution
    occupied_ratio_total = 0.0 if total_cells == 0 else occupied / total_cells
    free_ratio_total = 0.0 if total_cells == 0 else free / total_cells
    known_ratio = 0.0 if total_cells == 0 else known / total_cells
    unknown_ratio = 0.0 if total_cells == 0 else unknown / total_cells
    occupied_ratio_known = 0.0 if known == 0 else occupied / known

    if known_max_x >= known_min_x and known_max_y >= known_min_y:
        known_bbox_width_cells = known_max_x - known_min_x + 1
        known_bbox_height_cells = known_max_y - known_min_y + 1
    else:
        known_bbox_width_cells = 0
        known_bbox_height_cells = 0

    known_bbox_width_m = known_bbox_width_cells * metadata.resolution
    known_bbox_height_m = known_bbox_height_cells * metadata.resolution

    lines = [
        "OpenBene Map Doctor",
        "===================",
        f"[INFO] yaml_path={metadata.yaml_path}",
        f"[INFO] image_path={metadata.image_path}",
        f"[INFO] mode={metadata.mode}",
        f"[INFO] resolution_m={metadata.resolution:.3f}",
        f"[INFO] map_cells={image.width}x{image.height}",
        f"[INFO] map_extent_m={width_m:.2f} x {height_m:.2f}",
        f"[INFO] origin_xy_m=({metadata.origin[0]:.3f}, {metadata.origin[1]:.3f})",
        f"[INFO] occupied_cells={occupied} ({occupied_ratio_total:.1%})",
        f"[INFO] free_cells={free} ({free_ratio_total:.1%})",
        f"[INFO] unknown_cells={unknown} ({unknown_ratio:.1%})",
        f"[INFO] known_ratio={known_ratio:.1%}",
        f"[INFO] known_bbox_cells={known_bbox_width_cells}x{known_bbox_height_cells}",
        f"[INFO] known_bbox_m={known_bbox_width_m:.2f} x {known_bbox_height_m:.2f}",
        f"[INFO] occupied_ratio_within_known={occupied_ratio_known:.1%}",
    ]

    warnings = 0
    errors = 0

    if total_cells == 0:
        lines.append("[ERROR] map image contains zero cells.")
        errors += 1
    if occupied == 0:
        lines.append("[ERROR] no occupied cells were found. Localization will have nothing solid to match.")
        errors += 1
    if free == 0:
        lines.append("[ERROR] no free cells were found. The map is not navigable.")
        errors += 1
    if width_m < 1.5 or height_m < 1.5:
        lines.append("[WARN] map extent is small. Capture a larger loop before treating this as a localization map.")
        warnings += 1
    if known_bbox_width_m < 1.5 or known_bbox_height_m < 1.5:
        lines.append("[WARN] known mapped area is small. The robot may relocalize ambiguously.")
        warnings += 1
    if known_ratio < 0.20:
        lines.append("[WARN] most cells are still unknown. The scan coverage is probably incomplete.")
        warnings += 1
    if unknown_ratio > 0.80:
        lines.append("[WARN] unknown area dominates the saved map. This often means the path did not cover enough perimeter.")
        warnings += 1
    if occupied_ratio_known < 0.03:
        lines.append("[WARN] obstacle structure is sparse relative to known area. AMCL-style localization may be weak.")
        warnings += 1
    if occupied_ratio_known > 0.65:
        lines.append("[WARN] occupied structure is very dense. The map may be cluttered or overfilled by noise.")
        warnings += 1

    if errors == 0 and warnings == 0:
        lines.append("[OK] saved map looks healthy for the current 2D localization pipeline.")
    elif errors == 0:
        lines.append("[OK] saved map is readable, but it still shows some quality risks.")

    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Inspect a saved ROS2 occupancy map for localization readiness.")
    parser.add_argument(
        "map_path",
        help="Path to a saved map yaml, pgm, or prefix (for example /home/user/maps/openbene_map).",
    )
    args = parser.parse_args(argv)

    for line in build_map_report(args.map_path):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
