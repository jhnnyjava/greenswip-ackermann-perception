FROM osrf/ros:humble-desktop

SHELL ["/bin/bash", "-lc"]

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ros-humble-xacro \
    ros-humble-joint-state-publisher \
  && rm -rf /var/lib/apt/lists/*
