![ROS 2 Humble](https://img.shields.io/badge/ROS2-Humble-blue) ![Gazebo Ignition](https://img.shields.io/badge/Gazebo-Ignition-orange) ![Python](https://img.shields.io/badge/Python-3.10-green) ![Docker](https://img.shields.io/badge/Docker-Ready-blue) ![License](https://img.shields.io/badge/License-MIT-yellow)

## About
This project implements an end-to-end autonomous perception-and-control pipeline for a simulated Ackermann robot using ROS 2 Humble, Gazebo Ignition, OpenCV, and Docker. A forward-facing camera stream is processed in real time to detect a red target object, estimate its image-space position and apparent distance proxy, and publish control signals that steer the robot toward the target while handling stop and search behaviors.

Ackermann kinematics are essential here because the robot is car-like, not differential-drive. Steering is constrained by a front steering linkage and wheelbase geometry, so heading changes must be generated as steering angles instead of independent wheel velocities. This yields physically consistent behavior, controller compatibility, and realistic motion planning constraints for automotive-style robots.

## System Architecture
```text
 Gazebo Camera (/camera/image)
            |
            v
   ackermann_perception/vision_node
            |  publishes /target_info (geometry_msgs/Point)
            v
   ackermann_control/control_node
            |  publishes /ackermann_cmd (ackermann_msgs/AckermannDriveStamped)
            v
   Ackermann Robot (ros2_control + steering/wheel joints)
```

## Repository Structure
```text
greenswip-ackermann-perception/
├── src/
│   ├── ackermann_robot/
│   │   ├── urdf/ack.urdf.xacro
│   │   ├── worlds/shapes.sdf
│   │   ├── config/ackermann_control.yaml
│   │   ├── launch/simulation.launch.py
│   │   └── package.xml
│   ├── ackermann_perception/
│   │   ├── ackermann_perception/vision_node.py
│   │   └── package.xml
│   └── ackermann_control/
│       ├── ackermann_control/control_node.py
│       └── package.xml
├── report/debug_prompt_log.pdf
├── Dockerfile
└── README.md
```

## Quick Start (Docker — recommended)
```bash
set -e
cd /home/johnsumba/Documents/Resources/Material

# Clean old containers
docker rm -f ackermann_viz ackermann_sim >/dev/null 2>&1 || true

# Allow X11 for GUI apps from containers
xhost +si:localuser:root
xhost +local:docker

# Build RViz image once (fast on subsequent runs)
docker build -t ackermann_viz_image -f Dockerfile .

# Launch RViz robot model view (override display if needed: VIZ_DISPLAY=:1)
VIZ_DISPLAY=:0 bash ./launch_ackermann_viz.sh

# Launch full Gazebo + ROS 2 simulation stack
bash ./launch_ackermann_gazebo.sh
```

## How It Works
### Perception
The perception node subscribes to `/camera/image`, converts BGR to HSV, and applies dual-range red masking to detect objects with hue wrapping at 0/180.

- HSV dual-range red detection:
  - Range 1: H [0, 10], S [100, 255], V [80, 255]
  - Range 2: H [170, 180], S [100, 255], V [80, 255]

Shape discrimination checks:

| Check | Rule | Purpose |
|---|---|---|
| Area | contour area >= 500 | Reject tiny noise blobs |
| Aspect Ratio | 0.6 <= w/h <= 1.6 | Keep box-like projections |
| Solidity | area / hull_area > 0.80 | Reject hollow/fragmented shapes |
| Polygon Corners | 4 <= corners <= 8 | Prefer box-like contours over curved decoys |

The detected target is published on `/target_info` as `geometry_msgs/Point`:
- `x`: centroid x in pixels
- `y`: centroid y in pixels
- `z`: bounding-box area in pixels squared
- Sentinel when not found: `(-1, -1, 0)`

### Control
The control node subscribes to `/target_info`, publishes `AckermannDriveStamped` on `/ackermann_cmd` for diagnostics, and also publishes `TwistStamped` on `/ackermann_steering_controller/reference` so the ros2_control Ackermann controller can drive the vehicle in Gazebo.

Ackermann steering formula:

$$
err = x_{centroid} - x_{center}, \quad
err_{norm} = clamp\left(\frac{err}{x_{center}}, -1, 1\right), \quad
\delta = clamp\left(err_{norm} \cdot \delta_{max}, -\delta_{max}, \delta_{max}\right)
$$

Speed zones:

| Normalized Error | Speed (m/s) |
|---|---|
| |err_norm| < 0.1 | 0.40 |
| 0.1 <= |err_norm| < 0.4 | 0.25 |
| |err_norm| >= 0.4 | 0.15 |

Stop condition: stop when target area `z` exceeds threshold (`30000.0`), indicating close proximity.

Search behavior: if no valid target arrives for `2.0 s`, command a gentle search arc (`steer=0.3`, `speed=0.1`).

Why NOT differential drive: this platform is car-like, so steering-angle control is required to respect nonholonomic Ackermann constraints.

## Robot Parameters

| Parameter | Value | Meaning |
|---|---:|---|
| wheelbase | 0.295 m | Distance between front steering axis and rear axle |
| max_steering_angle | 0.524 rad | Steering saturation limit |
| image_width | 640 px | Camera image width |
| image_center_x | 320 px | Principal horizontal center used for error |
| target_distance_threshold | 30000 px^2 | Area-based near-target stop threshold |
| target_search_timeout | 2.0 s | Timeout before entering search behavior |

## Key Design Decisions
- Used `AckermannDriveStamped` end-to-end for controller-compatible, physically meaningful commands.
- Encoded no-target state as a clear sentinel `(-1, -1, 0)` to simplify control logic and avoid stale detections.
- Combined HSV dual-range masking with geometric filters to distinguish the target box from shape decoys robustly.
- Kept simulation launch modular: world bring-up, robot spawn, bridge, controllers, perception, and control are composed in one launch file.
- Added a dedicated Docker-based RViz launcher for reproducible visualization on hosts without native ROS 2 installs.

## Known Limitations & Future Work
- The controller integration path currently uses custom `/ackermann_cmd`; a direct bridge to `ackermann_steering_controller` reference topic can be formalized.
- Perception uses color/shape heuristics; adding temporal tracking and learned detection would improve robustness under lighting change.
- Runtime dependency installation in simulation containers increases startup latency; prebuilt runtime images should be used in CI and demos.

## Assignment Context
This repository was developed for a Greenswip (Revati Technologies Pvt. Ltd.) robotics internship assignment focused on building a complete autonomous Ackermann simulation workflow: structured ROS 2 packages, realistic steering control, perception-driven target following, and reproducible Docker-based execution for evaluation and demonstration.

## License
MIT
