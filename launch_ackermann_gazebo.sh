#!/usr/bin/env bash
set -euo pipefail

# Stop any old simulation container first.
docker stop ackermann_sim >/dev/null 2>&1 || true
docker rm -f ackermann_sim >/dev/null 2>&1 || true

# Allow local Docker containers to connect to the host X server.
xhost +si:localuser:root >/dev/null 2>&1 || true
xhost +local:docker >/dev/null 2>&1 || true

effective_display="${VIZ_DISPLAY:-${DISPLAY:-:0}}"
if ! xset -display "${effective_display}" q >/dev/null 2>&1; then
  for candidate in :0 :1 :2; do
    if xset -display "${candidate}" q >/dev/null 2>&1; then
      effective_display="${candidate}"
      break
    fi
  done
fi

echo "Using DISPLAY=${effective_display} for Gazebo container"

gz_image=ackermann_gazebo_image

if ! docker image inspect "${gz_image}" >/dev/null 2>&1; then
  docker build \
    -t "${gz_image}" \
    -f /home/johnsumba/Documents/Resources/Material/Dockerfile.gazebo \
    /home/johnsumba/Documents/Resources/Material
fi

# Run Gazebo and the ROS 2 stack in a detached container.
docker run -d --rm \
  --name ackermann_sim \
  --network host \
  -e DISPLAY="${effective_display}" \
  -e QT_X11_NO_MITSHM=1 \
  -e LIBGL_ALWAYS_SOFTWARE=1 \
  -e MESA_GL_VERSION_OVERRIDE=3.3 \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -v "/home/johnsumba/Documents/Resources/Material/ackermann_ws:/ws" \
  -w /ws \
  "${gz_image}" \
  bash -lc '
set -euo pipefail

source /opt/ros/humble/setup.bash
if [ -f /ws/install/setup.bash ]; then
  source /ws/install/setup.bash
fi

colcon build --symlink-install
source install/setup.bash
exec ros2 launch ackermann_robot simulation.launch.py
'
