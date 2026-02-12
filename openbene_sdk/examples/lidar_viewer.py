"""
LiDAR Depth Viewer Example

Displays real-time depth map from iPhone LiDAR sensor.
Requires: numpy, opencv-python, matplotlib

Usage:
    python lidar_viewer.py <iPhone_IP> [--scale SCALE]

Example:
    python lidar_viewer.py 192.168.1.100
    python lidar_viewer.py 192.168.1.100 --scale 3
"""

import sys
import argparse
import cv2
import numpy as np
from openbene import OpenBene

# Default visualization scale factor
DEFAULT_SCALE = 2


def visualize_depth(depth_array, min_depth, max_depth):
    """
    Convert depth array to color visualization
    
    Args:
        depth_array: 2D numpy array of depth values
        min_depth: Minimum depth value in meters
        max_depth: Maximum depth value in meters
    
    Returns:
        Colored visualization image
    """
    # Normalize to 0-255
    if max_depth > min_depth:
        normalized = ((depth_array - min_depth) / (max_depth - min_depth) * 255).astype(np.uint8)
    else:
        normalized = np.zeros_like(depth_array, dtype=np.uint8)
    
    # Apply colormap (JET: blue=near, red=far)
    colored = cv2.applyColorMap(normalized, cv2.COLORMAP_JET)
    return colored


def main():
    # Parse command line arguments
    parser = argparse.ArgumentParser(description='LiDAR Depth Viewer')
    parser.add_argument('phone_ip', help='iPhone IP address')
    parser.add_argument('--scale', type=int, default=DEFAULT_SCALE, 
                       help=f'Visualization scale factor (default: {DEFAULT_SCALE})')
    args = parser.parse_args()
    
    phone_ip = args.phone_ip
    scale_factor = args.scale
    
    print(f"Connecting to iPhone at {phone_ip}...")
    bot = OpenBene()
    
    try:
        bot.connect(phone_ip)
    except Exception as e:
        print(f"Failed to connect: {e}")
        sys.exit(1)
    
    print("Connected successfully!")
    print("Receiving LiDAR depth data...")
    print("Controls:")
    print("  - Press 'q' to quit")
    print("  - Press 's' to save current frame")
    print("  - Press 'r' to toggle raw depth values")
    
    frame_count = 0
    show_raw = False
    no_data_count = 0
    
    try:
        while True:
            # Get LiDAR depth data
            lidar_data = bot.sensors.get_lidar_depth()
            
            if lidar_data:
                no_data_count = 0
                depth_img = bot.sensors.get_depth_image()
                
                if depth_img is not None:
                    # Visualize depth
                    if show_raw:
                        # Show raw normalized depth values
                        vis = cv2.normalize(depth_img, None, 0, 255, cv2.NORM_MINMAX, dtype=cv2.CV_8U)
                        vis = cv2.cvtColor(vis, cv2.COLOR_GRAY2BGR)
                    else:
                        # Show colorized depth
                        vis = visualize_depth(
                            depth_img,
                            lidar_data['min_depth'],
                            lidar_data['max_depth']
                        )
                    
                    # Resize for better visibility (configurable scale factor)
                    vis = cv2.resize(vis, (vis.shape[1] * scale_factor, vis.shape[0] * scale_factor), 
                                   interpolation=cv2.INTER_NEAREST)
                    
                    # Add info text overlay
                    info_y = 30
                    cv2.putText(vis, 
                               f"Depth Range: {lidar_data['min_depth']:.2f}m - {lidar_data['max_depth']:.2f}m",
                               (10, info_y), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
                    
                    info_y += 30
                    cv2.putText(vis, 
                               f"Resolution: {lidar_data['width']}x{lidar_data['height']}",
                               (10, info_y), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
                    
                    info_y += 30
                    mode_text = "Raw Depth" if show_raw else "Color Map"
                    cv2.putText(vis, 
                               f"Mode: {mode_text} (press 'r' to toggle)",
                               (10, info_y), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
                    
                    # Show the visualization
                    cv2.imshow('LiDAR Depth Viewer', vis)
                    
                    # Handle keyboard input
                    key = cv2.waitKey(1) & 0xFF
                    if key == ord('q'):
                        print("Quitting...")
                        break
                    elif key == ord('s'):
                        filename = f"depth_frame_{frame_count:04d}.png"
                        cv2.imwrite(filename, vis)
                        print(f"Saved {filename}")
                        frame_count += 1
                    elif key == ord('r'):
                        show_raw = not show_raw
                        print(f"Switched to {'raw depth' if show_raw else 'color map'} mode")
            else:
                no_data_count += 1
                if no_data_count % 10 == 1:  # Print every 10th time
                    print("Waiting for LiDAR data...")
                cv2.waitKey(100)
    
    except KeyboardInterrupt:
        print("\nInterrupted by user")
    
    finally:
        print("Disconnecting...")
        bot.disconnect()
        cv2.destroyAllWindows()
        print("Done!")


if __name__ == "__main__":
    main()
