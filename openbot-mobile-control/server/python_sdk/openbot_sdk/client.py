import asyncio
import json
import base64
from typing import Optional, Dict, Any, Callable
from datetime import datetime
import websockets
from websockets.server import WebSocketServerProtocol
import threading


class OpenBotClient:
    """
    OpenBot Python SDK Client

    Provides interfaces to receive video frames and sensor data from the OpenBot mobile app.
    """

    def __init__(self, host: str = "0.0.0.0", port: int = 8765):
        """
        Initialize the OpenBot client.

        Args:
            host: Host address to bind the WebSocket server (default: "0.0.0.0")
            port: Port number for the WebSocket server (default: 8765)
        """
        self.host = host
        self.port = port
        self.server = None
        self.websocket: Optional[WebSocketServerProtocol] = None
        self.loop = None
        self.server_thread = None

        # Data storage
        self._latest_video_frame: Optional[bytes] = None
        self._latest_sensor_data: Optional[Dict[str, Any]] = None

        # Callbacks
        self._video_frame_callback: Optional[Callable[[bytes], None]] = None
        self._sensor_data_callback: Optional[Callable[[Dict[str, Any]], None]] = None

        # Statistics
        self._frame_count = 0
        self._sensor_count = 0
        self._connected = False

    def start(self):
        """Start the WebSocket server in a separate thread."""
        if self.server_thread and self.server_thread.is_alive():
            print("Server is already running")
            return

        self.server_thread = threading.Thread(target=self._run_server, daemon=True)
        self.server_thread.start()
        print(f"OpenBot server started on {self.host}:{self.port}")

    def _run_server(self):
        """Run the WebSocket server event loop."""
        self.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.loop)

        async def serve():
            async with websockets.serve(self._handle_client, self.host, self.port):
                await asyncio.Future()  # Run forever

        self.loop.run_until_complete(serve())

    async def _handle_client(self, websocket: WebSocketServerProtocol, path: str):
        """
        Handle incoming WebSocket client connections.

        Args:
            websocket: WebSocket connection
            path: Request path
        """
        self.websocket = websocket
        self._connected = True
        client_address = websocket.remote_address
        print(f"Client connected from {client_address}")

        try:
            async for message in websocket:
                await self._process_message(message)
        except websockets.exceptions.ConnectionClosed:
            print(f"Client disconnected from {client_address}")
        finally:
            self._connected = False
            self.websocket = None

    async def _process_message(self, message: str):
        """
        Process incoming messages from the mobile app.

        Args:
            message: JSON message string
        """
        try:
            data = json.loads(message)
            msg_type = data.get("type")

            if msg_type == "video_frame":
                await self._handle_video_frame(data)
            elif msg_type == "sensor_data":
                await self._handle_sensor_data(data)
            elif msg_type == "ping":
                await self._send_pong()
            else:
                print(f"Unknown message type: {msg_type}")

        except json.JSONDecodeError as e:
            print(f"Failed to decode message: {e}")
        except Exception as e:
            print(f"Error processing message: {e}")

    async def _handle_video_frame(self, data: Dict[str, Any]):
        """
        Handle incoming video frame data.

        Args:
            data: Message data containing base64-encoded JPEG frame
        """
        try:
            base64_data = data.get("data")
            if base64_data:
                # Decode base64 to bytes
                jpeg_bytes = base64.b64decode(base64_data)
                self._latest_video_frame = jpeg_bytes
                self._frame_count += 1

                # Call callback if set
                if self._video_frame_callback:
                    self._video_frame_callback(jpeg_bytes)

        except Exception as e:
            print(f"Error handling video frame: {e}")

    async def _handle_sensor_data(self, data: Dict[str, Any]):
        """
        Handle incoming sensor data.

        Args:
            data: Message data containing sensor readings
        """
        try:
            sensor_data = data.get("data")
            if sensor_data:
                self._latest_sensor_data = sensor_data
                self._sensor_count += 1

                # Call callback if set
                if self._sensor_data_callback:
                    self._sensor_data_callback(sensor_data)

        except Exception as e:
            print(f"Error handling sensor data: {e}")

    async def _send_pong(self):
        """Send pong response to heartbeat ping."""
        if self.websocket:
            try:
                response = {
                    "type": "pong",
                    "timestamp": int(datetime.now().timestamp() * 1000)
                }
                await self.websocket.send(json.dumps(response))
            except Exception as e:
                print(f"Error sending pong: {e}")

    def get_video_frame(self) -> Optional[bytes]:
        """
        Get the latest video frame.

        Returns:
            Latest JPEG-encoded video frame as bytes, or None if no frame available
        """
        return self._latest_video_frame

    def get_sensor_data(self) -> Optional[Dict[str, Any]]:
        """
        Get the latest sensor data.

        Returns:
            Dictionary containing sensor data (accelerometer, gyroscope, magnetometer, battery, etc.),
            or None if no data available

        Example:
            {
                'accelerometer': {'x': 0.1, 'y': 0.2, 'z': 9.8},
                'gyroscope': {'x': 0.0, 'y': 0.0, 'z': 0.0},
                'magnetometer': {'x': 30.0, 'y': -20.0, 'z': 40.0},
                'battery_level': 0.85,
                'voltage': 12.6,
                'timestamp': '2025-12-30T12:00:00.000Z'
            }
        """
        return self._latest_sensor_data

    def set_video_frame_callback(self, callback: Callable[[bytes], None]):
        """
        Set a callback function to be called when a new video frame is received.

        Args:
            callback: Function that takes a bytes object (JPEG frame)
        """
        self._video_frame_callback = callback

    def set_sensor_data_callback(self, callback: Callable[[Dict[str, Any]], None]):
        """
        Set a callback function to be called when new sensor data is received.

        Args:
            callback: Function that takes a dictionary of sensor data
        """
        self._sensor_data_callback = callback

    def is_connected(self) -> bool:
        """
        Check if a client is currently connected.

        Returns:
            True if connected, False otherwise
        """
        return self._connected

    def get_statistics(self) -> Dict[str, Any]:
        """
        Get connection and data statistics.

        Returns:
            Dictionary containing statistics
        """
        return {
            "connected": self._connected,
            "frames_received": self._frame_count,
            "sensor_updates_received": self._sensor_count,
            "has_video_frame": self._latest_video_frame is not None,
            "has_sensor_data": self._latest_sensor_data is not None,
        }

    def stop(self):
        """Stop the WebSocket server."""
        if self.loop:
            self.loop.call_soon_threadsafe(self.loop.stop)
        if self.server_thread:
            self.server_thread.join(timeout=2)
        print("OpenBot server stopped")
