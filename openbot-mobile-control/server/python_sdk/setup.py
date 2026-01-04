from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="openbot-sdk",
    version="1.0.0",
    author="OpenBot Team",
    author_email="info@openbot.org",
    description="Python SDK for OpenBot mobile robot control",
    long_description=long_description,
    long_description_content_type="text/markdown",
    url="https://github.com/openbot/openbot-app",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "Topic :: Software Development :: Libraries",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
    ],
    python_requires=">=3.8",
    install_requires=[
        "websockets>=12.0",
        "numpy>=1.24.0",
        "opencv-python>=4.8.0",
    ],
)
