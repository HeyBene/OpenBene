from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue


def generate_launch_description() -> LaunchDescription:
    return LaunchDescription(
        [
            DeclareLaunchArgument("host", default_value="0.0.0.0"),
            DeclareLaunchArgument("port", default_value="8765"),
            DeclareLaunchArgument("output_root_dir", default_value="~/openbene_captured_sessions"),
            DeclareLaunchArgument("scan_topic", default_value="/scan"),
            DeclareLaunchArgument("camera_info_topic", default_value="/openbene/camera_info"),
            DeclareLaunchArgument("frame_id", default_value="openbene_depth_frame"),
            DeclareLaunchArgument("band_center_ratio", default_value="0.5"),
            DeclareLaunchArgument("band_height", default_value="5"),
            DeclareLaunchArgument("range_min_m", default_value="0.15"),
            DeclareLaunchArgument("range_max_m", default_value="5.0"),
            DeclareLaunchArgument("confidence_min_value", default_value="1"),
            DeclareLaunchArgument("accepted_tracking_states", default_value="normal"),
            DeclareLaunchArgument("allow_missing_tracking_state", default_value="true"),
            DeclareLaunchArgument("accepted_depth_sources", default_value=""),
            DeclareLaunchArgument("allow_missing_depth_source", default_value="true"),
            DeclareLaunchArgument("publish_camera_info", default_value="true"),
            DeclareLaunchArgument("publish_odom_tf", default_value="false"),
            DeclareLaunchArgument("odom_frame", default_value="odom"),
            DeclareLaunchArgument("base_frame", default_value="openbene_base"),
            Node(
                package="openbene_ros2",
                executable="live_capture_scan_server",
                name="openbene_live_capture_scan_server",
                output="screen",
                parameters=[
                    {
                        "host": LaunchConfiguration("host"),
                        "port": ParameterValue(LaunchConfiguration("port"), value_type=int),
                        "output_root_dir": LaunchConfiguration("output_root_dir"),
                        "scan_topic": LaunchConfiguration("scan_topic"),
                        "camera_info_topic": LaunchConfiguration("camera_info_topic"),
                        "frame_id": LaunchConfiguration("frame_id"),
                        "band_center_ratio": ParameterValue(
                            LaunchConfiguration("band_center_ratio"),
                            value_type=float,
                        ),
                        "band_height": ParameterValue(
                            LaunchConfiguration("band_height"),
                            value_type=int,
                        ),
                        "range_min_m": ParameterValue(
                            LaunchConfiguration("range_min_m"),
                            value_type=float,
                        ),
                        "range_max_m": ParameterValue(
                            LaunchConfiguration("range_max_m"),
                            value_type=float,
                        ),
                        "confidence_min_value": ParameterValue(
                            LaunchConfiguration("confidence_min_value"),
                            value_type=int,
                        ),
                        "accepted_tracking_states": LaunchConfiguration("accepted_tracking_states"),
                        "allow_missing_tracking_state": ParameterValue(
                            LaunchConfiguration("allow_missing_tracking_state"),
                            value_type=bool,
                        ),
                        "accepted_depth_sources": LaunchConfiguration("accepted_depth_sources"),
                        "allow_missing_depth_source": ParameterValue(
                            LaunchConfiguration("allow_missing_depth_source"),
                            value_type=bool,
                        ),
                        "publish_camera_info": ParameterValue(
                            LaunchConfiguration("publish_camera_info"),
                            value_type=bool,
                        ),
                        "publish_odom_tf": ParameterValue(
                            LaunchConfiguration("publish_odom_tf"),
                            value_type=bool,
                        ),
                        "odom_frame": LaunchConfiguration("odom_frame"),
                        "base_frame": LaunchConfiguration("base_frame"),
                    }
                ],
            ),
        ]
    )
