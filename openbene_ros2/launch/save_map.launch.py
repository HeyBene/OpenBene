from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description() -> LaunchDescription:
    map_topic = LaunchConfiguration("map_topic")
    output_file_prefix = LaunchConfiguration("output_file_prefix")
    occupancy_threshold = LaunchConfiguration("occupancy_threshold")
    free_threshold = LaunchConfiguration("free_threshold")
    image_format = LaunchConfiguration("image_format")
    map_mode = LaunchConfiguration("map_mode")

    return LaunchDescription(
        [
            DeclareLaunchArgument("map_topic", default_value="/map"),
            DeclareLaunchArgument("output_file_prefix", default_value="openbene_map"),
            DeclareLaunchArgument("occupancy_threshold", default_value="0.65"),
            DeclareLaunchArgument("free_threshold", default_value="0.25"),
            DeclareLaunchArgument("image_format", default_value="pgm"),
            DeclareLaunchArgument("map_mode", default_value="trinary"),
            Node(
                package="nav2_map_server",
                executable="map_saver_cli",
                name="openbene_map_saver",
                output="screen",
                arguments=[
                    "-t",
                    map_topic,
                    "-f",
                    output_file_prefix,
                    "--occ",
                    occupancy_threshold,
                    "--free",
                    free_threshold,
                    "--fmt",
                    image_format,
                    "--mode",
                    map_mode,
                ],
            ),
        ]
    )
