"""
OpenBot Python SDK

A Python SDK for communicating with the OpenBot mobile app.
Provides interfaces to receive video frames and sensor data from the robot.
"""

__version__ = "1.0.0"
__author__ = "OpenBot Team"

from .client import OpenBotClient

__all__ = ["OpenBotClient"]
