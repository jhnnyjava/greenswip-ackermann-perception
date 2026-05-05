#!/bin/bash
set -e

# Kill previous container if any
echo "Stopping existing container (if present)..."
docker rm -f ackermann_sim 2>/dev/null || true

echo "Allowing local docker access to X server..."
xhost +local:docker >/dev/null 2>&1 || true

# Add /dev/dri if present for optional GPU passthrough
device_opt=""
if [ -d /dev/dri ]; then
  device_opt="--device /dev/dri"
  echo "Found /dev/dri on host — enabling device passthrough."
fi

echo "Launching ackermann_sim container (this will install packages, build workspace, and start Gazebo + RViz)..."

#!/bin/bash
set -e

echo "Stopping existing container (if present)..."
docker rm -f ackermann_sim 2>/dev/null || true

echo "Allowing local docker access to X server..."
xhost +local:docker >/dev/null 2>&1 || true

device_opt=""
if [ -d /dev/dri ]; then
  device_opt="--device /dev/dri"
  echo "Found /dev/dri on host — enabling device passthrough."
fi

image_name="ackermann_sim_image"
workspace_dir="/home/johnsumba/Documents/Resources/Material"

if ! docker image inspect "$image_name" >/dev/null 2>&1; then
  echo "Building $image_name from Dockerfile.gazebo..."
  docker build -t "$image_name" -f "$workspace_dir/Dockerfile.gazebo" "$workspace_dir"
fi

echo "Launching ackermann_sim container from prebuilt image..."

docker run --rm -d \
  --name ackermann_sim \
  --network host \
  #!/bin/bash
  set -e

  # Kill previous container if any
  echo "Stopping existing container (if present)..."
  docker rm -f ackermann_sim 2>/dev/null || true

  echo "Allowing local docker access to X server..."
  xhost +local:docker >/dev/null 2>&1 || true

  # Add /dev/dri if present for optional GPU passthrough
  device_opt=""
  if [ -d /dev/dri ]; then
    device_opt="--device /dev/dri"
    echo "Found /dev/dri on host — enabling device passthrough."
  fi

  image_name="ackermann_sim_image"
  workspace_dir="/home/johnsumba/Documents/Resources/Material"

  if ! docker image inspect "$image_name" >/dev/null 2>&1; then
    echo "Building $image_name from Dockerfile.gazebo..."
    docker build -t "$image_name" -f "$workspace_dir/Dockerfile.gazebo" "$workspace_dir"
  fi

  echo "Ensuring host config directory exists..."
  mkdir -p /home/johnsumba/ros2_ws/src/ackermann_robot/config || true

  echo "Launching ackermann_sim container from prebuilt image..."

  docker run --rm -d \
    --name ackermann_sim \
    --network host \
    -u root \
    -e DISPLAY=${DISPLAY:-:0} \
    -e QT_X11_NO_MITSHM=1 \
    -e LIBGL_ALWAYS_SOFTWARE=1 \
    -e MESA_GL_VERSION_OVERRIDE=3.3 \
    -e IGN_GAZEBO_RENDER_ENGINE=ogre \
    -e IGN_GAZEBO_SYSTEM_PLUGIN_PATH=/opt/ros/humble/lib \
    -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
    -v /home/johnsumba/ros2_ws:/ros2_ws \
    ${device_opt} \
    "$image_name" \
    bash -lc 'set -e
      echo "=== STEP 3: Sourcing ROS 2 environment ==="
      source /opt/ros/humble/setup.bash || true

      echo "=== STEP 4: Building workspace ==="
      if [ -d /ros2_ws/src ]; then
        cd /ros2_ws
        colcon build --symlink-install 2>/dev/null || true
        source /ros2_ws/install/setup.bash 2>/dev/null || true
      fi

      echo "=== STEP 5: Generating URDF ==="
      XACRO_BIN=$(which xacro 2>/dev/null || echo /opt/ros/humble/bin/xacro)
      robot_description="$($XACRO_BIN /ros2_ws/src/ackermann_robot/urdf/ack.urdf.xacro)"
      printf "%s
  " "$robot_description" > /tmp/robot.urdf
      robot_description_payload="$(python3 - <<PY
  import json
  from pathlib import Path
  xml = Path("/tmp/robot.urdf").read_text()
  print('{"data": ' + json.dumps(xml) + '}')
  PY
  )"

      echo "=== STEP 6: Starting robot_state_publisher ==="
      /opt/ros/humble/bin/ros2 run robot_state_publisher robot_state_publisher --ros-args -p robot_description:="$robot_description" &

      echo "=== STEP 7: Sleeping 3 seconds ==="
      sleep 3

      echo "=== STEP 8: Starting joint_state_publisher ==="
      /opt/ros/humble/bin/ros2 run joint_state_publisher joint_state_publisher &

      echo "=== STEP 9: Sleeping 2 seconds ==="
      sleep 2

      echo "=== STEP 10: Launching Gazebo ==="
      /opt/ros/humble/bin/ros2 launch ros_gz_sim gz_sim.launch.py gz_args:="-r /ros2_ws/src/ackermann_robot/worlds/shapes.sdf" &

      echo "=== STEP 11: Sleeping 8 seconds for Gazebo ==="
      sleep 8

      echo "=== STEP 12: Spawning robot ==="
      /opt/ros/humble/bin/ros2 topic pub /robot_description std_msgs/msg/String "$robot_description_payload" --once || true
      /opt/ros/humble/bin/ros2 run ros_gz_sim create -name ackerman_simple -topic /robot_description -x 0.0 -y 0.0 -z 0.15 -R 0 -P 0 -Y 0 || true

      echo "=== STEP 13: Sleeping 2 seconds ==="
      sleep 2

      echo "=== STEP 14: Starting ros_gz_bridge ==="
      /opt/ros/humble/bin/ros2 run ros_gz_bridge parameter_bridge \
        /camera/image@sensor_msgs/msg/Image[ignition.msgs.Image \
        /clock@rosgraph_msgs/msg/Clock[ignition.msgs.Clock \
        /joint_states@sensor_msgs/msg/JointState[ignition.msgs.Model &

      echo "=== STEP 15: Sleeping 3 seconds ==="
      sleep 3

      echo "=== STEP 16: (container) ensure config directory exists ==="
      [ -d /ros2_ws/src/ackermann_robot/config ] || true

      echo "=== STEP 17: Launching RViz2 ==="
      /opt/ros/humble/bin/rviz2 -d /ros2_ws/src/ackermann_robot/config/ackermann.rviz || true
    '

  echo "Container ackermann_sim launched."
  echo "Follow logs with: docker logs -f ackermann_sim"
    sleep 3

    echo "=== STEP 16: Creating config directory ==="
    mkdir -p /ros2_ws/src/ackermann_robot/config

    echo "=== STEP 17: Launching RViz2 ==="
    rviz2 -d /ros2_ws/src/ackermann_robot/config/ackermann.rviz
  '

echo "Container ackermann_sim launched."
echo "Follow logs with: docker logs -f ackermann_sim"
