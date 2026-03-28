#!/usr/bin/env python3
"""
Validate whether a session can relocalize against an existing map point cloud.

This is a first-pass geometry relocalization tool. It uses Open3D global feature
matching + ICP refinement between:
- a source session-derived point cloud
- a target map point cloud

Run with the Open3D conda environment:
    conda run -n openbene-map python openbene_sdk/src/openbene/session_relocalization_validator.py \
      --session /path/to/session \
      --map-pointcloud /path/to/map_tsdf_pointcloud.ply
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import open3d as o3d


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate relocalization against an existing map")
    parser.add_argument("--session", type=Path, required=True, help="Session directory")
    parser.add_argument("--map-pointcloud", type=Path, required=True, help="Reference map pointcloud PLY")
    parser.add_argument("--voxel-size", type=float, default=0.03, help="Voxel size for registration")
    parser.add_argument("--crop-radius", type=float, default=2.5, help="Crop relocalization clouds around session centroid (meters)")
    parser.add_argument("--source-stride", type=int, default=8, help="Depth sampling stride for source cloud")
    parser.add_argument("--source-near-depth", type=float, default=0.15, help="Source near depth clip")
    parser.add_argument("--source-far-depth", type=float, default=2.0, help="Source far depth clip")
    parser.add_argument("--output", type=Path, default=None, help="Optional JSON report path")
    return parser.parse_args()


def load_manifest(session_dir: Path) -> dict:
    manifest_path = session_dir / "transforms.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"Missing transforms.json: {manifest_path}")
    return json.loads(manifest_path.read_text())


def sample_session_points(manifest: dict, session_dir: Path, sample_stride: int = 8, near_depth: float = 0.15, far_depth: float = 2.0) -> np.ndarray:
    from PIL import Image

    frames = manifest.get("frames", [])
    image_width = int(manifest["w"])
    image_height = int(manifest["h"])
    depth_scale = float(manifest.get("depth_scale", 1000.0))
    all_points = []

    for frame in frames:
        depth_relpath = frame.get("depth_file_path")
        if not depth_relpath:
            continue
        depth_path = session_dir / depth_relpath
        if not depth_path.exists():
            continue

        with Image.open(depth_path) as image:
            depth = np.asarray(image, dtype=np.uint16).astype(np.float32) / depth_scale

        depth_h, depth_w = depth.shape
        fx = float(manifest["fl_x"]) * depth_w / max(image_width, 1)
        fy = float(manifest["fl_y"]) * depth_h / max(image_height, 1)
        cx = float(manifest["cx"]) * depth_w / max(image_width, 1)
        cy = float(manifest["cy"]) * depth_h / max(image_height, 1)

        ys = np.arange(0, depth_h, sample_stride, dtype=np.int32)
        xs = np.arange(0, depth_w, sample_stride, dtype=np.int32)
        grid_x, grid_y = np.meshgrid(xs, ys)
        sampled_depth = depth[grid_y, grid_x]
        valid = np.isfinite(sampled_depth) & (sampled_depth >= near_depth) & (sampled_depth <= far_depth)
        if not np.any(valid):
            continue

        z = sampled_depth[valid]
        x = (grid_x[valid].astype(np.float32) - cx) / fx * z
        y = (grid_y[valid].astype(np.float32) - cy) / fy * z
        camera_points = np.stack([x, y, z], axis=1)
        transform = np.asarray(frame["transform_matrix"], dtype=np.float64)
        world_points = (transform[:3, :3] @ camera_points.T).T + transform[:3, 3]
        world_points = world_points[np.all(np.isfinite(world_points), axis=1)]
        if world_points.size > 0:
            all_points.append(world_points)

    if not all_points:
        return np.zeros((0, 3), dtype=np.float64)
    return np.concatenate(all_points, axis=0)


def preprocess_cloud(cloud: o3d.geometry.PointCloud, voxel_size: float):
    down = cloud.voxel_down_sample(voxel_size)
    down.estimate_normals(o3d.geometry.KDTreeSearchParamHybrid(radius=voxel_size * 2.0, max_nn=30))
    feature = o3d.pipelines.registration.compute_fpfh_feature(
        down,
        o3d.geometry.KDTreeSearchParamHybrid(radius=voxel_size * 5.0, max_nn=100),
    )
    return down, feature


def crop_cloud_around_center(cloud: o3d.geometry.PointCloud, radius: float) -> o3d.geometry.PointCloud:
    if radius <= 0 or len(cloud.points) == 0:
        return cloud
    points = np.asarray(cloud.points)
    center = points.mean(axis=0)
    distances = np.linalg.norm(points - center, axis=1)
    mask = distances <= radius
    if not np.any(mask):
        return cloud
    indices = np.where(mask)[0].tolist()
    return cloud.select_by_index(indices)


def main() -> None:
    args = parse_args()
    session_dir = args.session.expanduser().resolve()
    map_pointcloud_path = args.map_pointcloud.expanduser().resolve()
    output_path = args.output.expanduser().resolve() if args.output else session_dir / "relocalization_report.json"

    manifest = load_manifest(session_dir)
    session_points = sample_session_points(
        manifest,
        session_dir,
        sample_stride=max(1, args.source_stride),
        near_depth=args.source_near_depth,
        far_depth=args.source_far_depth,
    )

    source = o3d.geometry.PointCloud()
    source.points = o3d.utility.Vector3dVector(session_points)
    target = o3d.io.read_point_cloud(str(map_pointcloud_path))
    source = crop_cloud_around_center(source, args.crop_radius)
    target = crop_cloud_around_center(target, args.crop_radius * 1.25)

    source_down, source_fpfh = preprocess_cloud(source, args.voxel_size)
    target_down, target_fpfh = preprocess_cloud(target, args.voxel_size)

    distance_threshold = args.voxel_size * 1.5
    global_result = o3d.pipelines.registration.registration_ransac_based_on_feature_matching(
        source_down,
        target_down,
        source_fpfh,
        target_fpfh,
        mutual_filter=True,
        max_correspondence_distance=distance_threshold,
        estimation_method=o3d.pipelines.registration.TransformationEstimationPointToPoint(False),
        ransac_n=4,
        checkers=[
            o3d.pipelines.registration.CorrespondenceCheckerBasedOnEdgeLength(0.9),
            o3d.pipelines.registration.CorrespondenceCheckerBasedOnDistance(distance_threshold),
        ],
        criteria=o3d.pipelines.registration.RANSACConvergenceCriteria(100000, 0.999),
    )

    icp_result = o3d.pipelines.registration.registration_icp(
        source,
        target,
        max_correspondence_distance=args.voxel_size,
        init=global_result.transformation,
        estimation_method=o3d.pipelines.registration.TransformationEstimationPointToPlane(),
    )

    fine_icp_result = o3d.pipelines.registration.registration_icp(
        source,
        target,
        max_correspondence_distance=args.voxel_size * 0.6,
        init=icp_result.transformation,
        estimation_method=o3d.pipelines.registration.TransformationEstimationPointToPlane(),
    )

    report = {
        "session_dir": str(session_dir),
        "map_pointcloud": str(map_pointcloud_path),
        "voxel_size": float(args.voxel_size),
        "crop_radius": float(args.crop_radius),
        "source_stride": int(max(1, args.source_stride)),
        "source_near_depth": float(args.source_near_depth),
        "source_far_depth": float(args.source_far_depth),
        "source_raw_points": int(len(source.points)),
        "source_down_points": int(len(source_down.points)),
        "target_down_points": int(len(target_down.points)),
        "global_fitness": float(global_result.fitness),
        "global_rmse": float(global_result.inlier_rmse),
        "icp_fitness": float(icp_result.fitness),
        "icp_rmse": float(icp_result.inlier_rmse),
        "fine_icp_fitness": float(fine_icp_result.fitness),
        "fine_icp_rmse": float(fine_icp_result.inlier_rmse),
        "transformation": np.asarray(fine_icp_result.transformation).tolist(),
    }
    output_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"source_raw_points: {report['source_raw_points']}")
    print(f"source_down_points: {report['source_down_points']}")
    print(f"target_down_points: {report['target_down_points']}")
    print(f"global_fitness: {report['global_fitness']:.4f}")
    print(f"global_rmse: {report['global_rmse']:.4f}")
    print(f"icp_fitness: {report['icp_fitness']:.4f}")
    print(f"icp_rmse: {report['icp_rmse']:.4f}")
    print(f"fine_icp_fitness: {report['fine_icp_fitness']:.4f}")
    print(f"fine_icp_rmse: {report['fine_icp_rmse']:.4f}")
    print(f"report: {output_path}")


if __name__ == "__main__":
    main()
