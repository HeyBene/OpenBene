#!/usr/bin/env python3
"""
Build and validate a formal OpenBene session map on PC.

This script upgrades the earlier validation-only step into a session map builder.
Given a Nerfstudio-style capture session directory, it produces:

- `map_fused_pointcloud.ply`: PC-built fused map artifact
- `map_metadata.json`: structured map/session statistics

It still supports lightweight terminal validation output so it can be used both
as a developer tool and as the first map-building stage in the pipeline.

Dependencies are intentionally minimal:
- Python 3 standard library
- Pillow
"""

from __future__ import annotations

import argparse
import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

from PIL import Image, ImageDraw


Point3 = Tuple[float, float, float]
Matrix4 = List[List[float]]


@dataclass
class SessionStats:
    frame_count: int
    depth_frame_count: int
    duration_seconds: float
    adjacent_translation_mean_m: float
    adjacent_translation_max_m: float
    adjacent_rotation_mean_deg: float
    adjacent_rotation_max_deg: float
    suspicious_steps: int
    severe_steps: int
    fused_point_count: int
    bbox_min_m: Point3
    bbox_max_m: Point3


@dataclass
class SessionMapMetadata:
    map_format_version: str
    source_session_dir: str
    source_session_name: str
    source_session_mode: str
    coordinate_convention: str
    depth_unit: str
    depth_scale: float
    image_width: int
    image_height: int
    fl_x: float
    fl_y: float
    cx: float
    cy: float
    sample_stride: int
    near_depth_m: float
    far_depth_m: float
    voxel_size_m: float
    min_neighbors: int
    output_pointcloud_file: str
    stats: SessionStats


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build and validate an OpenBene session map")
    parser.add_argument("session_dir", type=Path, help="Path to session directory")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=None,
        help="Optional output directory for map artifacts (defaults to <session>/map_pc)",
    )
    parser.add_argument(
        "--sample-stride",
        type=int,
        default=6,
        help="Sample every N pixels from depth map (default: 6)",
    )
    parser.add_argument(
        "--near-depth",
        type=float,
        default=0.05,
        help="Near depth clip in meters (default: 0.05)",
    )
    parser.add_argument(
        "--far-depth",
        type=float,
        default=4.0,
        help="Far depth clip in meters (default: 4.0)",
    )
    parser.add_argument(
        "--voxel-size",
        type=float,
        default=0.01,
        help="Voxel size in meters for fusion deduplication (default: 0.01)",
    )
    parser.add_argument(
        "--pointcloud-name",
        type=str,
        default="map_fused_pointcloud.ply",
        help="Output pointcloud file name (default: map_fused_pointcloud.ply)",
    )
    parser.add_argument(
        "--metadata-name",
        type=str,
        default="map_metadata.json",
        help="Output metadata file name (default: map_metadata.json)",
    )
    parser.add_argument(
        "--html-name",
        type=str,
        default="map_viewer.html",
        help="Output HTML viewer file name (default: map_viewer.html)",
    )
    parser.add_argument(
        "--preview-size",
        type=int,
        default=1200,
        help="Square preview image size in pixels (default: 1200)",
    )
    parser.add_argument(
        "--min-neighbors",
        type=int,
        default=2,
        help="Minimum occupied neighboring voxels required to keep a point (default: 2)",
    )
    return parser.parse_args()


def load_manifest(session_dir: Path) -> dict:
    manifest_path = session_dir / "transforms.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"Missing transforms.json: {manifest_path}")
    return json.loads(manifest_path.read_text())


def vector_sub(a: Sequence[float], b: Sequence[float]) -> Point3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def vector_length(v: Sequence[float]) -> float:
    return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


def matrix3_transpose(m: Sequence[Sequence[float]]) -> List[List[float]]:
    return [[m[j][i] for j in range(3)] for i in range(3)]


def matrix3_mul(a: Sequence[Sequence[float]], b: Sequence[Sequence[float]]) -> List[List[float]]:
    out = [[0.0, 0.0, 0.0] for _ in range(3)]
    for i in range(3):
        for j in range(3):
            out[i][j] = sum(a[i][k] * b[k][j] for k in range(3))
    return out


