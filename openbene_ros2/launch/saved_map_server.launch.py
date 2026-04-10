from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue


def generate_launch_description() -> LaunchDescription:
    map_yaml = LaunchConfiguration("map_yaml")
    map_topic = LaunchConfiguration("map_topic")
    frame_id = LaunchConfiguration("frame_id")
    use_sim_time = LaunchConfiguration("use_sim_time")

    return LaunchDescription(
        [
            DeclareLaunchArgument("map_yaml"),
            DeclareLaunchArgument("map_topic", default_value="/map"),
            DeclareLaunchArgument("frame_id", default_value="map"),
            DeclareLaunchArgument("use_sim_time", default_value="false"),
            Node(
                package="nav2_map_server",
                executable="map_server",
                name="map_server",
                output="screen",
                parameters=[
                    {
                        "yaml_filename": map_yaml,
                        "topic_name": map_topic,
                        "frame_id": frame_id,
                        "use_sim_time": ParameterValue(use_sim_time, value_type=bool),
                    }
                ],
            ),
            Node(
                package="openbene_ros2",
                executable="lifecycle_bringup",
                name="openbene_saved_map_bringup",
                output="screen",
                parameters=[{"managed_nodes": ["map_server"]}],
            ),
        ]
    )
