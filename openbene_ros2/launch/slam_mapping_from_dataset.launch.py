from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue
from launch_ros.substitutions import FindPackageShare


def generate_launch_description() -> LaunchDescription:
    slam_params_default = PathJoinSubstitution(
        [FindPackageShare("openbene_ros2"), "config", "slam_toolbox_openbene.yaml"]
    )

    dataset_dir = LaunchConfiguration("dataset_dir")
    scan_topic = LaunchConfiguration("scan_topic")
    frame_id = LaunchConfiguration("frame_id")
    base_frame = LaunchConfiguration("base_frame")
    odom_frame = LaunchConfiguration("odom_frame")
    map_frame = LaunchConfiguration("map_frame")
    publish_period_sec = LaunchConfiguration("publish_period_sec")
    band_center_ratio = LaunchConfiguration("band_center_ratio")
    band_height = LaunchConfiguration("band_height")
    range_min_m = LaunchConfiguration("range_min_m")
    range_max_m = LaunchConfiguration("range_max_m")
    confidence_min_value = LaunchConfiguration("confidence_min_value")
    accepted_tracking_states = LaunchConfiguration("accepted_tracking_states")
    allow_missing_tracking_state = LaunchConfiguration("allow_missing_tracking_state")
    accepted_depth_sources = LaunchConfiguration("accepted_depth_sources")
    allow_missing_depth_source = LaunchConfiguration("allow_missing_depth_source")
    slam_params_file = LaunchConfiguration("slam_params_file")
    use_sim_time = LaunchConfiguration("use_sim_time")
    frame_start = LaunchConfiguration("frame_start")
    frame_count = LaunchConfiguration("frame_count")
    tail_frames = LaunchConfiguration("tail_frames")

    return LaunchDescription(
        [
            DeclareLaunchArgument("dataset_dir", default_value=""),
            DeclareLaunchArgument("scan_topic", default_value="/scan"),
            DeclareLaunchArgument("frame_id", default_value="openbene_depth_frame"),
            DeclareLaunchArgument("base_frame", default_value="openbene_base"),
            DeclareLaunchArgument("odom_frame", default_value="odom"),
            DeclareLaunchArgument("map_frame", default_value="map"),
            DeclareLaunchArgument("publish_period_sec", default_value="0.2"),
            DeclareLaunchArgument("band_center_ratio", default_value="0.5"),
            DeclareLaunchArgument("band_height", default_value="5"),
            DeclareLaunchArgument("range_min_m", default_value="0.15"),
            DeclareLaunchArgument("range_max_m", default_value="5.0"),
            DeclareLaunchArgument("confidence_min_value", default_value="1"),
            DeclareLaunchArgument("accepted_tracking_states", default_value="normal"),
            DeclareLaunchArgument("allow_missing_tracking_state", default_value="true"),
            DeclareLaunchArgument("accepted_depth_sources", default_value=""),
            DeclareLaunchArgument("allow_missing_depth_source", default_value="true"),
            DeclareLaunchArgument("use_sim_time", default_value="false"),
            DeclareLaunchArgument("slam_params_file", default_value=slam_params_default),
            DeclareLaunchArgument("frame_start", default_value="0"),
            DeclareLaunchArgument("frame_count", default_value="0"),
            DeclareLaunchArgument("tail_frames", default_value="0"),
            Node(
                package="tf2_ros",
                executable="static_transform_publisher",
                name="openbene_base_to_scan_tf",
                arguments=["0", "0", "0", "0", "0", "0", base_frame, frame_id],
                output="screen",
            ),
            Node(
                package="openbene_ros2",
                executable="dataset_scan_replay",
                name="openbene_dataset_scan_replay",
                output="screen",
                parameters=[
                    {
                        "dataset_dir": dataset_dir,
                        "scan_topic": scan_topic,
                        "camera_info_topic": "/openbene/camera_info",
                        "frame_id": frame_id,
                        "publish_period_sec": ParameterValue(publish_period_sec, value_type=float),
                        "band_center_ratio": ParameterValue(band_center_ratio, value_type=float),
                        "band_height": ParameterValue(band_height, value_type=int),
                        "range_min_m": ParameterValue(range_min_m, value_type=float),
                        "range_max_m": ParameterValue(range_max_m, value_type=float),
                        "confidence_min_value": ParameterValue(confidence_min_value, value_type=int),
                        "accepted_tracking_states": accepted_tracking_states,
                        "allow_missing_tracking_state": ParameterValue(
                            allow_missing_tracking_state,
                            value_type=bool,
                        ),
                        "accepted_depth_sources": accepted_depth_sources,
                        "allow_missing_depth_source": ParameterValue(
                            allow_missing_depth_source,
                            value_type=bool,
                        ),
                        "repeat": False,
                        "publish_camera_info": False,
                        "publish_odom_tf": True,
                        "odom_frame": odom_frame,
                        "base_frame": base_frame,
                        "frame_start": ParameterValue(frame_start, value_type=int),
                        "frame_count": ParameterValue(frame_count, value_type=int),
                        "tail_frames": ParameterValue(tail_frames, value_type=int),
                    }
                ],
            ),
            Node(
                package="slam_toolbox",
                executable="async_slam_toolbox_node",
                name="slam_toolbox",
                output="screen",
                parameters=[
                    slam_params_file,
                    {
                        "use_sim_time": ParameterValue(use_sim_time, value_type=bool),
                        "scan_topic": scan_topic,
                        "odom_frame": odom_frame,
                        "base_frame": base_frame,
                        "map_frame": map_frame,
                        "minimum_time_interval": ParameterValue(publish_period_sec, value_type=float),
                        "min_laser_range": ParameterValue(range_min_m, value_type=float),
                        "max_laser_range": ParameterValue(range_max_m, value_type=float),
                    },
                ],
            ),
        ]
    )
