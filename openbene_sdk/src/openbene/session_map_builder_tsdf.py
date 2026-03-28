#!/usr/bin/env python3
"""
Build an OpenBene session map using Open3D TSDF fusion.

This is the next step beyond simple point cloud fusion. It integrates RGB-D
frames into a TSDF volume and extracts both a mesh and a point cloud, which is
much closer to a real mapping pipeline.

Run with the Open3D conda environment:
    conda run -n openbene-map python openbene_sdk/src/openbene/session_map_builder_tsdf.py /path/to/session
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import open3d as o3d
from PIL import Image


PRESETS = {
    "balanced": {
        "near_depth": 0.15,
        "far_depth": 2.0,
        "voxel_length": 0.01,
        "sdf_trunc": 0.04,
        "edge_crop": 32,
    },
    "near_clean": {
        "near_depth": 0.2,
        "far_depth": 1.8,
        "voxel_length": 0.008,
        "sdf_trunc": 0.03,
        "edge_crop": 32,
    },
    "smooth_stable": {
        "near_depth": 0.2,
        "far_depth": 2.2,
        "voxel_length": 0.015,
        "sdf_trunc": 0.05,
        "edge_crop": 40,
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build an OpenBene TSDF map with Open3D")
    parser.add_argument("session_dir", type=Path, help="Path to session directory")
    parser.add_argument("--output-dir", type=Path, default=None, help="Output directory (default: <session>/map_tsdf)")
    parser.add_argument("--preset", type=str, default="balanced", choices=sorted(PRESETS.keys()), help="Named TSDF preset")
    parser.add_argument("--near-depth", type=float, default=None, help="Near depth clip in meters")
    parser.add_argument("--far-depth", type=float, default=None, help="Far depth clip in meters")
    parser.add_argument("--voxel-length", type=float, default=None, help="TSDF voxel length in meters")
    parser.add_argument("--sdf-trunc", type=float, default=None, help="TSDF truncation distance in meters")
    parser.add_argument("--edge-crop", type=int, default=None, help="Crop this many depth pixels from each border")
    parser.add_argument("--max-frames", type=int, default=0, help="Optional limit on integrated frames (0 = all)")
    return parser.parse_args()


def resolve_parameters(args: argparse.Namespace) -> dict:
    preset = dict(PRESETS[args.preset])
    return {
        "preset": args.preset,
        "near_depth": float(args.near_depth if args.near_depth is not None else preset["near_depth"]),
        "far_depth": float(args.far_depth if args.far_depth is not None else preset["far_depth"]),
        "voxel_length": float(args.voxel_length if args.voxel_length is not None else preset["voxel_length"]),
        "sdf_trunc": float(args.sdf_trunc if args.sdf_trunc is not None else preset["sdf_trunc"]),
        "edge_crop": int(args.edge_crop if args.edge_crop is not None else preset["edge_crop"]),
    }


def load_manifest(session_dir: Path) -> dict:
    manifest_path = session_dir / "transforms.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"Missing transforms.json: {manifest_path}")
    return json.loads(manifest_path.read_text())


def build_output_dir(session_dir: Path, explicit_output_dir: Path | None) -> Path:
    if explicit_output_dir is not None:
        return explicit_output_dir.expanduser().resolve()
    return session_dir / "map_tsdf"


def load_rgb_image(image_path: Path) -> np.ndarray:
    with Image.open(image_path) as image:
        image = image.convert("RGB")
        return np.asarray(image)


def load_depth_image(depth_path: Path) -> np.ndarray:
    with Image.open(depth_path) as image:
        image.load()
        return np.asarray(image, dtype=np.uint16)


def resize_rgb_to_depth(color: np.ndarray, depth_width: int, depth_height: int) -> np.ndarray:
    image = Image.fromarray(color)
    resized = image.resize((depth_width, depth_height), Image.Resampling.BILINEAR)
    return np.asarray(resized)


def make_intrinsics(manifest: dict, width: int, height: int) -> o3d.camera.PinholeCameraIntrinsic:
    image_width = int(manifest["w"])
    image_height = int(manifest["h"])
    fx = float(manifest["fl_x"]) * width / max(image_width, 1)
    fy = float(manifest["fl_y"]) * height / max(image_height, 1)
    cx = float(manifest["cx"]) * width / max(image_width, 1)
    cy = float(manifest["cy"]) * height / max(image_height, 1)
    return o3d.camera.PinholeCameraIntrinsic(width, height, fx, fy, cx, cy)


def crop_depth_edges(depth: np.ndarray, edge_crop: int) -> np.ndarray:
    if edge_crop <= 0:
        return depth
    cropped = depth.copy()
    cropped[:edge_crop, :] = 0
    cropped[-edge_crop:, :] = 0
    cropped[:, :edge_crop] = 0
    cropped[:, -edge_crop:] = 0
    return cropped


def integrate_session(
    manifest: dict,
    session_dir: Path,
    near_depth: float,
    far_depth: float,
    voxel_length: float,
    sdf_trunc: float,
    edge_crop: int,
    max_frames: int,
):
    volume = o3d.pipelines.integration.ScalableTSDFVolume(
        voxel_length=voxel_length,
        sdf_trunc=sdf_trunc,
        color_type=o3d.pipelines.integration.TSDFVolumeColorType.RGB8,
    )

    integrated_frames = 0
    frames = manifest.get("frames", [])
    depth_scale = float(manifest.get("depth_scale", 1000.0))

    for frame in frames:
        if max_frames > 0 and integrated_frames >= max_frames:
            break

        image_path = session_dir / frame["file_path"]
        depth_relpath = frame.get("depth_file_path")
        if not depth_relpath:
            continue
        depth_path = session_dir / depth_relpath
        if not image_path.exists() or not depth_path.exists():
            continue

        color = load_rgb_image(image_path)
        depth_raw = load_depth_image(depth_path)
        depth_raw = crop_depth_edges(depth_raw, edge_crop)
        depth_height, depth_width = depth_raw.shape
        if color.shape[0] != depth_height or color.shape[1] != depth_width:
            color = resize_rgb_to_depth(color, depth_width, depth_height)

        depth_m = depth_raw.astype(np.float32) / depth_scale
        valid = np.isfinite(depth_m) & (depth_m >= near_depth) & (depth_m <= far_depth)
        if not np.any(valid):
            continue
        depth_raw = np.where(valid, depth_raw, 0).astype(np.uint16)

        color_o3d = o3d.geometry.Image(color)
        depth_o3d = o3d.geometry.Image(depth_raw)
        rgbd = o3d.geometry.RGBDImage.create_from_color_and_depth(
            color=color_o3d,
            depth=depth_o3d,
            depth_scale=depth_scale,
            depth_trunc=far_depth,
            convert_rgb_to_intensity=False,
        )

        intrinsics = make_intrinsics(manifest, depth_raw.shape[1], depth_raw.shape[0])
        camera_to_world = np.asarray(frame["transform_matrix"], dtype=np.float64)
        extrinsic = np.linalg.inv(camera_to_world)
        if not np.all(np.isfinite(extrinsic)):
            continue

        volume.integrate(rgbd, intrinsics, extrinsic)
        integrated_frames += 1

    mesh = volume.extract_triangle_mesh()
    mesh.compute_vertex_normals()
    pointcloud = volume.extract_point_cloud()
    return volume, mesh, pointcloud, integrated_frames


def save_preview(mesh: o3d.geometry.TriangleMesh, pointcloud: o3d.geometry.PointCloud, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    width = 1400
    height = 1000
    background = np.full((height, width, 3), 245, dtype=np.uint8)

    if len(mesh.vertices) > 0:
        points = np.asarray(mesh.vertices)
    else:
        points = np.asarray(pointcloud.points)

    if len(points) == 0:
        Image.fromarray(background).save(output_path)
        return

    center = points.mean(axis=0)
    shifted = points - center
    yaw = 0.75
    pitch = -0.4
    cy = np.cos(yaw)
    sy = np.sin(yaw)
    cp = np.cos(pitch)
    sp = np.sin(pitch)

    x1 = cy * shifted[:, 0] + sy * shifted[:, 2]
    z1 = -sy * shifted[:, 0] + cy * shifted[:, 2]
    y2 = cp * shifted[:, 1] - sp * z1
    z2 = sp * shifted[:, 1] + cp * z1
    rotated = np.stack([x1, y2, z2], axis=1)

    scale = np.max(np.ptp(rotated, axis=0)) or 1.0
    rotated /= scale
    depth_min = float(rotated[:, 2].min())
    depth_max = float(rotated[:, 2].max())
    order = np.argsort(rotated[:, 2])

    for idx in order:
        x, y, z = rotated[idx]
        px = int(width / 2 + x * 360)
        py = int(height / 2 - y * 360)
        if 0 <= px < width and 0 <= py < height:
            t = 0.0 if depth_max <= depth_min else (z - depth_min) / (depth_max - depth_min)
            background[py, px] = [int(35 + 170 * t), int(90 + 70 * (1.0 - t)), int(180 + 40 * (1.0 - t))]

    Image.fromarray(background).save(output_path)


def write_report(output_path: Path, stats: dict) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    html = f"""<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>OpenBene TSDF Map Report</title>
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
      <h1>OpenBene TSDF Map Report</h1>
      <div class=\"metric\">Session: <code>{stats['session_name']}</code></div>
      <div class=\"metric\">Frames integrated: {stats['integrated_frames']}</div>
      <div class=\"metric\">Mesh: <code>{stats['mesh_file']}</code></div>
    </div>
    <div class=\"grid\">
      <div class=\"card\">
        <h2>Preview</h2>
        <img src=\"map_preview_tsdf.png\" alt=\"TSDF map preview\" />
      </div>
      <div class=\"card\">
        <h2>Stats</h2>
        <div class=\"metric\">TSDF point count: {stats['pointcloud_point_count']}</div>
        <div class=\"metric\">Mesh vertices: {stats['mesh_vertex_count']}</div>
        <div class=\"metric\">Mesh triangles: {stats['mesh_triangle_count']}</div>
        <div class=\"metric\">Voxel length: {stats['voxel_length_m']} m</div>
        <div class=\"metric\">SDF truncation: {stats['sdf_trunc_m']} m</div>
        <div class=\"metric\">Depth clip: {stats['near_depth_m']} - {stats['far_depth_m']} m</div>
        <div class=\"metric\">Edge crop: {stats['edge_crop_px']} px</div>
      </div>
    </div>
  </div>
