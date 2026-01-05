#!/usr/bin/env python3
"""
Mock TCP Server with Telemetry

Simulates OpenBene robot's TCP control server with bidirectional communication:
- Receives control commands from PC (drive, stop)
- Sends status telemetry back to PC every 0.5 seconds

Protocol:
    PC -> Robot: JSON commands (newline-terminated)
    Robot -> PC: JSON status messages (newline-terminated)

Usage:
    python mock_tcp_server.py [--port 8888]
"""

import socket
import json
import threading
import time
import argparse
import logging
import random

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class MockRobotServer:
    """
    Mock robot TCP server with telemetry simulation.

    Simulates a complete robot control interface including:
    - Command reception (drive, stop)
    - Status telemetry broadcasting
    - Battery voltage simulation
    - Wheel speed reporting
    """

    def __init__(self, port=8888, telemetry_interval=0.5):
        """
        Initialize mock robot server.

        Args:
            port (int): TCP port to listen on
            telemetry_interval (float): Seconds between telemetry broadcasts
        """
        self.port = port
        self.telemetry_interval = telemetry_interval

        self.server_socket = None
        self.client_socket = None
        self.client_address = None
        self.running = False

        # Robot state
        self.battery_voltage = 12.4  # Volts
        self.wheel_speeds = [0.0, 0.0]  # Left, Right (-1.0 to 1.0)
        self.state_lock = threading.Lock()

        # Telemetry thread
        self.telemetry_thread = None

    def handle_command(self, message: str):
        """
        Process received command.

        Args:
            message (str): JSON command string
        """
        try:
            command = json.loads(message)
            cmd_type = command.get('cmd')

            if cmd_type == 'drive':
                val = command.get('val', [0.0, 0.0])
                with self.state_lock:
                    self.wheel_speeds = val
                logger.info(f"Drive command: {val}")

            elif cmd_type == 'stop':
                with self.state_lock:
                    self.wheel_speeds = [0.0, 0.0]
                logger.info("Stop command")

            else:
                logger.warning(f"Unknown command: {cmd_type}")

        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON: {e}")
        except Exception as e:
            logger.error(f"Error handling command: {e}")

    def send_telemetry(self):
        """
        Send status telemetry to connected client.

        Sends JSON message: {"type": "status", "bat": float, "spd": [float, float]}
        """
        if not self.client_socket:
            return

        try:
            # Get current state
            with self.state_lock:
                battery = self.battery_voltage
                speeds = self.wheel_speeds.copy()

            # Build status message
            status = {
                "type": "status",
                "bat": round(battery, 2),
                "spd": [round(speeds[0], 3), round(speeds[1], 3)]
            }

            # Send as JSON line
            message = json.dumps(status) + '\n'
            self.client_socket.sendall(message.encode('utf-8'))

            logger.debug(f"Sent telemetry: bat={battery:.1f}V, spd={speeds}")

        except (BrokenPipeError, OSError) as e:
            logger.warning(f"Failed to send telemetry: {e}")
            # Client disconnected, will be detected in main loop
        except Exception as e:
            logger.error(f"Error sending telemetry: {e}")

    def telemetry_loop(self):
        """
        Background thread that sends periodic telemetry.
        """
        logger.info(f"Telemetry thread started (interval: {self.telemetry_interval}s)")

        while self.running and self.client_socket:
            try:
                # Send current status
                self.send_telemetry()

                # Simulate battery drain (very slow)
                with self.state_lock:
                    self.battery_voltage -= 0.001  # 0.001V per update
                    if self.battery_voltage < 10.0:
                        self.battery_voltage = 12.4  # Reset for testing

                # Wait for next interval
                time.sleep(self.telemetry_interval)

            except Exception as e:
                logger.error(f"Error in telemetry loop: {e}")
                break

        logger.info("Telemetry thread stopped")

    def handle_client(self):
        """
        Handle connected client - receive commands and send telemetry.
        """
        logger.info(f"Client connected from {self.client_address}")

        # Start telemetry thread
        self.telemetry_thread = threading.Thread(
            target=self.telemetry_loop,
            daemon=True
        )
        self.telemetry_thread.start()

        # Receive commands
        buffer = ""

        try:
            while self.running:
                data = self.client_socket.recv(4096)

                if not data:
                    logger.info("Client disconnected")
                    break

                # Decode and buffer
                buffer += data.decode('utf-8')

                # Process complete lines
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    line = line.strip()

                    if line:
                        logger.info(f"Received: {line}")
                        self.handle_command(line)

        except Exception as e:
            logger.error(f"Error handling client: {e}")

        finally:
            # Wait for telemetry thread to finish
            if self.telemetry_thread:
                self.telemetry_thread.join(timeout=1.0)

            # Reset state
            with self.state_lock:
                self.wheel_speeds = [0.0, 0.0]

            if self.client_socket:
                self.client_socket.close()
                self.client_socket = None

            logger.info(f"Client {self.client_address} disconnected")

    def start(self):
        """Start the mock robot server."""
        logger.info(f"Starting mock robot server on port {self.port}")

        try:
            # Create server socket
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.server_socket.bind(('0.0.0.0', self.port))
            self.server_socket.listen(1)

            logger.info(f"Mock robot listening on 0.0.0.0:{self.port}")
            logger.info("Waiting for client connection...")

            self.running = True

            while self.running:
                try:
                    # Accept client
                    self.client_socket, self.client_address = self.server_socket.accept()

                    # Handle client (blocks until disconnect)
                    self.handle_client()

                    logger.info("Waiting for next connection...")

                except KeyboardInterrupt:
                    logger.info("Interrupted by user")
                    break

                except Exception as e:
                    logger.error(f"Error accepting connection: {e}")
                    time.sleep(1)

        finally:
            self.stop()

    def stop(self):
        """Stop the mock robot server."""
        logger.info("Stopping mock robot server...")
        self.running = False

        if self.client_socket:
            try:
                self.client_socket.close()
            except:
                pass

        if self.server_socket:
            try:
                self.server_socket.close()
            except:
                pass

        logger.info("Mock robot server stopped")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Mock OpenBene Robot TCP Server with Telemetry')
    parser.add_argument('--port', type=int, default=8888, help='TCP port (default: 8888)')
    parser.add_argument('--interval', type=float, default=0.5, help='Telemetry interval in seconds (default: 0.5)')

    args = parser.parse_args()

    server = MockRobotServer(port=args.port, telemetry_interval=args.interval)

    try:
        server.start()
    except KeyboardInterrupt:
        logger.info("\nShutting down...")
    finally:
        server.stop()


if __name__ == '__main__':
    main()
