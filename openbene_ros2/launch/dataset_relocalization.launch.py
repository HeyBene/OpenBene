from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description() -> LaunchDescription:
    report_path = LaunchConfiguration("report_path")
    session_dir = LaunchConfiguration("session_dir")
    map_pointcloud = LaunchConfiguration("map_pointcloud")
    world_frame = LaunchConfiguration("world_frame")
    output_report_path = LaunchConfiguration("output_report_path")
    source_frame_start = LaunchConfiguration("source_frame_start")
    source_frame_count = LaunchConfiguration("source_frame_count")
    source_tail_frames = LaunchConfiguration("source_tail_frames")

    return LaunchDescription(
        [
            DeclareLaunchArgument("report_path", default_value=""),
            DeclareLaunchArgument("session_dir"),
            DeclareLaunchArgument("map_pointcloud"),
            DeclareLaunchArgument("world_frame", default_value="openbene_map"),
            DeclareLaunchArgument("output_report_path", default_value=""),
            DeclareLaunchArgument("source_frame_start", default_value="0"),
            DeclareLaunchArgument("source_frame_count", default_value="0"),
            DeclareLaunchArgument("source_tail_frames", default_value="0"),
            Node(
                package="openbene_ros2",
                executable="dataset_relocalization",
                name="openbene_dataset_relocalization",
                output="screen",
                parameters=[
                    {
                        "report_path": report_path,
                        "session_dir": session_dir,
                        "map_pointcloud": map_pointcloud,
                        "world_frame": world_frame,
                        "output_report_path": output_report_path,
                        "source_frame_start": source_frame_start,
                        "source_frame_count": source_frame_count,
                        "source_tail_frames": source_tail_frames,
                    }
                ],
            ),
        ]
    )
