#!/usr/bin/env python3
"""
Build a higher-quality OpenBene session map using Open3D.

Compared with the lightweight pure-Python builder, this version adds:
- denser point sampling
- voxel downsampling
- statistical outlier removal
- optional normal estimation
- Poisson mesh reconstruction for a more surface-like result
- self-contained browser preview that colors point depth

Run it from the Open3D-enabled conda environment, for example:
    conda run -n openbene-map python openbene_sdk/src/openbene/session_map_builder_o3d.py /path/to/session
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import List, Sequence, Tuple

import numpy as np
import open3d as o3d
from PIL import Image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build a higher-quality OpenBene session map with Open3D")
    parser.add_argument("session_dir", type=Path, help="Path to session directory")
    parser.add_argument("--output-dir", type=Path, default=None, help="Output directory (default: <session>/map_o3d)")
    parser.add_argument("--sample-stride", type=int, default=4, help="Depth pixel stride (default: 4)")
    parser.add_argument("--near-depth", type=float, default=0.1, help="Near depth clip in meters")
    parser.add_argument("--far-depth", type=float, default=3.0, help="Far depth clip in meters")
    parser.add_argument("--voxel-size", type=float, default=0.015, help="Voxel downsample size in meters")
    parser.add_argument("--nb-neighbors", type=int, default=20, help="Neighbors for statistical filtering")
    parser.add_argument("--std-ratio", type=float, default=1.8, help="Std ratio for statistical filtering")
    parser.add_argument("--poisson-depth", type=int, default=8, help="Poisson reconstruction depth")
    return parser.parse_args()


def load_manifest(session_dir: Path) -> dict:
    manifest_path = session_dir / "transforms.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"Missing transforms.json: {manifest_path}")
    return json.loads(manifest_path.read_text())


def build_output_dir(session_dir: Path, explicit_output_dir: Path | None) -> Path:
    if explicit_output_dir is not None:
        return explicit_output_dir.expanduser().resolve()
    return session_dir / "map_o3d"


def load_depth_png(depth_path: Path) -> np.ndarray:
    with Image.open(depth_path) as image:
        image.load()
        return np.array(image, dtype=np.uint16)


def sample_world_points(manifest: dict, session_dir: Path, sample_stride: int, near_depth: float, far_depth: float) -> np.ndarray:
    frames = manifest.get("frames", [])
    image_width = int(manifest["w"])
    image_height = int(manifest["h"])
    depth_scale = float(manifest.get("depth_scale", 1000.0))
    all_points: List[np.ndarray] = []

    for frame in frames:
        depth_relpath = frame.get("depth_file_path")
        if not depth_relpath:
            continue

        depth_path = session_dir / depth_relpath
        if not depth_path.exists():
            continue

        depth_image = load_depth_png(depth_path).astype(np.float32) / depth_scale
        depth_height, depth_width = depth_image.shape

        fx = float(manifest["fl_x"]) * depth_width / max(image_width, 1)
        fy = float(manifest["fl_y"]) * depth_height / max(image_height, 1)
        cx = float(manifest["cx"]) * depth_width / max(image_width, 1)
        cy = float(manifest["cy"]) * depth_height / max(image_height, 1)

        ys = np.arange(0, depth_height, sample_stride, dtype=np.int32)
        xs = np.arange(0, depth_width, sample_stride, dtype=np.int32)
        grid_x, grid_y = np.meshgrid(xs, ys)
        sampled_depth = depth_image[grid_y, grid_x]

        valid = np.isfinite(sampled_depth) & (sampled_depth >= near_depth) & (sampled_depth <= far_depth)
        if not np.any(valid):
            continue

        z = sampled_depth[valid]
        x = (grid_x[valid].astype(np.float32) - cx) / fx * z
        y = (grid_y[valid].astype(np.float32) - cy) / fy * z
        camera_points = np.stack([x, y, z], axis=1)
        finite_mask = np.all(np.isfinite(camera_points), axis=1)
        if not np.any(finite_mask):
            continue
        camera_points = camera_points[finite_mask]

        transform = np.asarray(frame["transform_matrix"], dtype=np.float32)
        rotation = transform[:3, :3]
        translation = transform[:3, 3]
        world_points = (rotation @ camera_points.T).T + translation
        world_points = world_points[np.all(np.isfinite(world_points), axis=1)]
        if world_points.size == 0:
            continue
        all_points.append(world_points)

    if not all_points:
        return np.zeros((0, 3), dtype=np.float32)

    return np.concatenate(all_points, axis=0)


def build_point_cloud(points: np.ndarray, voxel_size: float, nb_neighbors: int, std_ratio: float) -> o3d.geometry.PointCloud:
    cloud = o3d.geometry.PointCloud()
    cloud.points = o3d.utility.Vector3dVector(points)
    cloud = cloud.voxel_down_sample(voxel_size=voxel_size)

    if len(cloud.points) == 0:
        return cloud

    cloud, _ = cloud.remove_statistical_outlier(nb_neighbors=nb_neighbors, std_ratio=std_ratio)
    if len(cloud.points) == 0:
        return cloud

    cloud.estimate_normals(search_param=o3d.geometry.KDTreeSearchParamHybrid(radius=voxel_size * 4.0, max_nn=30))
    cloud.normalize_normals()
    return cloud


def crop_low_density_mesh(mesh: o3d.geometry.TriangleMesh, densities: np.ndarray, keep_ratio: float = 0.04) -> o3d.geometry.TriangleMesh:
    if len(densities) == 0:
        return mesh
    threshold = np.quantile(densities, keep_ratio)
    vertices_to_remove = densities < threshold
    mesh.remove_vertices_by_mask(vertices_to_remove)
    return mesh


def build_mesh(cloud: o3d.geometry.PointCloud, poisson_depth: int) -> o3d.geometry.TriangleMesh | None:
    if len(cloud.points) < 100:
        return None
    mesh, densities = o3d.geometry.TriangleMesh.create_from_point_cloud_poisson(cloud, depth=poisson_depth)
    mesh = crop_low_density_mesh(mesh, np.asarray(densities))
    mesh.compute_vertex_normals()
    return mesh


def save_depth_colored_preview(points: np.ndarray, output_path: Path, title: str) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)

    width = 1400
    height = 1000
    image = Image.new("RGB", (width, height), (245, 244, 238))
    pixels = image.load()

    if len(points) > 0:
        center = points.mean(axis=0)
        shifted = points - center
        yaw = 0.7
        pitch = -0.35

        cy = math.cos(yaw)
        sy = math.sin(yaw)
        cp = math.cos(pitch)
        sp = math.sin(pitch)

        rotated = []
        for x, y, z in shifted:
            x1 = cy * x + sy * z
            z1 = -sy * x + cy * z
            y2 = cp * y - sp * z1
            z2 = sp * y + cp * z1
            rotated.append((x1, y2, z2))
        rotated = np.asarray(rotated)

        radius = np.max(np.ptp(rotated, axis=0)) or 1.0
        rotated /= radius

        depth_min = float(rotated[:, 2].min())
        depth_max = float(rotated[:, 2].max())

        order = np.argsort(rotated[:, 2])
        for idx in order:
            x, y, z = rotated[idx]
            px = int(width / 2 + x * 360)
            py = int(height / 2 - y * 360)
            if 0 <= px < width and 0 <= py < height:
                t = 0.0 if depth_max <= depth_min else (z - depth_min) / (depth_max - depth_min)
                r = int(25 + 160 * t)
                g = int(70 + 80 * (1.0 - t))
                b = int(170 + 40 * (1.0 - t))
                pixels[px, py] = (r, g, b)

    from PIL import ImageDraw
    draw = ImageDraw.Draw(image)
    draw.text((24, 18), title, fill=(40, 40, 40))

    image.save(output_path)


def write_html_report(output_path: Path, stats: dict) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    html = f"""<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>OpenBene O3D Map Report</title>
  <style>
    body {{ margin: 0; font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #f3f0e8; color: #1f2933; }}
    .wrap {{ max-width: 1100px; margin: 0 auto; padding: 28px; }}
    .hero {{ margin-bottom: 24px; }}
    .hero h1 {{ margin: 0 0 8px; font-size: 28px; }}
    .grid {{ display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 18px; }}
    .card {{ background: rgba(255,255,255,0.82); border: 1px solid rgba(0,0,0,0.08); border-radius: 18px; padding: 18px; }}
    .card h2 {{ margin: 0 0 12px; font-size: 18px; }}
    .metric {{ margin: 8px 0; font-size: 14px; color: #52606d; }}
    img {{ width: 100%; border-radius: 12px; border: 1px solid rgba(0,0,0,0.08); background: white; }}
    code {{ font-family: ui-monospace, SFMono-Regular, monospace; }}
  </style>
</head>
<body>
  <div class=\"wrap\">
    <div class=\"hero\">
      <h1>OpenBene Session Map Report</h1>
      <div class=\"metric\">Session: <code>{stats['session_name']}</code></div>
      <div class=\"metric\">Point cloud: <code>{stats['pointcloud_file']}</code></div>
      <div class=\"metric\">Mesh: <code>{stats['mesh_file']}</code></div>
    </div>
    <div class=\"grid\">
      <div class=\"card\">
        <h2>Preview</h2>
        <img src=\"map_preview_depth.png\" alt=\"Depth-colored map preview\" />
      </div>
      <div class=\"card\">
        <h2>Stats</h2>
        <div class=\"metric\">Raw sampled points: {stats['raw_point_count']}</div>
        <div class=\"metric\">Filtered points: {stats['filtered_point_count']}</div>
        <div class=\"metric\">Mesh vertices: {stats['mesh_vertex_count']}</div>
        <div class=\"metric\">Mesh triangles: {stats['mesh_triangle_count']}</div>
        <div class=\"metric\">Voxel size: {stats['voxel_size_m']} m</div>
        <div class=\"metric\">Depth clip: {stats['near_depth_m']} - {stats['far_depth_m']} m</div>
        <div class=\"metric\">Sampling stride: {stats['sample_stride']}</div>
      </div>
    </div>
  </div>
</body>
</html>
"""
    output_path.write_text(html, encoding="utf-8")


def main() -> None:
    args = parse_args()
    session_dir = args.session_dir.expanduser().resolve()
    output_dir = build_output_dir(session_dir, args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    manifest = load_manifest(session_dir)
    raw_points = sample_world_points(
        manifest=manifest,
        session_dir=session_dir,
        sample_stride=max(1, args.sample_stride),
        near_depth=args.near_depth,
        far_depth=args.far_depth,
    )
    cloud = build_point_cloud(
        points=raw_points,
        voxel_size=args.voxel_size,
        nb_neighbors=args.nb_neighbors,
        std_ratio=args.std_ratio,
    )
    mesh = build_mesh(cloud, poisson_depth=args.poisson_depth)

    pointcloud_path = output_dir / "map_fused_pointcloud_o3d.ply"
    mesh_path = output_dir / "map_surface_mesh_o3d.ply"
    preview_path = output_dir / "map_preview_depth.png"
    metadata_path = output_dir / "map_o3d_metadata.json"
    report_path = output_dir / "map_o3d_report.html"

    o3d.io.write_point_cloud(str(pointcloud_path), cloud)
    if mesh is not None:
        o3d.io.write_triangle_mesh(str(mesh_path), mesh)
    save_depth_colored_preview(np.asarray(cloud.points), preview_path, session_dir.name)

    stats = {
        "map_format_version": "openbene_session_map_o3d_v1",
        "session_name": str(manifest.get("session_name", session_dir.name)),
        "session_mode": str(manifest.get("session_mode", "mapping")),
        "raw_point_count": int(raw_points.shape[0]),
        "filtered_point_count": int(len(cloud.points)),
        "mesh_vertex_count": int(len(mesh.vertices)) if mesh is not None else 0,
        "mesh_triangle_count": int(len(mesh.triangles)) if mesh is not None else 0,
        "sample_stride": int(max(1, args.sample_stride)),
        "near_depth_m": float(args.near_depth),
        "far_depth_m": float(args.far_depth),
        "voxel_size_m": float(args.voxel_size),
        "nb_neighbors": int(args.nb_neighbors),
        "std_ratio": float(args.std_ratio),
        "poisson_depth": int(args.poisson_depth),
        "pointcloud_file": pointcloud_path.name,
        "mesh_file": mesh_path.name if mesh is not None else None,
        "preview_file": preview_path.name,
        "report_file": report_path.name,
    }
    metadata_path.write_text(json.dumps(stats, indent=2), encoding="utf-8")
    write_html_report(report_path, stats)

    print(f"raw_point_count: {stats['raw_point_count']}")
    print(f"filtered_point_count: {stats['filtered_point_count']}")
    print(f"mesh_vertex_count: {stats['mesh_vertex_count']}")
    print(f"mesh_triangle_count: {stats['mesh_triangle_count']}")
    print(f"map_pointcloud: {pointcloud_path}")
    print(f"map_mesh: {mesh_path if mesh is not None else 'not_generated'}")
    print(f"map_preview: {preview_path}")
    print(f"map_metadata: {metadata_path}")
    print(f"map_report: {report_path}")


if __name__ == "__main__":
    main()
