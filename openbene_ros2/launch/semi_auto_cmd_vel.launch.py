from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch.substitutions import PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare


def generate_launch_description() -> LaunchDescription:
    safety_config_file = LaunchConfiguration("safety_config_file")
    bridge_config_file = LaunchConfiguration("bridge_config_file")
    input_cmd_vel_topic = LaunchConfiguration("input_cmd_vel_topic")
    output_cmd_vel_topic = LaunchConfiguration("output_cmd_vel_topic")
    scan_topic = LaunchConfiguration("scan_topic")
    status_topic = LaunchConfiguration("status_topic")

    ip = LaunchConfiguration("ip")
    port = LaunchConfiguration("port")
    dry_run = LaunchConfiguration("dry_run")
    log_commands = LaunchConfiguration("log_commands")

    return LaunchDescription(
        [
            DeclareLaunchArgument(
                "safety_config_file",
                default_value=PathJoinSubstitution(
                    [FindPackageShare("openbene_ros2"), "config", "safety_cmd_vel.yaml"]
                ),
            ),
            DeclareLaunchArgument(
                "bridge_config_file",
                default_value=PathJoinSubstitution(
                    [FindPackageShare("openbene_ros2"), "config", "openbene_bridge.yaml"]
                ),
            ),
            DeclareLaunchArgument("input_cmd_vel_topic", default_value="/cmd_vel_user"),
            DeclareLaunchArgument("output_cmd_vel_topic", default_value="/cmd_vel_safe"),
            DeclareLaunchArgument("scan_topic", default_value="/scan"),
            DeclareLaunchArgument("status_topic", default_value="/openbene/safety/status"),
            DeclareLaunchArgument("ip", default_value=""),
            DeclareLaunchArgument("port", default_value="8765"),
            DeclareLaunchArgument("dry_run", default_value="false"),
            DeclareLaunchArgument("log_commands", default_value="true"),
            Node(
                package="openbene_ros2",
                executable="safety_cmd_vel",
                name="openbene_safety_cmd_vel",
                output="screen",
                parameters=[
                    safety_config_file,
                    {
                        "input_cmd_vel_topic": input_cmd_vel_topic,
                        "output_cmd_vel_topic": output_cmd_vel_topic,
                        "scan_topic": scan_topic,
                        "status_topic": status_topic,
                    },
                ],
            ),
            Node(
                package="openbene_ros2",
                executable="cmd_vel_bridge",
                name="openbene_cmd_vel_bridge",
                output="screen",
                parameters=[
                    bridge_config_file,
                    {
                        "ip": ip,
                        "port": port,
                        "cmd_vel_topic": output_cmd_vel_topic,
                        "dry_run": dry_run,
                        "log_commands": log_commands,
                    },
                ],
            ),
        ]
    )
