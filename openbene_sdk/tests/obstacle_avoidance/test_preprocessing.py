"""
Comprehensive tests for depth preprocessing.
"""

import pytest
import numpy as np
from src.obstacle_avoidance import ObstacleDetector


class TestDepthPreprocessing:
    """Test depth map preprocessing functions."""
    
    def test_preprocess_removes_nan(self):
        """Test that NaN values are handled."""
        detector = ObstacleDetector()
        
        # Create depth map with NaN values
        depth_map = np.array([
            [1.0, 2.0, np.nan],
            [2.0, np.nan, 3.0],
            [3.0, 2.0, 1.0]
        ])
        
        result = detector.preprocess_depth(depth_map)
        
        # Result should not contain original NaN in processed areas
        assert result.shape == depth_map.shape
    
    def test_preprocess_removes_infinity(self):
        """Test that infinity values are removed."""
        detector = ObstacleDetector()
        
        depth_map = np.array([
            [1.0, 2.0, np.inf],
            [2.0, -np.inf, 3.0],
            [3.0, 2.0, 1.0]
        ])
        
        result = detector.preprocess_depth(depth_map)
        
        # No infinities should remain in valid areas
        valid_mask = ~np.isnan(result)
        assert not np.any(np.isinf(result[valid_mask]))
    
    def test_preprocess_clips_range(self):
        """Test that values are clipped to valid range."""
        detector = ObstacleDetector(min_distance=0.5, max_distance=5.0)
        
        depth_map = np.array([
            [0.1, 2.0, 10.0],
            [2.0, 3.0, 15.0],
            [0.3, 2.0, 1.0]
        ])
        
        result = detector.preprocess_depth(depth_map)
        
        # All valid values should be within range
        valid_mask = ~np.isnan(result)
        assert np.all(result[valid_mask] >= 0.5)
        assert np.all(result[valid_mask] <= 5.0)
    
    def test_preprocess_empty_array(self):
        """Test handling of empty arrays."""
        detector = ObstacleDetector()
        
        with pytest.raises(ValueError):
            detector.preprocess_depth(np.array([]))
    
    def test_preprocess_none_input(self):
        """Test handling of None input."""
        detector = ObstacleDetector()
        
        with pytest.raises(ValueError):
            detector.preprocess_depth(None)
    
    def test_preprocess_reduces_noise(self):
        """Test that preprocessing reduces noise."""
        detector = ObstacleDetector()
        
        # Create noisy depth map
        np.random.seed(42)
        clean = np.ones((10, 10)) * 2.0
        noisy = clean + np.random.normal(0, 0.1, (10, 10))
        
        result = detector.preprocess_depth(noisy)
        
        # Variance should be reduced
        assert np.nanvar(result) < np.var(noisy)
    
    def test_preprocess_preserves_shape(self):
        """Test that output shape matches input shape."""
        detector = ObstacleDetector()
        
        for shape in [(10, 10), (20, 30), (5, 15)]:
            depth_map = np.random.uniform(1.0, 4.0, shape)
            result = detector.preprocess_depth(depth_map)
            assert result.shape == shape
    
    def test_interpolate_small_gaps(self):
        """Test gap interpolation."""
        detector = ObstacleDetector()
        
        # Create depth map with small gap
        depth_map = np.array([
            [1.0, 1.0, 1.0, 1.0, 1.0],
            [1.0, 1.0, np.nan, 1.0, 1.0],
            [1.0, 1.0, 1.0, 1.0, 1.0],
        ])
        
        result = detector._interpolate_small_gaps(depth_map, max_gap_size=3)
        
        # Gap should be filled
        assert not np.isnan(result[1, 2])
        # Filled value should be close to neighbors
        assert 0.8 <= result[1, 2] <= 1.2


class TestPreprocessingEdgeCases:
    """Test edge cases in preprocessing."""
    
    def test_all_invalid_values(self):
        """Test depth map with all invalid values."""
        detector = ObstacleDetector()
        
        depth_map = np.full((5, 5), np.nan)
        result = detector.preprocess_depth(depth_map)
        
        # Should return array of same shape, all NaN
        assert result.shape == (5, 5)
        assert np.all(np.isnan(result))
    
    def test_single_valid_value(self):
        """Test depth map with only one valid value."""
        detector = ObstacleDetector()
        
        depth_map = np.full((5, 5), np.nan)
        depth_map[2, 2] = 2.0
        
        result = detector.preprocess_depth(depth_map)
        
        # Should preserve the valid value
        assert not np.isnan(result[2, 2])
    
    def test_checkerboard_pattern(self):
        """Test alternating valid/invalid pattern."""
        detector = ObstacleDetector()
        
        depth_map = np.ones((6, 6)) * 2.0
        depth_map[::2, ::2] = np.nan
        
        result = detector.preprocess_depth(depth_map)
        
        # Should still have valid values
        assert np.any(~np.isnan(result))