def transform_point(transform: Matrix4, point: Sequence[float]) -> Point3:
    x = transform[0][0] * point[0] + transform[0][1] * point[1] + transform[0][2] * point[2] + transform[0][3]
    y = transform[1][0] * point[0] + transform[1][1] * point[1] + transform[1][2] * point[2] + transform[1][3]
    z = transform[2][0] * point[0] + transform[2][1] * point[1] + transform[2][2] * point[2] + transform[2][3]
    return (x, y, z)


def compute_pose_step_stats(frames: List[dict]) -> Tuple[float, float, float, float, int, int, float]:
    if not frames:
        return 0.0, 0.0, 0.0, 0.0, 0, 0, 0.0

    translations: List[float] = []
    rotations: List[float] = []
    suspicious_steps = 0
    severe_steps = 0

    timestamps = [float(frame.get("timestamp", 0.0)) for frame in frames]
    duration_seconds = max(timestamps) - min(timestamps) if len(timestamps) > 1 else 0.0

    for previous_frame, current_frame in zip(frames, frames[1:]):
        previous_pose = previous_frame["transform_matrix"]
        current_pose = current_frame["transform_matrix"]

        previous_translation = [previous_pose[0][3], previous_pose[1][3], previous_pose[2][3]]
        current_translation = [current_pose[0][3], current_pose[1][3], current_pose[2][3]]
        translation = vector_length(vector_sub(current_translation, previous_translation))

        previous_rotation = [[previous_pose[i][j] for j in range(3)] for i in range(3)]
        current_rotation = [[current_pose[i][j] for j in range(3)] for i in range(3)]
        relative_rotation = matrix3_mul(matrix3_transpose(previous_rotation), current_rotation)
        trace = relative_rotation[0][0] + relative_rotation[1][1] + relative_rotation[2][2]
        cos_angle = max(-1.0, min(1.0, (trace - 1.0) / 2.0))
        rotation_deg = math.degrees(math.acos(cos_angle))

        translations.append(translation)
        rotations.append(rotation_deg)

        if translation > 0.15 or rotation_deg > 20.0:
            severe_steps += 1
        elif translation > 0.08 or rotation_deg > 12.0:
            suspicious_steps += 1

    if not translations:
        return 0.0, 0.0, 0.0, 0.0, 0, 0, duration_seconds

    return (
        sum(translations) / len(translations),
        max(translations),
        sum(rotations) / len(rotations),
        max(rotations),
        suspicious_steps,
        severe_steps,
        duration_seconds,
    )


def load_depth_image(depth_path: Path) -> Tuple[List[List[int]], int, int]:
    with Image.open(depth_path) as image:
        image.load()
        width, height = image.size
        rows = list(image.getdata())
    depth_rows = [rows[i * width:(i + 1) * width] for i in range(height)]
    return depth_rows, width, height


def iter_fused_points(
    session_dir: Path,
    manifest: dict,
    sample_stride: int,
    near_depth: float,
    far_depth: float,
    voxel_size: float,
) -> Iterable[Point3]:
    frames = manifest.get("frames", [])
    image_width = int(manifest["w"])
    image_height = int(manifest["h"])
    depth_scale = float(manifest.get("depth_scale", 1000.0))

    for frame in frames:
        depth_relpath = frame.get("depth_file_path")
        if not depth_relpath:
            continue

        depth_path = session_dir / depth_relpath
        if not depth_path.exists():
            continue

        depth_rows, depth_width, depth_height = load_depth_image(depth_path)
        fx = float(manifest["fl_x"]) * depth_width / max(image_width, 1)
        fy = float(manifest["fl_y"]) * depth_height / max(image_height, 1)
        cx = float(manifest["cx"]) * depth_width / max(image_width, 1)
        cy = float(manifest["cy"]) * depth_height / max(image_height, 1)
        transform = frame["transform_matrix"]

        frame_voxels: Dict[Tuple[int, int, int], Point3] = {}

        for y in range(0, depth_height, sample_stride):
            row = depth_rows[y]
            for x in range(0, depth_width, sample_stride):
                raw_depth = row[x]
                if not isinstance(raw_depth, int):
                    raw_depth = int(raw_depth)
                if raw_depth <= 0:
                    continue

                depth_meters = raw_depth / depth_scale
                if not math.isfinite(depth_meters):
                    continue
                if depth_meters < near_depth or depth_meters > far_depth:
                    continue

                x_camera = (float(x) - cx) / fx * depth_meters
                y_camera = (float(y) - cy) / fy * depth_meters
                world_point = transform_point(transform, (x_camera, y_camera, depth_meters))
                voxel_key = (
                    int(round(world_point[0] / voxel_size)),
                    int(round(world_point[1] / voxel_size)),
                    int(round(world_point[2] / voxel_size)),
                )
                frame_voxels[voxel_key] = world_point

        for point in frame_voxels.values():
            yield point


