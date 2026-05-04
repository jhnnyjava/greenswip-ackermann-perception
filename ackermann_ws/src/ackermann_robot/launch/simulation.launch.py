import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription, TimerAction
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import Command, LaunchConfiguration, TextSubstitution
from launch_ros.actions import Node


def generate_launch_description():
    workspace_root = os.path.abspath(
        os.path.join(os.path.dirname(__file__), '../../../../')
    )

    xacro_file = os.path.join(workspace_root, 'ack.urdf.xacro')
    world_file = os.path.join(workspace_root, 'shapes.sdf')
    robot_description = Command(['xacro ', xacro_file])

    gz_sim = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(
                get_package_share_directory('ros_gz_sim'),
                'launch',
                'gz_sim.launch.py',
            )
        ),
        launch_arguments={'gz_args': LaunchConfiguration('gz_args')}.items(),
    )

    robot_state_publisher = Node(
        package='robot_state_publisher',
        executable='robot_state_publisher',
        output='screen',
        parameters=[{
            'use_sim_time': True,
            'robot_description': robot_description,
        }],
    )

    spawn_robot = Node(
        package='ros_gz_sim',
        executable='create',
        output='screen',
        arguments=[
            '-name', 'ackerman_simple',
            '-string', robot_description,
            '-x', '0.0',
            '-y', '0.0',
            '-z', '0.1',
        ],
    )

    bridge = Node(
        package='ros_gz_bridge',
        executable='parameter_bridge',
        output='screen',
        arguments=[
            '/camera/image@sensor_msgs/msg/Image@ignition.msgs.Image',
            '/clock@rosgraph_msgs/msg/Clock@ignition.msgs.Clock',
        ],
    )

    delayed_controller_spawners = TimerAction(
        period=3.0,
        actions=[
            Node(
                package='controller_manager',
                executable='spawner',
                output='screen',
                arguments=[
                    'joint_state_broadcaster',
                    '--controller-manager',
                    '/controller_manager',
                ],
            ),
            Node(
                package='controller_manager',
                executable='spawner',
                output='screen',
                arguments=[
                    'ackermann_steering_controller',
                    '--controller-manager',
                    '/controller_manager',
                ],
            ),
        ],
    )

    vision_node = Node(
        package='ackermann_perception',
        executable='vision_node',
        output='screen',
        parameters=[{'use_sim_time': True}],
    )

    control_node = Node(
        package='ackermann_control',
        executable='control_node',
        output='screen',
        parameters=[{'use_sim_time': True}],
    )

    return LaunchDescription([
        DeclareLaunchArgument(
            'gz_args',
            default_value=TextSubstitution(text=f'-r {world_file}'),
            description='Arguments passed to ros_gz_sim gz_sim.launch.py',
        ),
        gz_sim,
        robot_state_publisher,
        spawn_robot,
        bridge,
        delayed_controller_spawners,
        vision_node,
        control_node,
    ])