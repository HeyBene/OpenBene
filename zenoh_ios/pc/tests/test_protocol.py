import json
import struct

import pytest

from openbene_receiver.protocol import (
    CaptureFrame,
    FrameCodecError,
    FrameMetadata,
    PACKET_MAGIC,
    VIDEO_MAGIC,
    decode_capture_frame,
    decode_legacy_video,
    encode_capture_frame,
    encode_legacy_video,
    parse_key,
    sanitize_robot_id,
)


def test_android_golden_video_frame():
    payload = bytes(
        [
            0x5A, 0x46, 0x52, 0x4D,
            0x01, 0x00,
            0x00, 0x00,
            0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01,
            0x07, 0x00, 0x00, 0x00,
            0xAA, 0xBB,
        ]
    )
    frame_id, timestamp_ns, jpeg = decode_legacy_video(payload)
    assert frame_id == 7
    assert timestamp_ns == 0x0102030405060708
    assert jpeg == b"\xaa\xbb"


def test_legacy_roundtrip():
    encoded = encode_legacy_video(b"\xff\xd8", frame_id=3, timestamp_ns=1_700_000_000_000_000_000)
    assert encoded[:4] == b"ZFRM"
    assert struct.unpack_from("<I", encoded, 0)[0] == VIDEO_MAGIC
    assert decode_legacy_video(encoded) == (3, 1_700_000_000_000_000_000, b"\xff\xd8")


def test_capture_frame_roundtrip():
    metadata = FrameMetadata(
        width=1920,
        height=1440,
        depth_width=256,
        depth_height=192,
        fx=1500.0,
        fy=1500.0,
        cx=960.0,
        cy=720.0,
        tracking_state="normal",
        depth_source="smoothed_scene_depth",
        confidence_width=256,
        confidence_height=192,
    )
    frame = CaptureFrame(
        frame_id=12,
        timestamp_ns=1_700_000_000_123_456_789,
        rgb_jpeg=b"\xff\xd8\xff",
        depth_png=b"\x89PNG",
        confidence_png=b"\x89PNH",
        pose=tuple(float(i) for i in range(16)),
        metadata=metadata,
        flags=0b1111,
    )
    encoded = encode_capture_frame(frame)
    assert encoded[:4] == b"ZPKD"
    assert struct.unpack_from("<I", encoded, 0)[0] == PACKET_MAGIC
    assert decode_capture_frame(encoded) == frame


def test_metadata_uses_swift_key_names():
    encoded = encode_capture_frame(
        CaptureFrame(frame_id=1, timestamp_ns=1, metadata=FrameMetadata(width=640, height=480))
    )
    section_count = struct.unpack_from("<I", encoded, 20)[0]
    offset = 24
    for _ in range(section_count):
        kind, length = struct.unpack_from("<II", encoded, offset)
        offset += 8
        if kind == 5:
            document = json.loads(encoded[offset : offset + length])
            assert document["width"] == 640
            assert document["depthWidth"] == 0
            assert document["trackingState"] == "unknown"
            return
        offset += length
    pytest.fail("metadata section missing")


def test_rejects_bad_frames():
    with pytest.raises(FrameCodecError):
        decode_legacy_video(b"ZFR")
    with pytest.raises(FrameCodecError):
        decode_capture_frame(b"ZPK")
    with pytest.raises(FrameCodecError):
        decode_legacy_video(b"\x00" + encode_legacy_video(b"", 1, 1)[1:])
    truncated = encode_capture_frame(CaptureFrame(frame_id=1, timestamp_ns=1))
    with pytest.raises(FrameCodecError):
        decode_capture_frame(truncated[:-2])


def test_keys():
    assert parse_key("openbene/rtr520/frame") == ("rtr520", "frame")
    assert parse_key("openbene/rtr520/unknown") is None
    assert parse_key("openbene/rtr520") is None
    assert sanitize_robot_id(" rtr 520 ") == "rtr_520"
    assert sanitize_robot_id("") == "robot"
