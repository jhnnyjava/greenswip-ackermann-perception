#!/bin/bash
# Gazebo launcher: no image build, just run directly on base image
set -e

cd /home/johnsumba/Documents/Resources/Material

# Detect display
DISPLAY="${VIZ_DISPLAY:-:0}"
if ! xset -display "$DISPLAY" q &>/dev/null 2>&1; then
    for d in :0 :1 :2 :99; do
        if xset -display "$d" q &>/dev/null 2>&1; then
            DISPLAY="$d"
            break
        fi
    done
fi

echo "Display: $DISPLAY"

# Allow Docker to access X server
xhost +si:localuser:root >/dev/null 2>&1 || true
xhost +local:docker >/dev/null 2>&1 || true

CONTAINER_NAME="ackermann_gazebo"
BASE_IMAGE="osrf/ros:humble-desktop"

# Clean up old container
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

echo "Starting Gazebo simulation container..."
echo "This will install packages, build workspace, and launch Gazebo."
echo ""

# Run container with all setup in one command
docker run -d \
    --name "$CONTAINER_NAME" \
    --net=host \
    -e DISPLAY="$DISPLAY" \
    -e QT_X11_NO_MITSHM=1 \
    -e LIBGL_ALWAYS_SOFTWARE=1 \
    -e MESA_GL_VERSION_OVERRIDE=3.3 \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v /home/johnsumba/Documents/Resources/Material/ackermann_ws:/ws \
    -w /ws \
    "$BASE_IMAGE" \
    bash -lc '
set -e

echo "=== Installing packages ==="
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    python3-colcon-common-extensions \
    ros-humble-ros-gz-sim \
    ros-humble-ros-gz-bridge \
    ros-humble-ros2-control \
    ros-humble-ros2-controllers \
    ros-humble-joint-state-broadcaster \
    ros-humble-ackermann-steering-controller \
    ros-humble-ackermann-msgs \
    2>/dev/null || true

echo "=== Building workspace ==="
source /opt/ros/humble/setup.bash
colcon build --symlink-install 2>&1 | tail -20
source install/setup.bash

echo "=== Launching Gazebo ==="
ros2 launch ackermann_robot simulation.launch.py
'

echo ""
echo "✓ Gazebo container launched"
echo "  Container: $CONTAINER_NAME"
echo "  View output: docker logs -f $CONTAINER_NAME"
echo "  Stop:        docker rm -f $CONTAINER_NAME"
