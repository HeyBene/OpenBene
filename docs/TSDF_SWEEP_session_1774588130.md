# TSDF Sweep - session_1774588130

Baseline session:
- Session dir: `/Users/fandi/Downloads/session_1774588130`
- Session mode: `mapping`
- Integrated frames: `64`

## Config 01 - near_clean

- Output dir: `/Users/fandi/Downloads/session_1774588130/tsdf_sweeps/01_near_clean`
- Parameters:
  - `near_depth_m = 0.2`
  - `far_depth_m = 1.8`
  - `voxel_length_m = 0.008`
  - `sdf_trunc_m = 0.03`
  - `edge_crop_px = 32`
- Results:
  - `pointcloud_point_count = 63494`
  - `mesh_vertex_count = 69177`
  - `mesh_triangle_count = 112435`
  - `report = /Users/fandi/Downloads/session_1774588130/tsdf_sweeps/01_near_clean/map_tsdf_report.html`

## Config 02 - balanced

- Output dir: `/Users/fandi/Downloads/session_1774588130/tsdf_sweeps/02_balanced`
- Parameters:
  - `near_depth_m = 0.15`
  - `far_depth_m = 2.0`
  - `voxel_length_m = 0.01`
  - `sdf_trunc_m = 0.04`
  - `edge_crop_px = 32`
- Results:
  - `pointcloud_point_count = 46582`
  - `mesh_vertex_count = 50478`
  - `mesh_triangle_count = 82162`
  - `report = /Users/fandi/Downloads/session_1774588130/tsdf_sweeps/02_balanced/map_tsdf_report.html`

## Config 03 - smooth_stable

- Output dir: `/Users/fandi/Downloads/session_1774588130/tsdf_sweeps/03_smooth_stable`
- Parameters:
  - `near_depth_m = 0.2`
  - `far_depth_m = 2.2`
  - `voxel_length_m = 0.015`
  - `sdf_trunc_m = 0.05`
  - `edge_crop_px = 40`
- Results:
  - `pointcloud_point_count = 15297`
  - `mesh_vertex_count = 16501`
  - `mesh_triangle_count = 26031`
  - `report = /Users/fandi/Downloads/session_1774588130/tsdf_sweeps/03_smooth_stable/map_tsdf_report.html`

## Notes

- `01_near_clean` is the densest and most aggressive near-range configuration.
- `02_balanced` is the best default candidate for general use because it keeps more structure than `03` while being less noisy than `01`.
- `03_smooth_stable` is the most conservative and smoothest configuration, but may oversimplify geometry.
