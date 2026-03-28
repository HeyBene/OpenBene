# OpenBene to ROS2 Dataflow

Current validated pipeline state:

- iPhone session capture works
- Session export works (`images/`, `depth/`, `transforms.json`, point cloud)
- PC-side TSDF mapping works with default preset `balanced`
- A second session can be ICP-aligned against the baseline map

## Current recommended baseline artifacts

- Baseline map session: `/Users/fandi/Downloads/session_1774588130`
- Default TSDF preset: `balanced`
- Baseline map point cloud:
  `/Users/fandi/Downloads/session_1774588130/tsdf_sweeps/02_balanced/map_tsdf_pointcloud.ply`
- Baseline map mesh:
  `/Users/fandi/Downloads/session_1774588130/tsdf_sweeps/02_balanced/map_tsdf_mesh.ply`

## Proposed ROS2 topic structure

### Capture topics

- `/openbene/camera/rgb/image_raw/compressed`
- `/openbene/camera/depth/image_raw`
- `/openbene/camera/camera_info`
- `/openbene/camera/pose`
- `/openbene/session/state`

### Mapping topics

- `/openbene/map/pointcloud`
- `/openbene/map/mesh`
- `/openbene/map/metadata`

### Relocalization topics

- `/openbene/relocalization/initial_guess`
- `/openbene/relocalization/refined_pose`
- `/openbene/relocalization/fitness`
- `/openbene/relocalization/status`

## Near-term node layout

### Node 1 - capture bridge

Input:
- iPhone WebSocket stream or exported session replay

Output:
- camera topics listed above

### Node 2 - map builder

Input:
- RGB
- depth
- pose
- intrinsics

Output:
- TSDF map artifacts
- map point cloud topic
- map metadata topic

### Node 3 - relocalization validator

Input:
- current frame/session cloud
- baseline map point cloud

Output:
- estimated transform
- fitness / RMSE
- relocalization status

## What is validated already

- Session `session_1774588130` serves as the baseline map source
- Session `session_1774602253` can be locally aligned against that baseline map with ICP
- This is enough to justify moving to a ROS2 message bridge next

## What still needs work before robust localization

- Global feature matching is not stable yet
- ICP works better than global registration, so the current system is best described as:
  `local geometric relocalization works better than global relocalization`
- We still need stronger source/map cropping, candidate retrieval, or descriptor improvements
