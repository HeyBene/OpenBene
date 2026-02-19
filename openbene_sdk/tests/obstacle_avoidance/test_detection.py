"""
Comprehensive tests for obstacle detection and clustering.
"""

import pytest
import numpy as np
from src.obstacle_avoidance import ObstacleDetector


class TestObstacleDetection:
    """Test obstacle detection pipeline."""
    
    def test_detect_obstacles_simple_case(self):
        """Test detection with simple obstacle."""
        detector = ObstacleDetector()
        
        # Create depth map with LARGER obstacle (survives Gaussian smoothing)
        depth_map = np.full((30, 30), 5.0)  # Background at 5m
        depth_map[10:20, 10:20] = 2.0  # 10x10 obstacle at 2m
        
        # IMPORTANT: Preprocess before detection
        preprocessed = detector.preprocess_depth(depth_map)
        obstacles = detector.detect_obstacles(preprocessed)
        
        # Should detect at least one obstacle
        assert len(obstacles) > 0
        
        # Closest obstacle should be around 2m
        closest = min(obstacles, key=lambda o: o.distance)
        assert 1.5 < closest.distance < 2.5
    
    def test_detect_obstacles_multiple(self):
        """Test detection with multiple obstacles."""
        detector = ObstacleDetector()
        
        # Create depth map with two LARGER separate obstacles
        depth_map = np.full((50, 50), 5.0)
        depth_map[5:15, 5:15] = 2.0   # 10x10 Obstacle 1
        depth_map[35:45, 35:45] = 3.0  # 10x10 Obstacle 2
        
        # Preprocess before detection
        preprocessed = detector.preprocess_depth(depth_map)
        obstacles = detector.detect_obstacles(preprocessed)
        
        # Should detect multiple obstacles
        assert len(obstacles) >= 2
    
    def test_detect_obstacles_empty_depth(self):
        """Test with empty/invalid depth map."""
        detector = ObstacleDetector()
        
        # All NaN depth map
        depth_map = np.full((20, 20), np.nan)
        
        obstacles = detector.detect_obstacles(depth_map)
        
        # Should return empty list
        assert len(obstacles) == 0
    
    def test_detect_obstacles_noise_filtered(self):
        """Test that noise points don't create obstacles."""
        detector = ObstacleDetector()
        
        # Create depth map with scattered noise
        depth_map = np.full((30, 30), 5.0)
        
        # Add random noise points (too sparse to cluster)
        np.random.seed(42)
        noise_mask = np.random.random((30, 30)) < 0.05
        depth_map[noise_mask] = 2.0
        
        obstacles = detector.detect_obstacles(depth_map)
        
        # Noise should be filtered out by DBSCAN
        # Should have 0 or very few obstacles
        assert len(obstacles) < 3


class TestDepthToPoints:
    """Test depth map to point cloud conversion."""
    
    def test_depth_to_points_shape(self):
        """Test output shape is correct."""
        detector = ObstacleDetector()
        
        depth_map = np.ones((10, 10)) * 2.0
        points = detector._depth_to_points(depth_map)
        
        # Should have Nx3 shape (100 valid points)
        assert points.shape[1] == 3
        assert points.shape[0] == 100
    
    def test_depth_to_points_z_values(self):
        """Test that z coordinates match depth values."""
        detector = ObstacleDetector()
        
        depth_map = np.ones((5, 5)) * 3.0
        points = detector._depth_to_points(depth_map)
        
        # All z values should be close to 3.0
        assert np.allclose(points[:, 2], 3.0)
    
    def test_depth_to_points_filters_invalid(self):
        """Test that invalid depths are filtered."""
        detector = ObstacleDetector()
        
        depth_map = np.ones((10, 10)) * 2.0
        depth_map[0:5, 0:5] = np.nan
        
        points = detector._depth_to_points(depth_map)
        
        # Should only have 75 valid points (100 - 25)
        assert points.shape[0] == 75
    
    def test_depth_to_points_center_at_origin(self):
        """Test that center pixel maps near (0, 0, depth)."""
        detector = ObstacleDetector()
        
        depth_map = np.full((11, 11), 5.0)
        points = detector._depth_to_points(depth_map)
        
        # Center point should be near (0, 0, 5.0)
        center_idx = 11 * 5 + 5  # Center pixel
        center_point = points[center_idx]
        
        # Relaxed tolerance for camera model approximation
        assert abs(center_point[0]) < 0.5  # x near 0
        assert abs(center_point[1]) < 0.5  # y near 0
        assert abs(center_point[2] - 5.0) < 0.1  # z near 5.0


