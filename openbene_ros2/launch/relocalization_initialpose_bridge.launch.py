from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
from launch_ros.parameter_descriptions import ParameterValue


def generate_launch_description() -> LaunchDescription:
    source_pose_topic = LaunchConfiguration("source_pose_topic")
    initialpose_topic = LaunchConfiguration("initialpose_topic")
    target_frame = LaunchConfiguration("target_frame")
    xy_stddev = LaunchConfiguration("xy_stddev")
    yaw_stddev = LaunchConfiguration("yaw_stddev")
    z_stddev = LaunchConfiguration("z_stddev")
    roll_pitch_stddev = LaunchConfiguration("roll_pitch_stddev")
    force_zero_z = LaunchConfiguration("force_zero_z")
    use_zero_stamp = LaunchConfiguration("use_zero_stamp")
    repeat_count = LaunchConfiguration("repeat_count")
    repeat_interval_sec = LaunchConfiguration("repeat_interval_sec")

    return LaunchDescription(
        [
            DeclareLaunchArgument("source_pose_topic", default_value="/openbene/relocalization/refined_initial_pose"),
            DeclareLaunchArgument("initialpose_topic", default_value="/initialpose"),
            DeclareLaunchArgument("target_frame", default_value=""),
            DeclareLaunchArgument("xy_stddev", default_value="0.15"),
            DeclareLaunchArgument("yaw_stddev", default_value="0.25"),
            DeclareLaunchArgument("z_stddev", default_value="0.0"),
            DeclareLaunchArgument("roll_pitch_stddev", default_value="0.0"),
            DeclareLaunchArgument("force_zero_z", default_value="true"),
            DeclareLaunchArgument("use_zero_stamp", default_value="true"),
            DeclareLaunchArgument("repeat_count", default_value="3"),
            DeclareLaunchArgument("repeat_interval_sec", default_value="0.35"),
            Node(
                package="openbene_ros2",
                executable="relocalization_initialpose_bridge",
                name="openbene_relocalization_initialpose_bridge",
                output="screen",
                parameters=[
                    {
                        "source_pose_topic": source_pose_topic,
                        "initialpose_topic": initialpose_topic,
                        "target_frame": target_frame,
                        "xy_stddev": ParameterValue(xy_stddev, value_type=float),
                        "yaw_stddev": ParameterValue(yaw_stddev, value_type=float),
                        "z_stddev": ParameterValue(z_stddev, value_type=float),
                        "roll_pitch_stddev": ParameterValue(roll_pitch_stddev, value_type=float),
                        "force_zero_z": ParameterValue(force_zero_z, value_type=bool),
                        "use_zero_stamp": ParameterValue(use_zero_stamp, value_type=bool),
                        "repeat_count": ParameterValue(repeat_count, value_type=int),
                        "repeat_interval_sec": ParameterValue(repeat_interval_sec, value_type=float),
                    }
                ],
            ),
        ]
    )
