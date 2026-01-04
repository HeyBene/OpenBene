"""
OpenBene SDK - Python SDK for OpenBene Robot Control.

This package provides tools for discovering and controlling OpenBene robots
over the network.
"""

from .discovery import Discovery
from .openbene import OpenBene, ConnectionError

__version__ = '0.1.0'
__all__ = ['Discovery', 'OpenBene', 'ConnectionError']
