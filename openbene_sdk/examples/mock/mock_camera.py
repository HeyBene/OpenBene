#!/usr/bin/env python3
"""
Mock Camera Server

Simulates OpenBene robot's video stream server for testing purposes.
Generates random noise frames and sends them via TCP using the standard protocol:
- Header: 4 bytes (Big-Endian uint32) indicating JPEG size
- Body: JPEG image bytes

Usage:
    python mock_camera.py [--port 8000] [--fps 30] [--size 640x480]
"""

import socket
import struct
import time
import argparse
import numpy as np
import cv2
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class MockCamera:
    """
    Mock camera server that simulates robot video stream.

    Generates random noise frames and streams them to connected clients
    using the OpenBene video protocol.
    """

    def __init__(self, port=8000, fps=30, width=640, height=480, quality=80):
        """
        Initialize mock camera server.

        Args:
            port (int): TCP port to listen on
            fps (int): Frames per second to generate
            width (int): Frame width in pixels
            height (int): Frame height in pixels
            quality (int): JPEG quality (0-100)
        """
        self.port = port
        self.fps = fps
        self.width = width
        self.height = height
        self.quality = quality
        self.frame_delay = 1.0 / fps

        self.server_socket = None
        self.running = False
        self.frames_sent = 0

    def generate_frame(self) -> np.ndarray:
        """
        Generate a test frame.

        Creates a colorful test pattern with:
        - Random noise background
        - Frame counter text
        - FPS indicator
        - Timestamp

        Returns:
            np.ndarray: BGR image frame
        """
        # Create random noise (colorful static)
        frame = np.random.randint(0, 256, (self.height, self.width, 3), dtype=np.uint8)

        # Add some colored gradients to make it more interesting
        gradient_r = np.linspace(0, 255, self.width, dtype=np.uint8)
        gradient_g = np.linspace(255, 0, self.height, dtype=np.uint8)
        frame[:, :, 0] = (frame[:, :, 0] * 0.7 + np.tile(gradient_r, (self.height, 1)) * 0.3).astype(np.uint8)
        frame[:, :, 1] = (frame[:, :, 1] * 0.7 + np.tile(gradient_g, (self.width, 1)).T * 0.3).astype(np.uint8)

        # Add text overlay
        font = cv2.FONT_HERSHEY_SIMPLEX

        # Frame counter
        cv2.putText(
            frame,
            f"Frame: {self.frames_sent}",
            (10, 30),
            font,
            1,
            (255, 255, 255),
            2,
            cv2.LINE_AA
        )

        # FPS
        cv2.putText(
            frame,
            f"FPS: {self.fps}",
            (10, 70),
            font,
            1,
            (255, 255, 255),
            2,
            cv2.LINE_AA
        )

        # Mock Camera label
        cv2.putText(
            frame,
            "MOCK CAMERA",
            (self.width // 2 - 150, self.height // 2),
            font,
            1.5,
            (0, 255, 0),
            3,
            cv2.LINE_AA
        )

        # Resolution
        cv2.putText(
            frame,
            f"{self.width}x{self.height}",
            (10, self.height - 20),
            font,
            0.7,
            (255, 255, 255),
            2,
            cv2.LINE_AA
        )

        return frame

    def encode_frame(self, frame: np.ndarray) -> bytes:
        """
        Encode frame to JPEG.

        Args:
            frame (np.ndarray): BGR image frame

        Returns:
            bytes: JPEG-encoded image data
        """
        encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), self.quality]
        _, jpeg = cv2.imencode('.jpg', frame, encode_param)
        return jpeg.tobytes()

    def send_frame(self, client_socket: socket.socket, frame_data: bytes) -> bool:
        """
        Send frame using OpenBene protocol.

        Protocol:
            Header: 4 bytes (Big-Endian uint32) - JPEG size
            Body: JPEG bytes

        Args:
            client_socket (socket.socket): Connected client socket
            frame_data (bytes): JPEG-encoded frame

        Returns:
            bool: True if sent successfully
        """
        try:
            # Pack header: 4 bytes Big-Endian unsigned int
            header = struct.pack('>I', len(frame_data))

            # Send header + body
            client_socket.sendall(header + frame_data)
            return True

        except (socket.error, BrokenPipeError) as e:
            logger.warning(f"Failed to send frame: {e}")
            return False

    def handle_client(self, client_socket: socket.socket, client_address):
        """
        Handle connected client and stream frames.

        Args:
            client_socket (socket.socket): Client socket
            client_address (tuple): Client address (ip, port)
        """
        logger.info(f"Client connected from {client_address}")

        try:
            while self.running:
                start_time = time.time()

                # Generate frame
                frame = self.generate_frame()

                # Encode to JPEG
                frame_data = self.encode_frame(frame)

                # Send frame
                if not self.send_frame(client_socket, frame_data):
                    break

                self.frames_sent += 1

                # Log stats every 100 frames
                if self.frames_sent % 100 == 0:
                    logger.info(f"Sent {self.frames_sent} frames, "
                                f"Last frame: {len(frame_data)} bytes")

                # Maintain FPS timing
                elapsed = time.time() - start_time
                sleep_time = max(0, self.frame_delay - elapsed)
                time.sleep(sleep_time)

        except Exception as e:
            logger.error(f"Error streaming to client: {e}")

        finally:
            client_socket.close()
            logger.info(f"Client {client_address} disconnected. "
                        f"Total frames sent: {self.frames_sent}")

    def start(self):
        """Start the mock camera server."""
        logger.info(f"Starting mock camera server on port {self.port}")
        logger.info(f"Stream settings: {self.width}x{self.height} @ {self.fps} FPS, Quality: {self.quality}")

        try:
            # Create TCP server socket
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.server_socket.bind(('0.0.0.0', self.port))
            self.server_socket.listen(1)

            logger.info(f"Mock camera server listening on 0.0.0.0:{self.port}")
            logger.info("Waiting for client connection...")

            self.running = True

            while self.running:
                try:
                    # Accept client connection
                    client_socket, client_address = self.server_socket.accept()

                    # Reset frame counter for new client
                    self.frames_sent = 0

                    # Handle client in current thread (single client for simplicity)
                    self.handle_client(client_socket, client_address)

                except KeyboardInterrupt:
                    logger.info("Interrupted by user")
                    break

                except Exception as e:
                    logger.error(f"Error accepting connection: {e}")
                    time.sleep(1)

        finally:
            self.stop()

    def stop(self):
        """Stop the mock camera server."""
        logger.info("Stopping mock camera server...")
        self.running = False

        if self.server_socket:
            try:
                self.server_socket.close()
            except:
                pass

        logger.info("Mock camera server stopped")


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description='Mock OpenBene Camera Server')
    parser.add_argument('--port', type=int, default=8000, help='TCP port (default: 8000)')
    parser.add_argument('--fps', type=int, default=30, help='Frames per second (default: 30)')
    parser.add_argument('--size', type=str, default='640x480', help='Frame size WxH (default: 640x480)')
    parser.add_argument('--quality', type=int, default=80, help='JPEG quality 0-100 (default: 80)')

    args = parser.parse_args()

    # Parse size
    try:
        width, height = map(int, args.size.split('x'))
    except ValueError:
        logger.error(f"Invalid size format: {args.size}. Use WIDTHxHEIGHT (e.g., 640x480)")
        return

    # Create and start mock camera
    camera = MockCamera(
        port=args.port,
        fps=args.fps,
        width=width,
        height=height,
        quality=args.quality
    )

    try:
        camera.start()
    except KeyboardInterrupt:
        logger.info("\nShutting down...")
    finally:
        camera.stop()


if __name__ == '__main__':
    main()
