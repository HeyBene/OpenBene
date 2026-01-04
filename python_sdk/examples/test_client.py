"""
OpenBot PC Test Client

This script demonstrates how to use the OpenBot Python SDK to:
1. Receive video frames from the mobile app
2. Display the video stream in real-time
3. Receive and display sensor data

Usage:
    python test_client.py
"""

import cv2
import numpy as np
from openbot_sdk import OpenBotClient
import time


def display_sensor_data(sensor_data):
    """
    Display sensor data in the console.

    Args:
        sensor_data: Dictionary containing sensor readings
    """
    print("\n" + "=" * 60)
    print("SENSOR DATA UPDATE")
    print("=" * 60)

    # Accelerometer
    if sensor_data.get("accelerometer"):
        acc = sensor_data["accelerometer"]
        print(f"Accelerometer: X={acc['x']:.3f}, Y={acc['y']:.3f}, Z={acc['z']:.3f} m/s²")

    # Gyroscope
    if sensor_data.get("gyroscope"):
        gyro = sensor_data["gyroscope"]
        print(f"Gyroscope:     X={gyro['x']:.3f}, Y={gyro['y']:.3f}, Z={gyro['z']:.3f} rad/s")

    # Magnetometer
    if sensor_data.get("magnetometer"):
        mag = sensor_data["magnetometer"]
        print(f"Magnetometer:  X={mag['x']:.3f}, Y={mag['y']:.3f}, Z={mag['z']:.3f} μT")

    # Battery
    if sensor_data.get("battery_level") is not None:
        battery = sensor_data["battery_level"] * 100
        print(f"Battery:       {battery:.1f}%")

    # Voltage
    if sensor_data.get("voltage") is not None:
        voltage = sensor_data["voltage"]
        print(f"Voltage:       {voltage:.2f}V")

    # Timestamp
    if sensor_data.get("timestamp"):
        print(f"Timestamp:     {sensor_data['timestamp']}")

    print("=" * 60)


def main():
    """Main function to run the OpenBot test client."""
    print("OpenBot PC Test Client")
    print("=" * 60)
    print("Starting server...")
    print("Please connect from the OpenBot mobile app")
    print("=" * 60)

    # Create OpenBot client
    client = OpenBotClient(host="0.0.0.0", port=8765)

    # Set up callbacks
    frame_count = [0]  # Use list to allow modification in nested function
    sensor_count = [0]

    def on_video_frame(frame_bytes):
        """Callback for video frames."""
        frame_count[0] += 1

    def on_sensor_data(sensor_data):
        """Callback for sensor data."""
        sensor_count[0] += 1
        if sensor_count[0] % 10 == 0:  # Display every 10th update
            display_sensor_data(sensor_data)

    client.set_video_frame_callback(on_video_frame)
    client.set_sensor_data_callback(on_sensor_data)

    # Start the server
    client.start()

    print("\nServer is running. Waiting for mobile app connection...")
    print("Press Ctrl+C to stop\n")

    try:
        # Create window for video display
        window_name = "OpenBot Video Stream"
        cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)

        last_status_time = time.time()
        fps_start_time = time.time()
        fps_frame_count = 0

        while True:
            # Get latest video frame
            frame_bytes = client.get_video_frame()

            if frame_bytes:
                # Decode JPEG to numpy array
                nparr = np.frombuffer(frame_bytes, np.uint8)
                frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

                if frame is not None:
                    # Calculate FPS
                    fps_frame_count += 1
                    current_time = time.time()
                    elapsed = current_time - fps_start_time

                    if elapsed >= 1.0:
                        fps = fps_frame_count / elapsed
                        fps_frame_count = 0
                        fps_start_time = current_time
                    else:
                        fps = 0

                    # Get sensor data for overlay
                    sensor_data = client.get_sensor_data()

                    # Draw overlay information
                    overlay_y = 30
                    cv2.putText(frame, f"FPS: {fps:.1f}", (10, overlay_y),
                                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
                    overlay_y += 30

                    if sensor_data:
                        if sensor_data.get("battery_level") is not None:
                            battery = sensor_data["battery_level"] * 100
                            color = (0, 255, 0) if battery > 20 else (0, 0, 255)
                            cv2.putText(frame, f"Battery: {battery:.1f}%", (10, overlay_y),
                                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)
                            overlay_y += 30

                        if sensor_data.get("voltage") is not None:
                            voltage = sensor_data["voltage"]
                            cv2.putText(frame, f"Voltage: {voltage:.2f}V", (10, overlay_y),
                                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)

                    # Display the frame
                    cv2.imshow(window_name, frame)

            # Display connection status periodically
            if time.time() - last_status_time >= 5.0:
                stats = client.get_statistics()
                print(f"\nStatus: {'Connected' if stats['connected'] else 'Disconnected'}")
                print(f"Frames received: {stats['frames_received']}")
                print(f"Sensor updates: {stats['sensor_updates_received']}")
                last_status_time = time.time()

            # Check for exit key
            if cv2.waitKey(1) & 0xFF == ord('q'):
                print("\nExiting...")
                break

            # Small delay to prevent busy-waiting
            time.sleep(0.01)

    except KeyboardInterrupt:
        print("\n\nShutting down...")
    finally:
        # Clean up
        cv2.destroyAllWindows()
        client.stop()
        print("Client stopped")


if __name__ == "__main__":
    main()
