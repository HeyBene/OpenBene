"""
Simple OpenBot Example

Basic example showing how to use the OpenBot SDK to receive data from the mobile app.
"""

from openbot_sdk import OpenBotClient
import time


def main():
    # Create and start the client
    client = OpenBotClient(host="0.0.0.0", port=8765)
    client.start()

    print("OpenBot Server Started")
    print("Waiting for mobile app connection on port 8765...")
    print("Press Ctrl+C to stop\n")

    try:
        while True:
            # Get latest data
            frame = client.get_video_frame()
            sensor_data = client.get_sensor_data()

            # Check if we have data
            if client.is_connected():
                if frame:
                    print(f"Received video frame: {len(frame)} bytes")

                if sensor_data:
                    print(f"Sensor data: Battery={sensor_data.get('battery_level', 'N/A')}")

            time.sleep(1)

    except KeyboardInterrupt:
        print("\nStopping...")
    finally:
        client.stop()


if __name__ == "__main__":
    main()
