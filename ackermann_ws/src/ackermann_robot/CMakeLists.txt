cmake_minimum_required(VERSION 3.8)
project(ackermann_robot)

find_package(ament_cmake REQUIRED)

install(DIRECTORY launch config
	DESTINATION share/${PROJECT_NAME}
)

install(FILES
	${CMAKE_CURRENT_SOURCE_DIR}/ack.urdf.xacro
	${CMAKE_CURRENT_SOURCE_DIR}/shapes.sdf
	DESTINATION share/${PROJECT_NAME}
)

ament_package()
