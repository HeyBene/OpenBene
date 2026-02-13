"""
OpenBene Discovery Module.

This module provides UDP broadcast discovery functionality for finding
OpenBene robots on the local network.
"""

import socket
import json
import logging
from typing import Optional, Callable, Dict, Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class Discovery:
    """
    UDP Discovery service for finding OpenBene robots on the local network.

    This class listens for UDP broadcast messages on port 12345 and parses
    discovery messages from OpenBene robot apps.

    Attributes:
        port (int): UDP port to listen on (default: 12345).
        sock (socket.socket): UDP socket for receiving broadcasts.
        running (bool): Flag indicating if discovery is active.
    """

    def __init__(self, port: int = 12345):
        """
        Initialize the Discovery service.

        Args:
            port (int): UDP port to listen on. Defaults to 12345.
        """
        self.port = port
        self.sock: Optional[socket.socket] = None
        self.running = False

    def start(self, on_discovery: Optional[Callable[[Dict[str, Any]], None]] = None) -> None:
        """Start listening for UDP broadcast messages.

        This method blocks and continuously listens for discovery messages.
        When a valid message is received, it calls the on_discovery callback
        (if provided) or prints the discovered bot information.

        Args:
            on_discovery: Optional callback function that receives
                the parsed discovery data as a dictionary.

        Raises:
            OSError: If socket binding fails.
        """
        try:
            # Create UDP socket
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

            # Bind to all interfaces on the specified port
            self.sock.bind(('', self.port))
            self.running = True

            logger.info(f"Discovery service started on UDP port {self.port}")
            logger.info("Waiting for OpenBene robots to broadcast...")

            while self.running:
                try:
                    # Receive broadcast message (buffer size: 1024 bytes)
                    data, addr = self.sock.recvfrom(1024)

                    # Decode and parse JSON
                    message = data.decode('utf-8')
                    discovery_data = json.loads(message)

                    # Validate message structure
                    if self._validate_discovery_message(discovery_data):
                        bot_name = discovery_data.get('name', 'Unknown')
                        bot_ip = discovery_data.get('ip', addr[0])

                        logger.info(f"Discovered Bot: [{bot_name}] at [{bot_ip}]")

                        # Call callback if provided
                        if on_discovery:
                            on_discovery(discovery_data)
                    else:
                        logger.warning(f"Invalid discovery message from {addr[0]}: {message}")

                except json.JSONDecodeError:
                    logger.error(f"Failed to decode JSON from {addr[0]}: {data}")
                except Exception as e:
                    if self.running:  # Only log if not intentionally stopped
                        logger.error(f"Error processing message: {e}")

        except OSError as e:
            logger.error(f"Failed to bind to port {self.port}: {e}")
            raise
        finally:
            self.stop()

    def stop(self) -> None:
        """Stop the discovery service and close the socket."""
        self.running = False
        if self.sock:
            self.sock.close()
            logger.info("Discovery service stopped.")

    def _validate_discovery_message(self, data: Dict[str, Any]) -> bool:
        """
        Validate discovery message structure.

        Args:
            data (dict): Parsed JSON data from broadcast message.

        Returns:
            bool: True if message is valid, False otherwise.
        """
        required_fields = ['type', 'name', 'ip']

        # Check if all required fields are present
        if not all(field in data for field in required_fields):
            return False

        # Check if type is 'discovery'
        if data.get('type') != 'discovery':
            return False

        return True


def main() -> None:
    """Main entry point for testing the Discovery service.

    Runs the discovery service and prints found robots to console.
    Press Ctrl+C to stop.
    """
    discovery = Discovery(port=12345)

    try:
        discovery.start()
    except KeyboardInterrupt:
        logger.info("\nDiscovery service interrupted by user.")
        discovery.stop()
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        discovery.stop()


if __name__ == '__main__':
    main()
