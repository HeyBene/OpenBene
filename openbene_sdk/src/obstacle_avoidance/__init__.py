"""
Obstacle Avoidance Module for OpenBene SDK

Provides real-time obstacle detection and avoidance using LiDAR depth sensing.
"""

from .obstacle_detection import ObstacleDetector, Obstacle
from .path_planning import PathPlanner
from .navigation_controller import NavigationController

__all__ = [
    'ObstacleDetector',
    'Obstacle',
    'PathPlanner',
    'NavigationController',
]

__version__ = '0.1.0'
