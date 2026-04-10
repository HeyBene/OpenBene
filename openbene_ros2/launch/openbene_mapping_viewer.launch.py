from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.actions import SetEnvironmentVariable
from launch.substitutions import LaunchConfiguration
from launch.substitutions import PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare


def generate_launch_description() -> LaunchDescription:
    rviz_config = LaunchConfiguration("rviz_config")

    return LaunchDescription(
        [
            DeclareLaunchArgument(
                "rviz_config",
                default_value=PathJoinSubstitution(
                    [FindPackageShare("openbene_ros2"), "rviz", "openbene_mapping.rviz"]
                ),
            ),
            # WSLg + RViz can fail with a black window under hardware GL.
            SetEnvironmentVariable("LIBGL_ALWAYS_SOFTWARE", "1"),
            SetEnvironmentVariable("QT_XCB_GL_INTEGRATION", "none"),
            Node(
                package="rviz2",
                executable="rviz2",
                name="openbene_mapping_viewer",
                output="screen",
                arguments=["-d", rviz_config],
            ),
        ]
    )
