"""
Tests for obstacle detection module.
"""

import pytest
import numpy as np
from src.obstacle_avoidance import ObstacleDetector, Obstacle


class TestObstacleDetector:
    """Test ObstacleDetector class."""
    
    def test_initialization(self):
        """Test detector initializes with correct parameters."""
        detector = ObstacleDetector(
            min_distance=0.5,
            max_distance=5.0,
            critical_zone=0.8,
            warning_zone=2.0,
        )
        assert detector.min_distance == 0.5
        assert detector.max_distance == 5.0
        assert detector.critical_zone == 0.8
        assert detector.warning_zone == 2.0
    
    def test_threat_level_critical(self):
        """Test critical threat level calculation."""
        detector = ObstacleDetector(critical_zone=0.8)
        threat = detector._calculate_threat_level(0.5)
        assert threat == 'critical'
    
    def test_threat_level_warning(self):
        """Test warning threat level calculation."""
        detector = ObstacleDetector(critical_zone=0.8, warning_zone=2.0)
        threat = detector._calculate_threat_level(1.5)
        assert threat == 'warning'
    
    def test_threat_level_safe(self):
        """Test safe threat level calculation."""
        detector = ObstacleDetector(warning_zone=2.0)
        threat = detector._calculate_threat_level(3.0)
        assert threat == 'safe'