class TestPointClustering:
    """Test DBSCAN point clustering."""
    
    def test_cluster_points_single_cluster(self):
        """Test clustering with one dense cluster."""
        detector = ObstacleDetector()
        
        # Create points in single cluster
        np.random.seed(42)
        points = np.random.randn(50, 3) * 0.1  # Tight cluster at origin
        
        clusters = detector._cluster_points(points)
        
        # Should find 1 cluster
        assert len(clusters) >= 1
    
    def test_cluster_points_multiple_clusters(self):
        """Test clustering with multiple separated clusters."""
        detector = ObstacleDetector()
        
        # Create two separated clusters
        cluster1 = np.random.randn(30, 3) * 0.1
        cluster2 = np.random.randn(30, 3) * 0.1 + [5, 0, 0]
        
        points = np.vstack([cluster1, cluster2])
        
        clusters = detector._cluster_points(points)
        
        # Should find 2 clusters
        assert len(clusters) >= 2
    
    def test_cluster_points_filters_noise(self):
        """Test that sparse points are treated as noise."""
        detector = ObstacleDetector()
        
        # Create very sparse points
        points = np.random.randn(10, 3) * 10
        
        clusters = detector._cluster_points(points)
        
        # Should find 0 clusters (all noise)
        assert len(clusters) == 0
    
    def test_cluster_points_empty_input(self):
        """Test with empty point array."""
        detector = ObstacleDetector()
        
        points = np.array([]).reshape(0, 3)
        clusters = detector._cluster_points(points)
        
        # Should return empty dict
        assert len(clusters) == 0


class TestObstacleProperties:
    """Test obstacle property extraction."""
    
    def test_extract_properties_distance(self):
        """Test distance calculation."""
        detector = ObstacleDetector()
        
        # Points at (3, 0, 4) - distance should be 5
        points = np.array([
            [3.0, 0.0, 4.0],
            [3.1, 0.1, 4.1],
            [2.9, -0.1, 3.9]
        ])
        
        obstacle = detector._extract_obstacle_properties(points, 0)
        
        assert obstacle is not None
        assert 4.5 < obstacle.distance < 5.5
    
    def test_extract_properties_angle(self):
        """Test angle calculation."""
        detector = ObstacleDetector()
        
        # Points to the right (+x direction)
        points = np.array([
            [2.0, 0.0, 2.0],
            [2.1, 0.0, 2.0],
            [1.9, 0.0, 2.0]
        ])
        
        obstacle = detector._extract_obstacle_properties(points, 0)
        
        assert obstacle is not None
        # Should be around 45 degrees
        assert 40 < obstacle.angle < 50
    
    def test_extract_properties_size(self):
        """Test width and height calculation."""
        detector = ObstacleDetector()
        
        # Points forming a box
        points = np.array([
            [0.0, 0.0, 2.0],
            [1.0, 0.0, 2.0],
            [0.0, 2.0, 2.0],
            [1.0, 2.0, 2.0]
        ])
        
        obstacle = detector._extract_obstacle_properties(points, 0)
        
        assert obstacle is not None
        assert 0.8 < obstacle.width < 1.2
        assert 1.8 < obstacle.height < 2.2
    
    def test_extract_properties_threat_level(self):
        """Test threat level assignment."""
        # Use correct parameter names: critical_zone and warning_zone
        detector = ObstacleDetector(
            critical_zone=1.0,
            warning_zone=2.0
        )
        
        # Close obstacle
        close_points = np.array([[0.0, 0.0, 0.5]])
        close_obs = detector._extract_obstacle_properties(close_points, 0)
        
        assert close_obs.threat_level == "critical"
        
        # Medium distance
        medium_points = np.array([[0.0, 0.0, 1.5]])
        medium_obs = detector._extract_obstacle_properties(medium_points, 1)
        
        assert medium_obs.threat_level == "warning"
        
        # Far obstacle
        far_points = np.array([[0.0, 0.0, 3.0]])
        far_obs = detector._extract_obstacle_properties(far_points, 2)
        
        assert far_obs.threat_level == "safe"
    
    def test_extract_properties_empty_cluster(self):
        """Test with empty cluster."""
        detector = ObstacleDetector()
        
        points = np.array([]).reshape(0, 3)
        obstacle = detector._extract_obstacle_properties(points, 0)
        
        # Should return None
        assert obstacle is None
