#!/usr/bin/env bash
set -euo pipefail

# Stop any old visualization containers first.
docker stop jovial_tharp cool_heyrovsky >/dev/null 2>&1 || true
docker rm -f ackermann_viz >/dev/null 2>&1 || true

# Allow local Docker containers to connect to the host X server.
xhost +si:localuser:root >/dev/null 2>&1 || true
xhost +local:docker >/dev/null 2>&1 || true

# Run a fresh visualization container.
docker run --rm \
  -i \
  --name ackermann_viz \
  --network host \
  -e DISPLAY="${DISPLAY}" \
  -e QT_X11_NO_MITSHM=1 \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -v "/home/johnsumba/Documents/Resources/Material/ackermann_ws:/ackermann_ws" \
  -v "/home/johnsumba/Documents/Resources/Material:/material_ws" \
  -w /ackermann_ws \
  osrf/ros:humble-desktop \
  bash -s <<'EOF'
set -euo pipefail

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ros-humble-xacro \
  ros-humble-joint-state-publisher

set +u
source /opt/ros/humble/setup.bash

if [ -f /ackermann_ws/install/setup.bash ]; then
  source /ackermann_ws/install/setup.bash
fi
set -u

xacro_file=/material_ws/ack.urdf.xacro
robot_description_file=/tmp/ackermann_robot_description.urdf
xacro "${xacro_file}" > "${robot_description_file}"

rsp_params=/tmp/rsp_params.yaml
cat > "${rsp_params}" <<RSP
robot_state_publisher:
  ros__parameters:
    robot_description: |
$(sed 's/^/      /' "${robot_description_file}")
RSP

rviz_config=/tmp/ackermann_viz.rviz
cat > "${rviz_config}" <<'RVIZ'
Panels:
  - Class: rviz_common/Displays
    Name: Displays
Visualization Manager:
  Class: ""
  Displays:
    - Class: rviz_default_plugins/Grid
      Enabled: true
      Name: Grid
      Plane: XY
      Plane Cell Count: 10
      Cell Size: 1
    - Class: rviz_default_plugins/RobotModel
      Enabled: true
      Name: RobotModel
  Global Options:
    Fixed Frame: base_footprint
    Frame Rate: 30
  Tools:
    - Class: rviz_default_plugins/Interact
  Views:
    Current:
      Class: rviz_default_plugins/Orbit
      Distance: 8
Window Geometry: {}
RVIZ

ros2 run robot_state_publisher robot_state_publisher \
  --ros-args --params-file "${rsp_params}" &

ros2 run joint_state_publisher joint_state_publisher \
  --ros-args --params-file "${rsp_params}" &

sleep 5
exec rviz2 -d "${rviz_config}"
EOF
