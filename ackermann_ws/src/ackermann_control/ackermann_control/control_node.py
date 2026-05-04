#!/usr/bin/env python3
# Copyright 2026 - MIT License
# Ackermann steering control node for target-following robot

import time
from math import tan

import rclpy
from ackermann_msgs.msg import AckermannDriveStamped
from geometry_msgs.msg import Point
from geometry_msgs.msg import TwistStamped
from rclpy.node import Node


class AckermannControlNode(Node):
    def __init__(self):
        super().__init__('ackermann_control_node')

        self.declare_parameter('wheelbase', 0.295)
        self.declare_parameter('max_steering_angle', 0.524)
        self.declare_parameter('image_width', 640.0)
        self.declare_parameter('image_center_x', 320.0)
        self.declare_parameter('target_distance_threshold', 30000.0)
        self.declare_parameter('target_search_timeout', 2.0)

        self.wheelbase = float(self.get_parameter('wheelbase').value)
        self.max_steering_angle = float(self.get_parameter('max_steering_angle').value)
        self.image_width = float(self.get_parameter('image_width').value)
        self.image_center_x = float(self.get_parameter('image_center_x').value)
        self.target_distance_threshold = float(
            self.get_parameter('target_distance_threshold').value
        )
        self.target_search_timeout = float(self.get_parameter('target_search_timeout').value)

        self.last_valid_target_time = time.monotonic()
        self._last_target = None

        self.target_sub = self.create_subscription(
            Point,
            '/target_info',
            self.target_callback,
            10,
        )
        self.cmd_pub = self.create_publisher(
            AckermannDriveStamped,
            '/ackermann_cmd',
            10,
        )
        self.controller_ref_pub = self.create_publisher(
            TwistStamped,
            '/ackermann_steering_controller/reference',
            10,
        )

        self.create_timer(0.05, self.control_loop)

        self.get_logger().info(
            'Ackermann control node initialized with '
            f'L={self.wheelbase:.3f}m, max steer={self.max_steering_angle:.3f}rad, '
            f'center={self.image_center_x:.1f}px, stop threshold={self.target_distance_threshold:.1f}px²'
        )

    def control_loop(self) -> None:
        current_time = time.monotonic()
        age = current_time - self.last_valid_target_time

        cmd_msg = AckermannDriveStamped()
        twist_msg = TwistStamped()
        cmd_msg.header.stamp = self.get_clock().now().to_msg()
        cmd_msg.header.frame_id = 'base_link'
        twist_msg.header.stamp = cmd_msg.header.stamp
        twist_msg.header.frame_id = 'base_link'

        def publish_motion(speed: float, steering_angle: float) -> None:
            cmd_msg.drive.speed = speed
            cmd_msg.drive.steering_angle = steering_angle

            twist_msg.twist.linear.x = speed
            if abs(self.wheelbase) > 1e-6:
                twist_msg.twist.angular.z = speed * tan(steering_angle) / self.wheelbase
            else:
                twist_msg.twist.angular.z = 0.0

            self.cmd_pub.publish(cmd_msg)
            self.controller_ref_pub.publish(twist_msg)

        if age > self.target_search_timeout:
            publish_motion(0.1, 0.3)
            return

        # If we are close enough, stop completely. For Ackermann robots, speed=0 implies steer=0.
        last_target = getattr(self, '_last_target', None)
        if last_target is not None:
            if last_target.z > self.target_distance_threshold:
                publish_motion(0.0, 0.0)
                return

            err = float(last_target.x) - self.image_center_x
            err_norm = max(-1.0, min(1.0, err / self.image_center_x))

            steering_angle = max(
                -self.max_steering_angle,
                min(self.max_steering_angle, err_norm * self.max_steering_angle),
            )

            abs_err = abs(err_norm)
            if abs_err < 0.1:
                speed = 0.4
            elif abs_err < 0.4:
                speed = 0.25
            else:
                speed = 0.15

            publish_motion(speed, steering_angle)
            return

        publish_motion(0.0, 0.0)

    def target_callback(self, msg: Point) -> None:
        if msg.x == -1.0:
            return
        self._last_target = msg
        self.last_valid_target_time = time.monotonic()


def main(args=None):
    rclpy.init(args=args)
    node = AckermannControlNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
