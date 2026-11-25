"""PC-side Zenoh receiver and recorder for OpenBene capture sessions."""

from .protocol import (
    CaptureFrame,
    FrameCodecError,
    FrameMetadata,
    decode_capture_frame,
    decode_legacy_video,
    parse_key,
    sanitize_robot_id,
)
from .recorder import McapRecorder, RecordingController, RecorderStats
from .receiver import OpenBeneReceiver
from .viewer import LiveViewer

__all__ = [
    "CaptureFrame",
    "FrameCodecError",
    "FrameMetadata",
    "LiveViewer",
    "McapRecorder",
    "OpenBeneReceiver",
    "RecorderStats",
    "RecordingController",
    "decode_capture_frame",
    "decode_legacy_video",
    "parse_key",
    "sanitize_robot_id",
]

__version__ = "0.1.0"
