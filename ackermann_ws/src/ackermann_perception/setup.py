from setuptools import setup

package_name = 'ackermann_perception'

setup(
    name=package_name,
    version='0.0.0',
    packages=[package_name],
    data_files=[
        ('share/ament_index/resource_index/packages', ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='johnsumba',
    maintainer_email='johnsumba@todo.todo',
    description='Vision and perception node package for the ackermann_simple Ackermann-steered robot.',
    license='Apache-2.0',
    tests_require=['pytest'],
    entry_points={
        'console_scripts': [
            'vision_node=ackermann_perception.vision_node:main',
        ],
    },
)
