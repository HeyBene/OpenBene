"""Wire protocol shared with the iOS SDK and the Android prototype.

Keys:  openbene/{robot_id}/{topic}

ZFRM (Android-era video frame, little endian):
    magic u32 | version u16 | flags u16 | timestamp_ns u64 | frame_id u32 | JPEG

ZPKD (iOS capture frame, little endian):
    magic u32 | version u16 | flags u16 | timestamp_ns u64 | frame_id u32 |
    section_count u32 | (type u32, length u32, payload)*
"""

from __future__ import annotations

import json
import struct
from dataclasses import dataclass, field
from typing import Any, Mapping

PROTOCOL_VERSION = 1
VIDEO_MAGIC = 0x4D52465A  # b"ZFRM" little endian
PACKET_MAGIC = 0x444B505A  # b"ZPKD" little endian
VIDEO_HEADER_BYTES = 20
PACKET_HEADER_BYTES = 24
MAX_SECTION_BYTES = 64 * 1024 * 1024

TOPICS = ("cmd", "status", "sensors", "telemetry", "video", "frame", "session")

SECTION_RGB = 1
SECTION_DEPTH = 2
SECTION_CONFIDENCE = 3
SECTION_POSE = 4
SECTION_METADATA = 5


class FrameCodecError(ValueError):
    """Raised for malformed or truncated binary frames."""


def sanitize_robot_id(raw: str) -> str:
    cleaned = "".join(
        character if character.isascii() and (character.isalnum() or character in "_-") else "_"
        for character in raw.strip()
    )
    return cleaned or "robot"


def parse_key(key: str) -> tuple[str, str] | None:
    """Returns ``(robot_id, topic)`` for an OpenBene key, else ``None``."""
    parts = [part for part in key.split("/") if part]
    if len(parts) != 3 or parts[0] != "openbene" or parts[2] not in TOPICS:
        return None
    return parts[1], parts[2]


@dataclass(frozen=True)
class FrameMetadata:
    width: int = 0
    height: int = 0
    depth_width: int = 0
    depth_height: int = 0
    fx: float = 0.0
    fy: float = 0.0
    cx: float = 0.0
    cy: float = 0.0
    tracking_state: str = "unknown"
    depth_source: str = "none"
    confidence_width: int = 0
    confidence_height: int = 0
    enabled_planes: tuple[str, ...] | None = None

    @classmethod
    def from_json(cls, raw: bytes | str) -> "FrameMetadata":
        if isinstance(raw, bytes):
            raw = raw.decode("utf-8")
        data = json.loads(raw)
        if not isinstance(data, Mapping):
            raise FrameCodecError("metadata must be a JSON object")
        return cls(
            width=int(data.get("width", 0)),
            height=int(data.get("height", 0)),
            depth_width=int(data.get("depthWidth", 0)),
            depth_height=int(data.get("depthHeight", 0)),
            fx=float(data.get("fx", 0.0)),
            fy=float(data.get("fy", 0.0)),
            cx=float(data.get("cx", 0.0)),
            cy=float(data.get("cy", 0.0)),
            tracking_state=str(data.get("trackingState", "unknown")),
            depth_source=str(data.get("depthSource", "none")),
            confidence_width=int(data.get("confidenceWidth", 0)),
            confidence_height=int(data.get("confidenceHeight", 0)),
            enabled_planes=(
                tuple(str(item) for item in data["enabledPlanes"])
                if isinstance(data.get("enabledPlanes"), list)
                else None
            ),
        )

    def as_dict(self) -> dict[str, Any]:
        return {
            "width": self.width,
            "height": self.height,
            "depthWidth": self.depth_width,
            "depthHeight": self.depth_height,
            "fx": self.fx,
            "fy": self.fy,
            "cx": self.cx,
            "cy": self.cy,
            "trackingState": self.tracking_state,
            "depthSource": self.depth_source,
            "confidenceWidth": self.confidence_width,
            "confidenceHeight": self.confidence_height,
            **(
                {"enabledPlanes": list(self.enabled_planes)}
                if self.enabled_planes is not None
                else {}
            ),
        }


@dataclass(frozen=True)
class CaptureFrame:
    frame_id: int
    timestamp_ns: int
    rgb_jpeg: bytes | None = None
    depth_png: bytes | None = None
    confidence_png: bytes | None = None
    pose: tuple[float, ...] | None = None
    metadata: FrameMetadata = field(default_factory=FrameMetadata)
    flags: int = 0


