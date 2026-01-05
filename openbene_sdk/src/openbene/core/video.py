"""
Video Streaming Module

Implements TCP-based video frame reception from OpenBene robot.
Uses Header (4 bytes) + Body (JPEG bytes) protocol for frame transmission.
"""

import socket
import struct
import threading
import logging
import time
from typing import Optional, Callable
import numpy as np
import cv2

logger = logging.getLogger(__name__)


def recv_exact(sock: socket.socket, num_bytes: int) -> bytes:
    """
    Receive exactly num_bytes from socket.

    This function solves the TCP "half-packet" problem by ensuring
    we read the exact number of bytes requested, even if they arrive
    in multiple recv() calls.

    Args:
        sock (socket.socket): The socket to read from
        num_bytes (int): Exact number of bytes to receive

    Returns:
        bytes: Exactly num_bytes of data

    Raises:
        ConnectionError: If socket closes before receiving all data

    Example:
        >>> header = recv_exact(sock, 4)  # Always returns exactly 4 bytes
        >>> size = struct.unpack('>I', header)[0]
        >>> jpeg_data = recv_exact(sock, size)  # Always returns full JPEG
    """
    data = b''
    while len(data) < num_bytes:
        remaining = num_bytes - len(data)
        try:
            chunk = sock.recv(remaining)
            if not chunk:
                # Socket closed by remote
                raise ConnectionError("Socket connection closed by remote")
            data += chunk
        except socket.timeout:
            # Allow timeout to propagate
            raise
        except OSError as e:
            raise ConnectionError(f"Socket error during recv: {e}")

    return data


