from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue
from launch_ros.substitutions import FindPackageShare


def generate_launch_description() -> LaunchDescription:
    amcl_params_default = PathJoinSubstitution(
        [FindPackageShare("openbene_ros2"), "config", "amcl_openbene.yaml"]
    )

    map_yaml = LaunchConfiguration("map_yaml")
    dataset_dir = LaunchConfiguration("dataset_dir")
    amcl_params_file = LaunchConfiguration("amcl_params_file")
    scan_topic = LaunchConfiguration("scan_topic")
    frame_id = LaunchConfiguration("frame_id")
    base_frame = LaunchConfiguration("base_frame")
    odom_frame = LaunchConfiguration("odom_frame")
    map_frame = LaunchConfiguration("map_frame")
    publish_period_sec = LaunchConfiguration("publish_period_sec")
    range_min_m = LaunchConfiguration("range_min_m")
    range_max_m = LaunchConfiguration("range_max_m")
    use_sim_time = LaunchConfiguration("use_sim_time")
    repeat = LaunchConfiguration("repeat")
    frame_start = LaunchConfiguration("frame_start")
    frame_count = LaunchConfiguration("frame_count")
    tail_frames = LaunchConfiguration("tail_frames")

    return LaunchDescription(
        [
            DeclareLaunchArgument("map_yaml"),
            DeclareLaunchArgument("dataset_dir"),
            DeclareLaunchArgument("amcl_params_file", default_value=amcl_params_default),
            DeclareLaunchArgument("scan_topic", default_value="/scan"),
            DeclareLaunchArgument("frame_id", default_value="openbene_depth_frame"),
            DeclareLaunchArgument("base_frame", default_value="openbene_base"),
            DeclareLaunchArgument("odom_frame", default_value="odom"),
            DeclareLaunchArgument("map_frame", default_value="map"),
            DeclareLaunchArgument("publish_period_sec", default_value="0.2"),
            DeclareLaunchArgument("range_min_m", default_value="0.15"),
            DeclareLaunchArgument("range_max_m", default_value="5.0"),
            DeclareLaunchArgument("use_sim_time", default_value="false"),
            DeclareLaunchArgument("repeat", default_value="true"),
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
                        "range_min_m": ParameterValue(range_min_m, value_type=float),
                        "range_max_m": ParameterValue(range_max_m, value_type=float),
                        "repeat": ParameterValue(repeat, value_type=bool),
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
                package="nav2_map_server",
                executable="map_server",
                name="map_server",
                output="screen",
                parameters=[
                    {
                        "yaml_filename": map_yaml,
                        "topic_name": "/map",
                        "frame_id": map_frame,
                        "use_sim_time": ParameterValue(use_sim_time, value_type=bool),
                    }
                ],
            ),
            Node(
                package="nav2_amcl",
                executable="amcl",
                name="amcl",
                output="screen",
                parameters=[
                    amcl_params_file,
                    {
                        "use_sim_time": ParameterValue(use_sim_time, value_type=bool),
                        "scan_topic": scan_topic,
                        "base_frame_id": base_frame,
                        "odom_frame_id": odom_frame,
                        "global_frame_id": map_frame,
                    },
                ],
            ),
            Node(
                package="nav2_lifecycle_manager",
                executable="lifecycle_manager",
                name="lifecycle_manager_localization",
                output="screen",
                parameters=[
                    {
                        "use_sim_time": ParameterValue(use_sim_time, value_type=bool),
                        "autostart": True,
                        "node_names": ["map_server", "amcl"],
                    }
                ],
            ),
        ]
    )
