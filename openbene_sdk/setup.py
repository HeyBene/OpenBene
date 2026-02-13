"""
OpenBene SDK - Python package for OpenBot robot control

Setup configuration for PyPI distribution.
"""

from setuptools import setup, find_packages
from pathlib import Path

# Read README for long description
readme_file = Path(__file__).parent / "README.md"
long_description = readme_file.read_text(encoding="utf-8") if readme_file.exists() else ""

setup(
    # Package metadata
    name="openbene",
    version="2.0.0",  # Simplified WebSocket-only architecture
    description="Phone as Body, PC as Brain - Control OpenBot robots with Python",
    long_description=long_description,
    long_description_content_type="text/markdown",

    # Author information
    author="OpenBene Contributors",
    author_email="your.email@example.com",  # TODO: Update with actual email
    maintainer="OpenBene Team",

    # URLs
    url="https://github.com/yourusername/openbene",  # TODO: Update with actual repo
    project_urls={
        "Bug Reports": "https://github.com/yourusername/openbene/issues",
        "Source": "https://github.com/yourusername/openbene",
        "Documentation": "https://github.com/yourusername/openbene/wiki",
    },

    # License
    license="MIT",

    # Package discovery
    package_dir={"": "src"},
    packages=find_packages(where="src"),

    # Python version requirement
    python_requires=">=3.8",

    # Dependencies
    install_requires=[
        # WebSocket support for openbot-mobile-control app integration
        "websockets>=10.0",

        # Video streaming support (optional, but recommended)
        "opencv-python>=4.5.0",
        "numpy>=1.19.0",

        # MQTT support for smart home devices
        "paho-mqtt>=1.6.0",
    ],

    # Optional dependencies for advanced features
    extras_require={
        "dev": [
            "pytest>=6.0.0",
            "black>=21.0",
            "flake8>=3.9.0",
            "mypy>=0.900",
        ],
        "keyboard": [
            "pynput>=1.7.0",  # For keyboard_drive.py advanced mode
        ],
        "vision": [
            # Will be used in Milestone 2
            "opencv-python>=4.5.0",
            "numpy>=1.19.0",
            "pillow>=8.0.0",
        ],
        "mqtt": [
            "paho-mqtt>=1.6.0",
        ],
    },

    # Package classifiers (for PyPI)
    classifiers=[
        # Development status
        "Development Status :: 4 - Beta",

        # Intended audience
        "Intended Audience :: Developers",
        "Intended Audience :: Education",
        "Intended Audience :: Science/Research",

        # Topic
        "Topic :: Scientific/Engineering :: Artificial Intelligence",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Hardware",

        # License
        "License :: OSI Approved :: MIT License",

        # Python versions
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",

        # OS
        "Operating System :: OS Independent",
    ],

    # Keywords for PyPI search
    keywords=[
        "robot",
        "robotics",
        "openbot",
        "mobile robot",
        "android",
        "remote control",
        "iot",
        "automation",
        "opencv",
        "computer vision",
    ],

    # Entry points (console scripts)
    entry_points={
        "console_scripts": [
            # Add CLI commands here in future, e.g.:
            # "openbene=openbene.cli:main",
        ],
    },

    # Include additional files
    include_package_data=True,
    zip_safe=False,
)