def fuse_session(
    session_dir: Path,
    manifest: dict,
    sample_stride: int,
    near_depth: float,
    far_depth: float,
    voxel_size: float,
) -> List[Point3]:
    voxel_map: Dict[Tuple[int, int, int], Point3] = {}

    for point in iter_fused_points(
        session_dir=session_dir,
        manifest=manifest,
        sample_stride=sample_stride,
        near_depth=near_depth,
        far_depth=far_depth,
        voxel_size=voxel_size,
    ):
        key = (
            int(round(point[0] / voxel_size)),
            int(round(point[1] / voxel_size)),
            int(round(point[2] / voxel_size)),
        )
        voxel_map[key] = point

    return list(voxel_map.values())


def filter_sparse_points(points: Sequence[Point3], voxel_size: float, min_neighbors: int) -> List[Point3]:
    if min_neighbors <= 0 or not points:
        return list(points)

    voxel_map: Dict[Tuple[int, int, int], Point3] = {}
    for point in points:
        key = (
            int(round(point[0] / voxel_size)),
            int(round(point[1] / voxel_size)),
            int(round(point[2] / voxel_size)),
        )
        voxel_map[key] = point

    kept: List[Point3] = []
    for key, point in voxel_map.items():
        neighbors = 0
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for dz in (-1, 0, 1):
                    if dx == 0 and dy == 0 and dz == 0:
                        continue
                    if (key[0] + dx, key[1] + dy, key[2] + dz) in voxel_map:
                        neighbors += 1
        if neighbors >= min_neighbors:
            kept.append(point)

    return kept if kept else list(points)


def compute_bounding_box(points: Sequence[Point3]) -> Tuple[Point3, Point3]:
    if not points:
        return (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)

    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    zs = [point[2] for point in points]
    return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))