def decode_legacy_video(payload: bytes) -> tuple[int, int, bytes]:
    """Returns ``(frame_id, timestamp_ns, jpeg)`` for a ZFRM payload."""
    if len(payload) < VIDEO_HEADER_BYTES:
        raise FrameCodecError(f"truncated ZFRM: {len(payload)} bytes")
    magic, version, _flags, timestamp_ns, frame_id = struct.unpack_from("<IHHQI", payload, 0)
    if magic != VIDEO_MAGIC:
        raise FrameCodecError(f"bad ZFRM magic 0x{magic:08x}")
    if version != PROTOCOL_VERSION:
        raise FrameCodecError(f"unsupported ZFRM version {version}")
    return frame_id, timestamp_ns, payload[VIDEO_HEADER_BYTES:]


def decode_capture_frame(payload: bytes) -> CaptureFrame:
    if len(payload) < PACKET_HEADER_BYTES:
        raise FrameCodecError(f"truncated ZPKD: {len(payload)} bytes")
    magic, version, flags, timestamp_ns, frame_id, section_count = struct.unpack_from(
        "<IHHQII", payload, 0
    )
    if magic != PACKET_MAGIC:
        raise FrameCodecError(f"bad ZPKD magic 0x{magic:08x}")
    if version != PROTOCOL_VERSION:
        raise FrameCodecError(f"unsupported ZPKD version {version}")

    offset = PACKET_HEADER_BYTES
    rgb = depth = confidence = None
    pose: tuple[float, ...] | None = None
    metadata = FrameMetadata()

    for _ in range(section_count):
        if offset + 8 > len(payload):
            raise FrameCodecError("truncated ZPKD section header")
        section_type, length = struct.unpack_from("<II", payload, offset)
        offset += 8
        if length > MAX_SECTION_BYTES or offset + length > len(payload):
            raise FrameCodecError(f"malformed section {section_type} with length {length}")
        body = payload[offset : offset + length]
        offset += length

        if section_type == SECTION_RGB:
            rgb = body
        elif section_type == SECTION_DEPTH:
            depth = body
        elif section_type == SECTION_CONFIDENCE:
            confidence = body
        elif section_type == SECTION_POSE:
            if length != 64:
                raise FrameCodecError(f"pose section must be 64 bytes, got {length}")
            pose = struct.unpack("<16f", body)
        elif section_type == SECTION_METADATA:
            metadata = FrameMetadata.from_json(body)
        # Unknown sections are skipped for forward compatibility.

    return CaptureFrame(
        frame_id=frame_id,
        timestamp_ns=timestamp_ns,
        rgb_jpeg=rgb,
        depth_png=depth,
        confidence_png=confidence,
        pose=pose,
        metadata=metadata,
        flags=flags,
    )


def encode_legacy_video(jpeg: bytes, frame_id: int, timestamp_ns: int, flags: int = 0) -> bytes:
    return struct.pack(
        "<IHHQI", VIDEO_MAGIC, PROTOCOL_VERSION, flags, timestamp_ns, frame_id
    ) + jpeg


def encode_capture_frame(frame: CaptureFrame) -> bytes:
    sections: list[tuple[int, bytes]] = []
    if frame.rgb_jpeg is not None:
        sections.append((SECTION_RGB, frame.rgb_jpeg))
    if frame.depth_png is not None:
        sections.append((SECTION_DEPTH, frame.depth_png))
    if frame.confidence_png is not None:
        sections.append((SECTION_CONFIDENCE, frame.confidence_png))
    if frame.pose is not None:
        sections.append((SECTION_POSE, struct.pack("<16f", *frame.pose)))
    sections.append(
        (
            SECTION_METADATA,
            json.dumps(frame.metadata.as_dict(), sort_keys=True).encode("utf-8"),
        )
    )

    header = struct.pack(
        "<IHHQII",
        PACKET_MAGIC,
        PROTOCOL_VERSION,
        frame.flags,
        frame.timestamp_ns,
        frame.frame_id,
        len(sections),
    )
    body = b"".join(struct.pack("<II", kind, len(data)) + data for kind, data in sections)
    return header + body
