"""
Obstacle Detection Module

Detects obstacles from LiDAR depth data using clustering and segmentation.
"""

from typing import List, Optional, Tuple
import numpy as np
from dataclasses import dataclass
from datetime import datetime


@dataclass
class Obstacle:
    """Represents a detected obstacle."""
    
    id: int
    distance: float  # meters
    angle: float  # degrees (-90 to 90, 0 is straight ahead)
    width: float  # meters
    height: float  # meters
    position: Tuple[float, float]  # (x, y) in meters
    velocity: Optional[Tuple[float, float]] = None  # (vx, vy) in m/s
    threat_level: str = 'safe'  # 'critical', 'warning', 'safe'
    timestamp: datetime = None
    
    def __post_init__(self):
        if self.timestamp is None:
            self.timestamp = datetime.now()


class ObstacleDetector:
    """
    Detects obstacles from LiDAR depth maps.
    
    Uses preprocessing, clustering, and tracking to identify obstacles
    in the robot's environment.
    """
    
    def __init__(
        self,
        min_distance: float = 0.5,
        max_distance: float = 5.0,
        critical_zone: float = 0.8,
        warning_zone: float = 2.0,
    ):
        """
        Initialize obstacle detector.
        
        Args:
            min_distance: Minimum valid depth (meters)
            max_distance: Maximum valid depth (meters)
            critical_zone: Distance threshold for critical threats (meters)
            warning_zone: Distance threshold for warnings (meters)
        """
        self.min_distance = min_distance
        self.max_distance = max_distance
        self.critical_zone = critical_zone
        self.warning_zone = warning_zone
        
        self._next_obstacle_id = 0
        self._tracked_obstacles: List[Obstacle] = []
    
    def preprocess_depth(self, depth_map: np.ndarray) -> np.ndarray:
        """
        Preprocess depth map to remove noise and invalid values.
        
        Args:
            depth_map: Raw depth map from LiDAR (height x width)
            
        Returns:
            Preprocessed depth map
        """
        # TODO: Implement in Task 2
        raise NotImplementedError("Preprocessing will be implemented in Task 2")
    
    def detect_obstacles(self, depth_map: np.ndarray) -> List[Obstacle]:
        """
        Detect obstacles in depth map.
        
        Args:
            depth_map: Preprocessed depth map
            
        Returns:
            List of detected obstacles
        """
        # TODO: Implement in Task 3
        raise NotImplementedError("Detection will be implemented in Task 3")
    
    def _calculate_threat_level(self, distance: float) -> str:
        """Calculate threat level based on distance."""
        if distance < self.critical_zone:
            return 'critical'
        elif distance < self.warning_zone:
            return 'warning'
        else:
            return 'safe'
    
    def get_closest_obstacle(self) -> Optional[Obstacle]:
        """Get the closest detected obstacle."""
        if not self._tracked_obstacles:
            return None
        return min(self._tracked_obstacles, key=lambda obs: obs.distance)
