"""
OpenBene Robot Controller Module.

This module provides the main OpenBene class for connecting to and controlling
OpenBene robots via TCP.
"""

import socket
import json
import logging
import time
from typing import Optional, Tuple
from .discovery import Discovery

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class ConnectionError(Exception):
    """Raised when connection to robot fails."""
    pass


class OpenBene:
    """
    Main controller class for OpenBene robots.

    This class handles TCP connection to discovered robots and provides
    high-level control APIs for robot movement.

    Attributes:
        ip (str): Robot IP address.
        port (int): TCP port (default: 8888).
        sock (socket.socket): TCP socket connection.
        connected (bool): Connection status.
    """

    TCP_PORT = 8888
    TIMEOUT = 5.0

    def __init__(self, ip: str, port: int = TCP_PORT):
        """
        Initialize OpenBene controller.

        Args:
            ip (str): Robot IP address.
            port (int): TCP port. Defaults to 8888.
        """
        self.ip = ip
        self.port = port
        self.sock: Optional[socket.socket] = None
        self.connected = False

    def connect(self, timeout: float = TIMEOUT) -> bool:
        """
        Establish TCP connection to the robot.

        Args:
            timeout (float): Connection timeout in seconds.

        Returns:
            bool: True if connection successful, False otherwise.

        Raises:
            ConnectionError: If connection fails.
        """
        try:
            logger.info(f"Connecting to robot at {self.ip}:{self.port}...")

            # Create TCP socket
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(timeout)

            # Connect to robot
            self.sock.connect((self.ip, self.port))
            self.connected = True

            logger.info(f"Successfully connected to {self.ip}:{self.port}")
            return True

        except socket.timeout:
            logger.error(f"Connection timeout to {self.ip}:{self.port}")
            raise ConnectionError(f"Connection timeout to {self.ip}:{self.port}")
        except socket.error as e:
            logger.error(f"Failed to connect to {self.ip}:{self.port}: {e}")
            raise ConnectionError(f"Failed to connect: {e}")

    def disconnect(self):
        """
        Close the TCP connection to the robot.
        """
        if self.sock:
            try:
                self.sock.close()
                logger.info(f"Disconnected from {self.ip}")
            except Exception as e:
                logger.warning(f"Error during disconnect: {e}")
            finally:
                self.connected = False
                self.sock = None

    def _send_command(self, command: dict) -> bool:
        """
        Send a JSON command to the robot.

        Args:
            command (dict): Command dictionary to send.

        Returns:
            bool: True if command sent successfully.

        Raises:
            ConnectionError: If not connected or send fails.
        """
        if not self.connected or not self.sock:
            raise ConnectionError("Not connected to robot. Call connect() first.")

        try:
            # Convert to JSON and add newline (as per protocol)
            data = json.dumps(command) + '\n'
            encoded = data.encode('utf-8')

            # Send command
            self.sock.sendall(encoded)
            logger.debug(f"Sent command: {command}")
            return True

        except socket.error as e:
            logger.error(f"Failed to send command: {e}")
            self.connected = False
            raise ConnectionError(f"Failed to send command: {e}")

    def drive(self, left_speed: float, right_speed: float) -> bool:
        """
        Control robot motor speeds.

        Args:
            left_speed (float): Left wheel speed (-1.0 to 1.0).
            right_speed (float): Right wheel speed (-1.0 to 1.0).

        Returns:
            bool: True if command sent successfully.

        Raises:
            ValueError: If speed values are out of range.
            ConnectionError: If not connected.

        Example:
            >>> bot = OpenBene("192.168.1.100")
            >>> bot.connect()
            >>> bot.drive(0.5, 0.5)  # Move forward at 50% speed
        """
        # Validate speed range
        if not (-1.0 <= left_speed <= 1.0):
            raise ValueError(f"left_speed must be between -1.0 and 1.0, got {left_speed}")
        if not (-1.0 <= right_speed <= 1.0):
            raise ValueError(f"right_speed must be between -1.0 and 1.0, got {right_speed}")

        # Prepare command as per protocol specification
        command = {
            "cmd": "drive",
            "val": [left_speed, right_speed]
        }

        logger.info(f"Drive command: left={left_speed}, right={right_speed}")
        return self._send_command(command)

    def stop(self) -> bool:
        """
        Stop the robot immediately.

        Returns:
            bool: True if command sent successfully.

        Raises:
            ConnectionError: If not connected.

        Example:
            >>> bot.stop()
        """
        command = {"cmd": "stop"}
        logger.info("Stop command sent")
        return self._send_command(command)

    def move_forward(self, speed: float = 0.5) -> bool:
        """
        Move robot forward at specified speed.

        Args:
            speed (float): Speed (0.0 to 1.0). Defaults to 0.5.

        Returns:
            bool: True if command sent successfully.
        """
        return self.drive(speed, speed)

    def move_backward(self, speed: float = 0.5) -> bool:
        """
        Move robot backward at specified speed.

        Args:
            speed (float): Speed (0.0 to 1.0). Defaults to 0.5.

        Returns:
            bool: True if command sent successfully.
        """
        return self.drive(-speed, -speed)

    def turn_left(self, speed: float = 0.5) -> bool:
        """
        Turn robot left by rotating in place.

        Args:
            speed (float): Turn speed (0.0 to 1.0). Defaults to 0.5.

        Returns:
            bool: True if command sent successfully.
        """
        return self.drive(-speed, speed)

    def turn_right(self, speed: float = 0.5) -> bool:
        """
        Turn robot right by rotating in place.

        Args:
            speed (float): Turn speed (0.0 to 1.0). Defaults to 0.5.

        Returns:
            bool: True if command sent successfully.
        """
        return self.drive(speed, -speed)

    @classmethod
    def connect_auto(cls, discovery: Optional[Discovery] = None,
                     timeout: float = 10.0) -> 'OpenBene':
        """
        Automatically discover and connect to first available robot.

        Args:
            discovery (Discovery): Discovery instance. If None, creates new one.
            timeout (float): Discovery timeout in seconds.

        Returns:
            OpenBene: Connected robot instance.

        Raises:
            ConnectionError: If no robot found or connection fails.

        Example:
            >>> bot = OpenBene.connect_auto()
            >>> bot.drive(0.5, 0.5)
        """
        logger.info("Starting auto-discovery...")

        discovered_bot = None

        def on_discovery(data):
            nonlocal discovered_bot
            discovered_bot = data

        # Create discovery instance if not provided
        if discovery is None:
            discovery = Discovery(port=12345)

        # Start discovery in a separate thread with timeout
        import threading

        discovery_thread = threading.Thread(
            target=discovery.start,
            kwargs={'on_discovery': on_discovery}
        )
        discovery_thread.daemon = True
        discovery_thread.start()

        # Wait for discovery with timeout
        start_time = time.time()
        while discovered_bot is None:
            if time.time() - start_time > timeout:
                discovery.stop()
                raise ConnectionError(f"No robot found within {timeout} seconds")
            time.sleep(0.1)

        # Stop discovery
        discovery.stop()

        # Connect to discovered robot
        bot_ip = discovered_bot.get('ip')
        bot_name = discovered_bot.get('name')

        logger.info(f"Found robot: {bot_name} at {bot_ip}")

        bot = cls(bot_ip)
        bot.connect()

        return bot

    def __enter__(self):
        """Context manager entry."""
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.disconnect()

    def __repr__(self):
        """String representation."""
        status = "connected" if self.connected else "disconnected"
        return f"OpenBene(ip='{self.ip}', port={self.port}, status='{status}')"