class VideoReceiver(threading.Thread):
    """
    Video frame receiver for OpenBene robots.

    Connects to robot's video stream server (port 8000) and continuously
    receives JPEG-encoded frames via TCP.

    Protocol:
        - Header: 4 bytes (Big-Endian uint32) indicating JPEG size
        - Body: JPEG image bytes

    The receiver runs in a separate thread and delivers decoded frames
    via callback function.

    Attributes:
        ip (str): Robot IP address
        port (int): Video stream port (default: 8000)
        running (bool): Whether the receiver is actively streaming
        sock (socket.socket): TCP socket connection

    Example:
        >>> def on_frame(frame):
        ...     cv2.imshow('Robot Camera', frame)
        ...     cv2.waitKey(1)
        ...
        >>> receiver = VideoReceiver("192.168.1.100", on_frame=on_frame)
        >>> receiver.start()
        >>> time.sleep(10)
        >>> receiver.stop()
    """

    DEFAULT_PORT = 8000
    HEADER_SIZE = 4  # 4 bytes for uint32 frame size
    TIMEOUT = 5.0    # Socket timeout in seconds

    def __init__(
        self,
        ip: str,
        port: int = DEFAULT_PORT,
        on_frame: Optional[Callable[[np.ndarray], None]] = None,
        on_error: Optional[Callable[[Exception], None]] = None
    ):
        """
        Initialize video receiver.

        Args:
            ip (str): Robot IP address
            port (int): Video stream port. Defaults to 8000.
            on_frame (callable): Callback function for each frame.
                                 Signature: on_frame(frame: np.ndarray)
            on_error (callable): Callback function for errors.
                                 Signature: on_error(exception: Exception)
        """
        super().__init__(daemon=True)
        self.ip = ip
        self.port = port
        self.on_frame = on_frame
        self.on_error = on_error

        self.running = False
        self.sock: Optional[socket.socket] = None

        # Statistics
        self.frames_received = 0
        self.bytes_received = 0
        self.last_fps_time = time.time()
        self.fps = 0.0

    def connect(self) -> bool:
        """
        Connect to robot video stream server.

        Returns:
            bool: True if connection successful

        Raises:
            ConnectionError: If connection fails
        """
        try:
            logger.info(f"Connecting to video stream at {self.ip}:{self.port}...")

            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(self.TIMEOUT)
            self.sock.connect((self.ip, self.port))

            logger.info(f"Successfully connected to video stream")
            return True

        except socket.timeout:
            error_msg = f"Connection timeout to {self.ip}:{self.port}"
            logger.error(error_msg)
            raise ConnectionError(error_msg)

        except socket.error as e:
            error_msg = f"Failed to connect to {self.ip}:{self.port}: {e}"
            logger.error(error_msg)
            raise ConnectionError(error_msg)

    def disconnect(self):
        """Close socket connection."""
        if self.sock:
            try:
                self.sock.close()
                logger.info("Video stream disconnected")
            except Exception as e:
                logger.warning(f"Error during disconnect: {e}")
            finally:
                self.sock = None

    def run(self):
        """
        Main thread loop - receives and decodes video frames.

        This method runs in a separate thread and continuously:
        1. Reads 4-byte header (frame size)
        2. Reads JPEG data (exact size from header)
        3. Decodes JPEG to numpy array
        4. Calls on_frame callback with decoded frame
        """
        logger.info("Video receiver thread started")
        self.running = True
        frame_count = 0
        fps_start_time = time.time()

        try:
            # Connect to video stream
            self.connect()

            while self.running:
                try:
                    # Step 1: Read header (4 bytes, big-endian uint32)
                    header = recv_exact(self.sock, self.HEADER_SIZE)
                    frame_size = struct.unpack('>I', header)[0]

                    # Validate frame size (sanity check)
                    if frame_size == 0 or frame_size > 10 * 1024 * 1024:  # Max 10MB
                        logger.warning(f"Invalid frame size: {frame_size} bytes, skipping")
                        continue

                    # Step 2: Read JPEG data (exact size from header)
                    jpeg_data = recv_exact(self.sock, frame_size)
                    self.bytes_received += frame_size + self.HEADER_SIZE

                    # Step 3: Decode JPEG to numpy array
                    jpeg_array = np.frombuffer(jpeg_data, dtype=np.uint8)
                    frame = cv2.imdecode(jpeg_array, cv2.IMREAD_COLOR)

                    if frame is None:
                        logger.warning("Failed to decode JPEG frame, skipping")
                        continue

                    # Step 4: Deliver frame via callback
                    self.frames_received += 1
                    frame_count += 1

                    if self.on_frame:
                        try:
                            self.on_frame(frame)
                        except Exception as e:
                            logger.error(f"Error in frame callback: {e}")

                    # Calculate FPS every second
                    current_time = time.time()
                    if current_time - fps_start_time >= 1.0:
                        self.fps = frame_count / (current_time - fps_start_time)
                        logger.debug(f"Video FPS: {self.fps:.1f}, Total frames: {self.frames_received}")
                        frame_count = 0
                        fps_start_time = current_time

                except ConnectionError as e:
                    if self.running:
                        logger.error(f"Connection lost: {e}")
                        if self.on_error:
                            self.on_error(e)
                    break

                except struct.error as e:
                    logger.error(f"Protocol error unpacking header: {e}")
                    break

                except Exception as e:
                    logger.error(f"Unexpected error in video receiver: {e}")
                    if self.on_error:
                        self.on_error(e)
                    break

        except Exception as e:
            logger.error(f"Fatal error in video receiver: {e}")
            if self.on_error:
                self.on_error(e)

        finally:
            self.disconnect()
            self.running = False
            logger.info(f"Video receiver stopped. Total frames: {self.frames_received}")

    def stop(self):
        """Stop the video receiver thread."""
        logger.info("Stopping video receiver...")
        self.running = False

        # Close socket to unblock recv()
        if self.sock:
            try:
                self.sock.shutdown(socket.SHUT_RDWR)
            except:
                pass
            self.sock.close()

        # Wait for thread to finish
        if self.is_alive():
            self.join(timeout=2.0)

    def get_stats(self) -> dict:
        """
        Get video stream statistics.

        Returns:
            dict: Statistics including frames received, FPS, and bytes
        """
        return {
            'frames_received': self.frames_received,
            'bytes_received': self.bytes_received,
            'fps': self.fps,
            'running': self.running,
        }

    def __repr__(self):
        """String representation."""
        status = "running" if self.running else "stopped"
        return f"VideoReceiver(ip='{self.ip}', port={self.port}, status='{status}', fps={self.fps:.1f})"
