#!/usr/bin/env bash
set -euo pipefail

# Stop any old visualization containers first.
docker stop jovial_tharp cool_heyrovsky >/dev/null 2>&1 || true
docker rm -f ackermann_viz >/dev/null 2>&1 || true

# Allow local Docker containers to connect to the host X server.
xhost +si:localuser:root >/dev/null 2>&1 || true
xhost +local:docker >/dev/null 2>&1 || true

# Pick a usable X display if the current DISPLAY is stale.
# You can override auto-detection with VIZ_DISPLAY=:1 (or :0).
effective_display="${VIZ_DISPLAY:-${DISPLAY:-:0}}"
if ! xset -display "${effective_display}" q >/dev/null 2>&1; then
  for candidate in :0 :1 :2; do
    if xset -display "${candidate}" q >/dev/null 2>&1; then
      effective_display="${candidate}"
      break
    fi
  done
fi

echo "Using DISPLAY=${effective_display} for RViz container"

viz_image=ackermann_viz_image

if ! docker image inspect "${viz_image}" >/dev/null 2>&1; then
  docker build \
    -t "${viz_image}" \
    -f /home/johnsumba/Documents/Resources/Material/Dockerfile \
    /home/johnsumba/Documents/Resources/Material
fi

# Run a fresh visualization container.
docker run -d --rm \
  --name ackermann_viz \
  --network host \
  -e DISPLAY="${effective_display}" \
  -e QT_X11_NO_MITSHM=1 \
  -e LIBGL_ALWAYS_SOFTWARE=1 \
  -e MESA_GL_VERSION_OVERRIDE=3.3 \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  -v "/home/johnsumba/Documents/Resources/Material:/material_ws" \
  -w /material_ws \
  "${viz_image}" \
  bash -lc '
set -euo pipefail

set +u
source /opt/ros/humble/setup.bash
set -u

xacro_file=/material_ws/ack.urdf.xacro
robot_description_file=/tmp/ackermann_robot_description.urdf
xacro "$xacro_file" > "$robot_description_file"

rsp_params=/tmp/rsp_params.yaml
cat > "$rsp_params" <<RSP
robot_state_publisher:
  ros__parameters:
    robot_description: |
$(sed "s/^/      /" "$robot_description_file")
RSP

jsp_params=/tmp/jsp_params.yaml
cat > "$jsp_params" <<JSP
joint_state_publisher:
  ros__parameters:
    robot_description: |
$(sed "s/^/      /" "$robot_description_file")
JSP

rviz_config=/tmp/ackermann_viz.rviz
cat > "$rviz_config" <<"RVIZ"
Panels:
  - Class: rviz_common/Displays
    Name: Displays
Visualization Manager:
  Class: ""
  Enabled: true
  Displays:
    - Class: rviz_default_plugins/Grid
      Enabled: true
      Name: Grid
      Plane: XY
      Plane Cell Count: 10
      Cell Size: 0.5
    - Class: rviz_default_plugins/RobotModel
      Enabled: true
      Name: RobotModel
      Description Topic:
        Value: /robot_description
      Visual Enabled: true
      Collision Enabled: false
      Alpha: 1
  Global Options:
    Fixed Frame: base_link
    Frame Rate: 30
  Tools:
    - Class: rviz_default_plugins/Interact
  Views:
    Current:
      Class: rviz_default_plugins/Orbit
      Distance: 1.5
      Focal Point:
        X: 0
        Y: 0
        Z: 0.1
Window Geometry: {}
RVIZ

ros2 run robot_state_publisher robot_state_publisher \
  --ros-args --params-file "$rsp_params" &

ros2 run joint_state_publisher joint_state_publisher \
  --ros-args --params-file "$jsp_params" &

sleep 5
exec rviz2 -d "$rviz_config"
'
