"""
Obstacle Detection Module

Detects obstacles from LiDAR depth data using clustering and segmentation.
"""

from typing import List, Optional, Tuple
import numpy as np
from dataclasses import dataclass
from datetime import datetime
from scipy.ndimage import median_filter, gaussian_filter
from scipy.interpolate import griddata
from scipy.spatial import cKDTree


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
        
        Pipeline:
        1. Remove invalid values (NaN, inf, zeros)
        2. Clip to valid depth range
        3. Apply median filter for noise removal
        4. Apply Gaussian smoothing
        5. Interpolate small gaps
        
        Args:
            depth_map: Raw depth map from LiDAR (height x width)
            
        Returns:
            Preprocessed depth map (same shape as input)
        """
        if depth_map is None or depth_map.size == 0:
            raise ValueError("Depth map cannot be None or empty")
        
        # Step 1: Create a copy to avoid modifying original
        processed = depth_map.copy().astype(np.float32)
        
        # Step 2: Remove invalid values (NaN, inf, negative, zero)
        invalid_mask = (
            np.isnan(processed) | 
            np.isinf(processed) | 
            (processed <= 0) |
            (processed > self.max_distance * 2)  # Remove obviously wrong values
        )
        processed[invalid_mask] = np.nan
        
        # Step 3: Clip to valid range
        processed = np.clip(processed, self.min_distance, self.max_distance)
        
        # Step 4: Apply median filter to remove salt-and-pepper noise
        # Only on valid regions
        valid_mask = ~np.isnan(processed)
        if np.any(valid_mask):
            # Fill NaN with median of valid values for filtering
            temp_filled = processed.copy()
            temp_filled[~valid_mask] = np.nanmedian(processed)
            
            # Apply median filter (3x3 kernel)
            filtered = median_filter(temp_filled, size=3)
            
            # Restore NaN where original was invalid
            filtered[~valid_mask] = np.nan
            processed = filtered
        
        # Step 5: Apply Gaussian smoothing for noise reduction
        if np.any(valid_mask):
            temp_filled = processed.copy()
            temp_filled[~valid_mask] = np.nanmedian(processed)
            
            # Apply Gaussian filter (sigma=1.0)
            smoothed = gaussian_filter(temp_filled, sigma=1.0)
            
            # Restore NaN where original was invalid
            smoothed[~valid_mask] = np.nan
            processed = smoothed
        
        # Step 6: Interpolate small gaps (optional, for small holes)
        processed = self._interpolate_small_gaps(processed, max_gap_size=5)
        
        return processed
    
    def _interpolate_small_gaps(
        self, 
        depth_map: np.ndarray, 
        max_gap_size: int = 5
    ) -> np.ndarray:
        """
        Fill small gaps in depth map using interpolation.
        
        Args:
            depth_map: Depth map with NaN gaps
            max_gap_size: Maximum gap size to fill (pixels)
            
        Returns:
            Depth map with small gaps filled
        """
        result = depth_map.copy()
        
        # Find valid and invalid points
        valid_mask = ~np.isnan(result)
        
        if not np.any(valid_mask):
            return result  # All invalid, cannot interpolate
        
        # Get coordinates
        h, w = result.shape
        y_coords, x_coords = np.mgrid[0:h, 0:w]
        
        # Valid points
        valid_points = np.column_stack([
            y_coords[valid_mask],
            x_coords[valid_mask]
        ])
        valid_values = result[valid_mask]
        
        # Invalid points
        invalid_mask = np.isnan(result)
        if not np.any(invalid_mask):
            return result  # No gaps to fill
        
        invalid_points = np.column_stack([
            y_coords[invalid_mask],
            x_coords[invalid_mask]
        ])
        
        # Only interpolate small gaps
        # (Check if invalid point has valid neighbors within max_gap_size)
        if len(valid_points) > 0 and len(invalid_points) > 0:
            tree = cKDTree(valid_points)
            distances, _ = tree.query(invalid_points, k=1)
            
            # Only fill gaps smaller than max_gap_size
            small_gaps = distances <= max_gap_size
            
            if np.any(small_gaps):
                # Interpolate using nearest neighbors
                interpolated = griddata(
                    valid_points,
                    valid_values,
                    invalid_points[small_gaps],
                    method='nearest'
                )
                
                # Update result
                small_gap_indices = np.where(invalid_mask)
                result[
                    small_gap_indices[0][small_gaps],
                    small_gap_indices[1][small_gaps]
                ] = interpolated
        
        return result
    
    def detect_obstacles(self, depth_map: np.ndarray) -> List[Obstacle]:
        """
        Detect obstacles in depth map.
        
        Args:
            depth_map: Preprocessed depth map
            
        Returns:
            List of detected obstacles
        """
        # Step 1: Convert depth map to 3D points
        points = self._depth_to_points(depth_map)
        
        if len(points) == 0:
            return []
        
        # Step 2: Cluster points into obstacles
        clusters = self._cluster_points(points)
        
        # Step 3: Extract obstacle properties
        obstacles = []
        for cluster_id, cluster_points in clusters.items():
            obstacle = self._extract_obstacle_properties(cluster_points, cluster_id)
            if obstacle:
                obstacles.append(obstacle)
        
        return obstacles
    
    def _depth_to_points(self, depth_map: np.ndarray) -> np.ndarray:
        """
        Convert depth map to 3D point cloud.
        
        Args:
            depth_map: 2D depth map (height x width)
            
        Returns:
            Nx3 array of (x, y, z) points in meters
        """
        height, width = depth_map.shape
        
        # Create pixel coordinates
        v, u = np.mgrid[0:height, 0:width]
        
        # Filter valid depths
        valid_mask = ~np.isnan(depth_map) & (depth_map > 0)
        
        u_valid = u[valid_mask]
        v_valid = v[valid_mask]
        z_valid = depth_map[valid_mask]
        
        # Simple camera model (assume FOV of 90 degrees)
        # x = (u - width/2) * z / (width/2)
        # y = (v - height/2) * z / (height/2)
        
        x = (u_valid - width / 2) * z_valid / (width / 2)
        y = (v_valid - height / 2) * z_valid / (height / 2)
        z = z_valid
        
        # Stack into Nx3 array
        points = np.column_stack([x, y, z])
        
        return points
    
    def _cluster_points(self, points: np.ndarray) -> dict:
        """
        Cluster 3D points into obstacles using DBSCAN.
        
        Args:
            points: Nx3 array of 3D points
            
        Returns:
            Dictionary mapping cluster_id -> cluster_points
        """
        from sklearn.cluster import DBSCAN
        
        if len(points) == 0:
            return {}
        
        # DBSCAN clustering
        # eps: maximum distance between points in same cluster (meters)
        # min_samples: minimum points to form a cluster
        clustering = DBSCAN(eps=0.3, min_samples=5).fit(points)
        
        labels = clustering.labels_
        
        # Group points by cluster
        clusters = {}
        for label in set(labels):
            if label == -1:  # Noise points
                continue
            
            cluster_mask = labels == label
            clusters[label] = points[cluster_mask]
        
        return clusters
    
    def _extract_obstacle_properties(
        self, 
        cluster_points: np.ndarray, 
        cluster_id: int
    ) -> Optional[Obstacle]:
        """
        Extract obstacle properties from clustered points.
        
        Args:
            cluster_points: Nx3 array of points in cluster
            cluster_id: Unique cluster identifier
            
        Returns:
            Obstacle object or None if invalid
        """
        if len(cluster_points) == 0:
            return None
        
        # Calculate centroid
        centroid = np.mean(cluster_points, axis=0)
        x, y, z = centroid
        
        # Calculate distance from robot (at origin)
        distance = np.sqrt(x**2 + z**2)
        
        # Calculate angle (in degrees, 0 = straight ahead)
        angle = np.degrees(np.arctan2(x, z))
        
        # Calculate bounding box
        min_bounds = np.min(cluster_points, axis=0)
        max_bounds = np.max(cluster_points, axis=0)
        
        width = max_bounds[0] - min_bounds[0]
        height = max_bounds[1] - min_bounds[1]
        
        # Determine threat level
        threat_level = self._calculate_threat_level(distance)
        
        return Obstacle(
            id=cluster_id,
            distance=float(distance),
            angle=float(angle),
            width=float(width),
            height=float(height),
            position=(float(x), float(z)),
            threat_level=threat_level
        )

    
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
