#!/bin/bash
set -e

echo "Stopping existing ackermann_viz container (if present)..."
docker rm -f ackermann_viz 2>/dev/null || true

echo "Allowing local docker access to X server..."
xhost +local:docker >/dev/null 2>&1 || true

# Add /dev/dri if present
device_opt=""
if [ -d /dev/dri ]; then
  device_opt="--device /dev/dri"
  echo "Found /dev/dri on host — enabling device passthrough."
fi

echo "Launching ackermann_viz container (RViz + joint sliders)..."

docker run --rm -d \
  --name ackermann_viz \
  --network host \
  -e DISPLAY=${DISPLAY:-:0} \
  -e QT_X11_NO_MITSHM=1 \
  -e LIBGL_ALWAYS_SOFTWARE=1 \
  -e MESA_GL_VERSION_OVERRIDE=3.3 \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -v /home/johnsumba/ros2_ws:/ros2_ws \
  ${device_opt} \
  osrf/ros:humble-desktop \
  bash -lc "set -e; \
    echo '=== Installing xacro and joint_state_publisher_gui ==='; \
    apt-get update -qq; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ros-humble-xacro ros-humble-joint-state-publisher-gui || true; \
    echo '=== Sourcing ROS 2 environment ==='; \
    source /opt/ros/humble/setup.bash; \
    echo '=== Build workspace (if present) ==='; \
    if [ -d /ros2_ws/src ]; then cd /ros2_ws || true; colcon build --symlink-install || true; source install/setup.bash || true; fi; \
    echo '=== Generating robot_description ==='; \
    xacro /ros2_ws/src/ackermann_robot/urdf/ack.urdf.xacro > /tmp/robot_description.urdf; \
    echo '=== Starting robot_state_publisher ==='; \
    ros2 run robot_state_publisher robot_state_publisher --ros-args -p robot_description:="$(cat /tmp/robot_description.urdf)" & \
    sleep 2; \
    echo '=== Starting joint_state_publisher_gui (sliders) ==='; \
    ros2 run joint_state_publisher_gui joint_state_publisher_gui --ros-args -p use_gui:=true & \
    sleep 1; \
    echo '=== Launching RViz2 with ackermann.rviz ==='; \
    rviz2 -d /ros2_ws/src/ackermann_robot/config/ackermann.rviz & \
    wait"

echo "Launched ackermann_viz (RViz + joint sliders)."
echo "Follow logs: docker logs -f ackermann_viz"
