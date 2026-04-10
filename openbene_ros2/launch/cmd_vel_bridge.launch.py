from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import PathJoinSubstitution
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare


def generate_launch_description() -> LaunchDescription:
    config_file = LaunchConfiguration("config_file")
    ip = LaunchConfiguration("ip")
    port = LaunchConfiguration("port")
    cmd_vel_topic = LaunchConfiguration("cmd_vel_topic")
    dry_run = LaunchConfiguration("dry_run")
    log_commands = LaunchConfiguration("log_commands")

    return LaunchDescription(
        [
            DeclareLaunchArgument(
                "config_file",
                default_value=PathJoinSubstitution(
                    [FindPackageShare("openbene_ros2"), "config", "openbene_bridge.yaml"]
                ),
            ),
            DeclareLaunchArgument("ip", default_value=""),
            DeclareLaunchArgument("port", default_value="8765"),
            DeclareLaunchArgument("cmd_vel_topic", default_value="/cmd_vel"),
            DeclareLaunchArgument("dry_run", default_value="false"),
            DeclareLaunchArgument("log_commands", default_value="true"),
            Node(
                package="openbene_ros2",
                executable="cmd_vel_bridge",
                name="openbene_cmd_vel_bridge",
                output="screen",
                parameters=[
                    config_file,
                    {
                        "ip": ip,
                        "port": port,
                        "cmd_vel_topic": cmd_vel_topic,
                        "dry_run": dry_run,
                        "log_commands": log_commands,
                    },
                ],
            ),
        ]
    )
