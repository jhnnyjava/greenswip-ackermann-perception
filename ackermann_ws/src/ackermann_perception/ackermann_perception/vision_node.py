#!/usr/bin/env python3
# Copyright 2026 - MIT License
# Vision node for detecting the red target box in the camera feed.

import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Image
from geometry_msgs.msg import Point
from cv_bridge import CvBridge
import cv2
import numpy as np


class VisionNode(Node):
    def __init__(self):
        super().__init__('vision_node')

        self.cv_bridge = CvBridge()

        self.image_sub = self.create_subscription(
            Image,
            '/camera/image',
            self.image_callback,
            10,
        )
        self.target_pub = self.create_publisher(Point, '/target_info', 10)
        self.debug_pub = self.create_publisher(Image, '/vision_debug', 10)

        self.get_logger().info('vision_node ready')

    def image_callback(self, msg: Image) -> None:
        try:
            cv_image = self.cv_bridge.imgmsg_to_cv2(msg, desired_encoding='bgr8')
        except Exception as exc:
            self.get_logger().error(f'cv_bridge conversion failed: {exc}')
            fallback = Point()
            fallback.x = -1.0
            fallback.y = -1.0
            fallback.z = 0.0
            self.target_pub.publish(fallback)
            return

        hsv_image = cv2.cvtColor(cv_image, cv2.COLOR_BGR2HSV)

        # Red wraps around 0 degrees in HSV, so we need two masks and then combine them.
        lower_red1 = np.array([0, 100, 80], dtype=np.uint8)
        upper_red1 = np.array([10, 255, 255], dtype=np.uint8)
        lower_red2 = np.array([170, 100, 80], dtype=np.uint8)
        upper_red2 = np.array([180, 255, 255], dtype=np.uint8)

        red_mask = cv2.inRange(hsv_image, lower_red1, upper_red1)
        red_mask |= cv2.inRange(hsv_image, lower_red2, upper_red2)

        # Clean up isolated pixels and small gaps so the contour tests see a single box-like blob.
        kernel = np.ones((5, 5), np.uint8)
        red_mask = cv2.morphologyEx(red_mask, cv2.MORPH_OPEN, kernel, iterations=1)
        red_mask = cv2.morphologyEx(red_mask, cv2.MORPH_CLOSE, kernel, iterations=2)

        contours, _ = cv2.findContours(red_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        debug_image = cv_image.copy()
        best_detection = None
        best_area = 0.0

        for contour in contours:
            # Reject tiny contours early to avoid noise and compression artifacts.
            contour_area = cv2.contourArea(contour)
            if contour_area < 500:
                continue

            x, y, w, h = cv2.boundingRect(contour)
            if w <= 0 or h <= 0:
                continue

            # A cube viewed by a camera should look roughly square, so we require a moderate aspect ratio.
            aspect_ratio = float(w) / float(h)
            if not (0.6 <= aspect_ratio <= 1.6):
                continue

            # Solidity helps reject hollow, broken, or thin shapes while keeping the solid red box.
            hull = cv2.convexHull(contour)
            hull_area = cv2.contourArea(hull)
            if hull_area <= 0:
                continue
            solidity = contour_area / hull_area
            if solidity <= 0.80:
                continue

            # The red box should have a simple polygonal outline, unlike the curved decoys.
            perimeter = cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, 0.04 * perimeter, True)
            num_corners = len(approx)
            if not (4 <= num_corners <= 8):
                continue

            moments = cv2.moments(contour)
            if moments['m00'] == 0:
                continue

            centroid_x = int(moments['m10'] / moments['m00'])
            centroid_y = int(moments['m01'] / moments['m00'])
            box_area = float(w * h)

            if box_area > best_area:
                best_area = box_area
                best_detection = {
                    'centroid_x': centroid_x,
                    'centroid_y': centroid_y,
                    'box_area': box_area,
                    'rect': (x, y, w, h),
                }

        if best_detection is not None:
            x, y, w, h = best_detection['rect']

            # Draw the green bounding rectangle so the debug image shows the selected box clearly.
            cv2.rectangle(debug_image, (x, y), (x + w, y + h), (0, 255, 0), 2)
            cv2.circle(
                debug_image,
                (best_detection['centroid_x'], best_detection['centroid_y']),
                4,
                (0, 255, 0),
                -1,
            )

            target_msg = Point()
            target_msg.x = float(best_detection['centroid_x'])
            target_msg.y = float(best_detection['centroid_y'])
            target_msg.z = float(best_detection['box_area'])
            self.target_pub.publish(target_msg)
        else:
            # Sentinel makes downstream control logic unambiguous when no target is visible.
            sentinel = Point()
            sentinel.x = -1.0
            sentinel.y = -1.0
            sentinel.z = 0.0
            self.target_pub.publish(sentinel)

        try:
            debug_msg = self.cv_bridge.cv2_to_imgmsg(debug_image, encoding='bgr8')
            self.debug_pub.publish(debug_msg)
        except Exception as exc:
            self.get_logger().error(f'Failed to publish debug image: {exc}')


def main(args=None):
    rclpy.init(args=args)
    node = VisionNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()