</body>
</html>
"""
    output_path.write_text(html, encoding="utf-8")


def main() -> None:
    args = parse_args()
    params = resolve_parameters(args)
    session_dir = args.session_dir.expanduser().resolve()
    output_dir = build_output_dir(session_dir, args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    manifest = load_manifest(session_dir)
    _, mesh, pointcloud, integrated_frames = integrate_session(
        manifest=manifest,
        session_dir=session_dir,
        near_depth=params["near_depth"],
        far_depth=params["far_depth"],
        voxel_length=params["voxel_length"],
        sdf_trunc=params["sdf_trunc"],
        edge_crop=max(0, params["edge_crop"]),
        max_frames=max(0, args.max_frames),
    )

    mesh_path = output_dir / "map_tsdf_mesh.ply"
    pointcloud_path = output_dir / "map_tsdf_pointcloud.ply"
    preview_path = output_dir / "map_preview_tsdf.png"
    metadata_path = output_dir / "map_tsdf_metadata.json"
    report_path = output_dir / "map_tsdf_report.html"

    o3d.io.write_triangle_mesh(str(mesh_path), mesh)
    o3d.io.write_point_cloud(str(pointcloud_path), pointcloud)
    save_preview(mesh, pointcloud, preview_path)

    stats = {
        "map_format_version": "openbene_session_map_tsdf_v1",
        "session_name": str(manifest.get("session_name", session_dir.name)),
        "session_mode": str(manifest.get("session_mode", "mapping")),
        "preset": params["preset"],
        "integrated_frames": int(integrated_frames),
        "pointcloud_point_count": int(len(pointcloud.points)),
        "mesh_vertex_count": int(len(mesh.vertices)),
        "mesh_triangle_count": int(len(mesh.triangles)),
        "near_depth_m": params["near_depth"],
        "far_depth_m": params["far_depth"],
        "voxel_length_m": params["voxel_length"],
        "sdf_trunc_m": params["sdf_trunc"],
        "edge_crop_px": int(max(0, params["edge_crop"])),
        "mesh_file": mesh_path.name,
        "pointcloud_file": pointcloud_path.name,
        "preview_file": preview_path.name,
        "report_file": report_path.name,
    }
    metadata_path.write_text(json.dumps(stats, indent=2), encoding="utf-8")
    write_report(report_path, stats)

    print(f"integrated_frames: {stats['integrated_frames']}")
    print(f"pointcloud_point_count: {stats['pointcloud_point_count']}")
    print(f"mesh_vertex_count: {stats['mesh_vertex_count']}")
    print(f"mesh_triangle_count: {stats['mesh_triangle_count']}")
    print(f"map_mesh: {mesh_path}")
    print(f"map_pointcloud: {pointcloud_path}")
    print(f"map_preview: {preview_path}")
    print(f"map_metadata: {metadata_path}")
    print(f"map_report: {report_path}")


if __name__ == "__main__":
    main()
