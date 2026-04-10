from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description() -> LaunchDescription:
    return LaunchDescription(
        [
            Node(
                package="openbene_ros2",
                executable="cmd_vel_bridge",
                name="openbene_cmd_vel_bridge",
                output="screen",
                parameters=[
                    {
                        "cmd_vel_topic": "/cmd_vel",
                        "dry_run": True,
                        "log_commands": True,
                    }
                ],
            ),
            Node(
                package="openbene_ros2",
                executable="cmd_vel_demo",
                name="openbene_cmd_vel_demo",
                output="screen",
                parameters=[
                    {
                        "cmd_vel_topic": "/cmd_vel",
                        "loop": True,
                    }
                ],
            ),
        ]
    )
