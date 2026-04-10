from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch.substitutions import PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare


def generate_launch_description() -> LaunchDescription:
    config_file = LaunchConfiguration("config_file")
    input_cmd_vel_topic = LaunchConfiguration("input_cmd_vel_topic")
    output_cmd_vel_topic = LaunchConfiguration("output_cmd_vel_topic")
    scan_topic = LaunchConfiguration("scan_topic")
    status_topic = LaunchConfiguration("status_topic")

    return LaunchDescription(
        [
            DeclareLaunchArgument(
                "config_file",
                default_value=PathJoinSubstitution(
                    [FindPackageShare("openbene_ros2"), "config", "safety_cmd_vel.yaml"]
                ),
            ),
            DeclareLaunchArgument("input_cmd_vel_topic", default_value="/cmd_vel_user"),
            DeclareLaunchArgument("output_cmd_vel_topic", default_value="/cmd_vel_safe"),
            DeclareLaunchArgument("scan_topic", default_value="/scan"),
            DeclareLaunchArgument("status_topic", default_value="/openbene/safety/status"),
            Node(
                package="openbene_ros2",
                executable="safety_cmd_vel",
                name="openbene_safety_cmd_vel",
                output="screen",
                parameters=[
                    config_file,
                    {
                        "input_cmd_vel_topic": input_cmd_vel_topic,
                        "output_cmd_vel_topic": output_cmd_vel_topic,
                        "scan_topic": scan_topic,
                        "status_topic": status_topic,
                    },
                ],
            ),
        ]
    )