def write_ascii_ply(points: Sequence[Point3], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as handle:
        handle.write("ply\n")
        handle.write("format ascii 1.0\n")
        handle.write(f"element vertex {len(points)}\n")
        handle.write("property float x\n")
        handle.write("property float y\n")
        handle.write("property float z\n")
        handle.write("end_header\n")
        for x, y, z in points:
            handle.write(f"{x} {y} {z}\n")


def project_points_to_plane(points: Sequence[Point3], axis_a: int, axis_b: int) -> List[Tuple[float, float]]:
    return [(point[axis_a], point[axis_b]) for point in points]


def draw_projection_image(
    projected_points: Sequence[Tuple[float, float]],
    output_path: Path,
    title: str,
    preview_size: int,
) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)

    canvas = Image.new("RGB", (preview_size, preview_size), (245, 244, 238))
    draw = ImageDraw.Draw(canvas)
    margin = max(40, preview_size // 20)

    if projected_points:
        xs = [point[0] for point in projected_points]
        ys = [point[1] for point in projected_points]
        min_x, max_x = min(xs), max(xs)
        min_y, max_y = min(ys), max(ys)
        span_x = max(max_x - min_x, 1e-6)
        span_y = max(max_y - min_y, 1e-6)
        scale = min((preview_size - 2 * margin) / span_x, (preview_size - 2 * margin) / span_y)

        for x, y in projected_points:
            px = margin + (x - min_x) * scale
            py = preview_size - margin - (y - min_y) * scale
            draw.point((px, py), fill=(26, 71, 102))

    draw.rectangle((margin, margin, preview_size - margin, preview_size - margin), outline=(170, 170, 170), width=2)
    draw.text((margin, 12), title, fill=(40, 40, 40))
    canvas.save(output_path)


def write_preview_images(points: Sequence[Point3], output_dir: Path, preview_size: int) -> List[str]:
    if not points:
        return []

    outputs = []
    plan_path = output_dir / "map_preview_top.png"
    side_path = output_dir / "map_preview_side.png"
    front_path = output_dir / "map_preview_front.png"

    draw_projection_image(project_points_to_plane(points, 0, 2), plan_path, "Top View (X-Z)", preview_size)
    draw_projection_image(project_points_to_plane(points, 0, 1), side_path, "Side View (X-Y)", preview_size)
    draw_projection_image(project_points_to_plane(points, 2, 1), front_path, "Front View (Z-Y)", preview_size)

    outputs.extend([plan_path.name, side_path.name, front_path.name])
    return outputs


def write_html_viewer(points: Sequence[Point3], output_path: Path, title: str) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    points_json = json.dumps([[round(x, 4), round(y, 4), round(z, 4)] for x, y, z in points])
    html = f"""<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>{title}</title>
  <style>
    html, body {{ margin: 0; height: 100%; background: #f3f0e8; color: #1f2933; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }}
    #app {{ display: grid; grid-template-rows: auto 1fr; height: 100%; }}
    #hud {{ padding: 14px 18px; background: rgba(255,255,255,0.86); backdrop-filter: blur(10px); border-bottom: 1px solid rgba(0,0,0,0.08); }}
    #hud h1 {{ margin: 0 0 4px; font-size: 16px; }}
    #hud p {{ margin: 0; font-size: 13px; color: #52606d; }}
    #viewer {{ width: 100%; height: 100%; display: block; cursor: grab; }}
    #viewer.dragging {{ cursor: grabbing; }}
  </style>
</head>
<body>
  <div id=\"app\">
    <div id=\"hud\">
      <h1>{title}</h1>
      <p>Drag to orbit, scroll to zoom. This is a self-contained 3D preview of the fused map.</p>
    </div>
    <canvas id=\"viewer\"></canvas>
  </div>
  <script>
    const points = {points_json};
    const canvas = document.getElementById('viewer');
    const ctx = canvas.getContext('2d');
    const state = {{ yaw: 0.65, pitch: -0.35, zoom: 1.0, dragging: false, lastX: 0, lastY: 0 }};

    function resize() {{
      const dpr = Math.max(1, window.devicePixelRatio || 1);
      canvas.width = Math.floor(canvas.clientWidth * dpr);
      canvas.height = Math.floor(canvas.clientHeight * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      draw();
    }}

    function bounds(values) {{
      let min = Infinity;
      let max = -Infinity;
      for (const value of values) {{
        if (value < min) min = value;
        if (value > max) max = value;
      }}
      return [min, max];
    }}

    const xs = points.map(p => p[0]);
    const ys = points.map(p => p[1]);
    const zs = points.map(p => p[2]);
    const [minX, maxX] = bounds(xs);
    const [minY, maxY] = bounds(ys);
    const [minZ, maxZ] = bounds(zs);
    const center = [
      (minX + maxX) / 2,
      (minY + maxY) / 2,
      (minZ + maxZ) / 2,
    ];
    const radius = Math.max(maxX - minX, maxY - minY, maxZ - minZ) || 1;
    const normalized = points.map(([x, y, z]) => [
      (x - center[0]) / radius,
      (y - center[1]) / radius,
      (z - center[2]) / radius,
    ]);

    function rotate(point) {{
      const cy = Math.cos(state.yaw);
      const sy = Math.sin(state.yaw);
      const cp = Math.cos(state.pitch);
      const sp = Math.sin(state.pitch);

      const x1 = cy * point[0] + sy * point[2];
      const z1 = -sy * point[0] + cy * point[2];
      const y2 = cp * point[1] - sp * z1;
      const z2 = sp * point[1] + cp * z1;
      return [x1, y2, z2];
    }}

    function drawAxis(width, height, scale) {{
      const axes = [
        {{ dir: [0.6, 0, 0], color: '#d64545' }},
        {{ dir: [0, 0.6, 0], color: '#2f855a' }},
        {{ dir: [0, 0, 0.6], color: '#2b6cb0' }},
      ];
      for (const axis of axes) {{
        const start = rotate([0, 0, 0]);
        const end = rotate(axis.dir);
        ctx.strokeStyle = axis.color;
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(width / 2 + start[0] * scale, height / 2 - start[1] * scale);
        ctx.lineTo(width / 2 + end[0] * scale, height / 2 - end[1] * scale);
        ctx.stroke();
      }}
    }}

    function draw() {{
      const width = canvas.clientWidth;
      const height = canvas.clientHeight;
      ctx.clearRect(0, 0, width, height);
      ctx.fillStyle = '#f3f0e8';
      ctx.fillRect(0, 0, width, height);

      const scale = Math.min(width, height) * 0.34 * state.zoom;
      const projected = normalized.map(point => {{
        const rotated = rotate(point);
        const depth = rotated[2] + 2.5;
        const perspective = 1.6 / depth;
        return {{
          x: width / 2 + rotated[0] * scale * perspective,
          y: height / 2 - rotated[1] * scale * perspective,
          z: rotated[2],
        }};
      }});

      projected.sort((a, b) => a.z - b.z);
      drawAxis(width, height, scale);

      for (const point of projected) {{
        const alpha = Math.max(0.18, Math.min(0.95, 0.75 - point.z * 0.18));
        const size = Math.max(1.2, 2.4 - point.z * 0.35);
        ctx.fillStyle = `rgba(26, 71, 102, ${{alpha}})`;
        ctx.beginPath();
        ctx.arc(point.x, point.y, size, 0, Math.PI * 2);
        ctx.fill();
      }}
    }}

    canvas.addEventListener('mousedown', (event) => {{
      state.dragging = true;
      state.lastX = event.clientX;
      state.lastY = event.clientY;
      canvas.classList.add('dragging');
    }});

    window.addEventListener('mouseup', () => {{
      state.dragging = false;
      canvas.classList.remove('dragging');
    }});

    window.addEventListener('mousemove', (event) => {{
      if (!state.dragging) return;
      const dx = event.clientX - state.lastX;
      const dy = event.clientY - state.lastY;
      state.lastX = event.clientX;
      state.lastY = event.clientY;
      state.yaw += dx * 0.01;
      state.pitch += dy * 0.01;
      state.pitch = Math.max(-1.45, Math.min(1.45, state.pitch));
      draw();
    }});

    canvas.addEventListener('wheel', (event) => {{
      event.preventDefault();
      const factor = event.deltaY > 0 ? 0.92 : 1.08;
      state.zoom = Math.max(0.4, Math.min(4.0, state.zoom * factor));
      draw();
    }}, {{ passive: false }});

    window.addEventListener('resize', resize);
    resize();
  </script>
</body>
</html>
"""
    output_path.write_text(html, encoding="utf-8")


def build_stats(manifest: dict, fused_points: Sequence[Point3]) -> SessionStats:
    frames = manifest.get("frames", [])
    depth_frame_count = sum(1 for frame in frames if frame.get("depth_file_path"))
    (
        adjacent_translation_mean,
        adjacent_translation_max,
        adjacent_rotation_mean_deg,
        adjacent_rotation_max_deg,
        suspicious_steps,
        severe_steps,
        duration_seconds,
    ) = compute_pose_step_stats(frames)

    bbox_min, bbox_max = compute_bounding_box(fused_points)

    return SessionStats(
        frame_count=len(frames),
        depth_frame_count=depth_frame_count,
        duration_seconds=duration_seconds,
        adjacent_translation_mean_m=adjacent_translation_mean,
        adjacent_translation_max_m=adjacent_translation_max,
        adjacent_rotation_mean_deg=adjacent_rotation_mean_deg,
        adjacent_rotation_max_deg=adjacent_rotation_max_deg,
        suspicious_steps=suspicious_steps,
        severe_steps=severe_steps,
        fused_point_count=len(fused_points),
        bbox_min_m=bbox_min,
        bbox_max_m=bbox_max,
    )


def build_metadata(
    session_dir: Path,
    manifest: dict,
    stats: SessionStats,
    sample_stride: int,
    near_depth: float,
    far_depth: float,
    voxel_size: float,
    min_neighbors: int,
    pointcloud_name: str,
) -> SessionMapMetadata:
    return SessionMapMetadata(
        map_format_version="openbene_session_map_v1",
        source_session_dir=str(session_dir),
        source_session_name=str(manifest.get("session_name", session_dir.name)),
        source_session_mode=str(manifest.get("session_mode", "mapping")),
        coordinate_convention=str(manifest.get("coordinate_convention", "opengl")),
        depth_unit=str(manifest.get("depth_unit", "millimeters")),
        depth_scale=float(manifest.get("depth_scale", 1000.0)),
        image_width=int(manifest["w"]),
        image_height=int(manifest["h"]),
        fl_x=float(manifest["fl_x"]),
        fl_y=float(manifest["fl_y"]),
        cx=float(manifest["cx"]),
        cy=float(manifest["cy"]),
        sample_stride=sample_stride,
        near_depth_m=near_depth,
        far_depth_m=far_depth,
        voxel_size_m=voxel_size,
        min_neighbors=min_neighbors,
        output_pointcloud_file=pointcloud_name,
        stats=stats,
    )


def write_metadata(metadata: SessionMapMetadata, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(asdict(metadata), indent=2))


def print_stats(stats: SessionStats, output_dir: Path, pointcloud_name: str, metadata_name: str, html_name: str) -> None:
    print(f"frame_count: {stats.frame_count}")
    print(f"depth_frame_count: {stats.depth_frame_count}")
    print(f"duration_seconds: {stats.duration_seconds:.3f}")
    print(f"adjacent_translation_mean_m: {stats.adjacent_translation_mean_m:.4f}")
    print(f"adjacent_translation_max_m: {stats.adjacent_translation_max_m:.4f}")
    print(f"adjacent_rotation_mean_deg: {stats.adjacent_rotation_mean_deg:.3f}")
    print(f"adjacent_rotation_max_deg: {stats.adjacent_rotation_max_deg:.3f}")
    print(f"suspicious_steps: {stats.suspicious_steps}")
    print(f"severe_steps: {stats.severe_steps}")
    print(f"fused_point_count: {stats.fused_point_count}")
    print(f"bbox_min_m: [{stats.bbox_min_m[0]:.3f}, {stats.bbox_min_m[1]:.3f}, {stats.bbox_min_m[2]:.3f}]")
    print(f"bbox_max_m: [{stats.bbox_max_m[0]:.3f}, {stats.bbox_max_m[1]:.3f}, {stats.bbox_max_m[2]:.3f}]")
    print(f"map_pointcloud: {output_dir / pointcloud_name}")
    print(f"map_metadata: {output_dir / metadata_name}")
    print(f"map_viewer: {output_dir / html_name}")


def build_output_dir(session_dir: Path, explicit_output_dir: Optional[Path]) -> Path:
    if explicit_output_dir is not None:
        return explicit_output_dir.expanduser().resolve()
    return session_dir / "map_pc"


def main() -> None:
    args = parse_args()
    session_dir = args.session_dir.expanduser().resolve()
    output_dir = build_output_dir(session_dir, args.output_dir)
    manifest = load_manifest(session_dir)

    sample_stride = max(1, args.sample_stride)
    fused_points = fuse_session(
        session_dir=session_dir,
        manifest=manifest,
        sample_stride=sample_stride,
        near_depth=args.near_depth,
        far_depth=args.far_depth,
        voxel_size=args.voxel_size,
    )
    fused_points = filter_sparse_points(fused_points, args.voxel_size, max(0, args.min_neighbors))

    stats = build_stats(manifest, fused_points)
    metadata = build_metadata(
        session_dir=session_dir,
        manifest=manifest,
        stats=stats,
        sample_stride=sample_stride,
        near_depth=args.near_depth,
        far_depth=args.far_depth,
        voxel_size=args.voxel_size,
        min_neighbors=max(0, args.min_neighbors),
        pointcloud_name=args.pointcloud_name,
    )

    write_ascii_ply(fused_points, output_dir / args.pointcloud_name)
    write_metadata(metadata, output_dir / args.metadata_name)
    preview_outputs = write_preview_images(fused_points, output_dir, max(400, args.preview_size))
    write_html_viewer(fused_points, output_dir / args.html_name, f"OpenBene Session Map: {session_dir.name}")
    print_stats(stats, output_dir, args.pointcloud_name, args.metadata_name, args.html_name)
    for preview_name in preview_outputs:
        print(f"map_preview: {output_dir / preview_name}")


if __name__ == "__main__":
    main()
