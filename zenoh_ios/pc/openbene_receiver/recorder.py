"""MCAP recording for OpenBene Zenoh sessions.

One MCAP file holds every stream of one or more robots:

    /openbene/<robot>/frame/meta        JSON  frame bookkeeping + pose
    /openbene/<robot>/frame/rgb         jpeg
    /openbene/<robot>/frame/depth       png
    /openbene/<robot>/frame/confidence  png
    /openbene/<robot>/video             jpeg  (legacy Android frames)
    /openbene/<robot>/<topic>           json  status/telemetry/sensors/cmd/session

The JSON sidecar next to the file carries per-channel counts for quick
inspection without an MCAP reader.
"""

from __future__ import annotations

import json
import os
import time
from collections import Counter
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from mcap.writer import Writer


@dataclass
class RecorderStats:
    messages: int = 0
    bytes: int = 0
    frames: int = 0
    legacy_frames: int = 0
    gaps: int = 0
    decode_errors: int = 0
    channels: Counter = field(default_factory=Counter)
    first_ns: int | None = None
    last_ns: int | None = None

    def note(self, topic: str, size: int, timestamp_ns: int) -> None:
        self.messages += 1
        self.bytes += size
        self.channels[topic] += 1
        if self.first_ns is None or timestamp_ns < self.first_ns:
            self.first_ns = timestamp_ns
        if self.last_ns is None or timestamp_ns > self.last_ns:
            self.last_ns = timestamp_ns

    def as_dict(self) -> dict[str, Any]:
        duration = 0.0
        if self.first_ns is not None and self.last_ns is not None:
            duration = (self.last_ns - self.first_ns) / 1e9
        return {
            "messages": self.messages,
            "bytes": self.bytes,
            "frames": self.frames,
            "legacy_frames": self.legacy_frames,
            "gaps": self.gaps,
            "decode_errors": self.decode_errors,
            "duration_s": round(duration, 3),
            "channels": dict(self.channels),
        }


class McapRecorder:
    """Writes an MCAP file plus a JSON sidecar."""

    def __init__(
        self,
        path: str | os.PathLike[str],
        *,
        library: str = "openbene_receiver/0.1.0",
        profile: str = "openbene",
        metadata: dict[str, str] | None = None,
    ) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._file = self.path.open("wb")
        self._writer = Writer(self._file)
        self._writer.start(profile=profile, library=library)
        self._schema_ids: dict[str, int] = {}
        self._channel_ids: dict[tuple[str, str], int] = {}
        self.stats = RecorderStats()
        self.started_at = datetime.now(timezone.utc)
        self.extra_metadata = dict(metadata or {})
        self._closed = False

    def _schema(self, name: str, schema: dict[str, Any] | None = None) -> int:
        if name not in self._schema_ids:
            data = json.dumps(schema or {}, sort_keys=True).encode("utf-8")
            self._schema_ids[name] = self._writer.register_schema(
                name=name, encoding="jsonschema", data=data
            )
        return self._schema_ids[name]

    def _channel(self, topic: str, encoding: str) -> int:
        key = (topic, encoding)
        if key not in self._channel_ids:
            if encoding == "json":
                schema_id = self._schema("openbene.message")
            else:
                schema_id = 0
            self._channel_ids[key] = self._writer.register_channel(
                topic=topic,
                message_encoding=encoding,
                schema_id=schema_id,
            )
        return self._channel_ids[key]

    def write(self, topic: str, data: bytes, timestamp_ns: int, encoding: str = "json") -> None:
        if self._closed:
            raise RuntimeError("recorder is closed")
        # MCAP/ROS tooling expects leading-slash topic names.
        topic = topic if topic.startswith("/") else "/" + topic
        channel_id = self._channel(topic, encoding)
        self._writer.add_message(
            channel_id=channel_id,
            log_time=timestamp_ns,
            publish_time=timestamp_ns,
            data=data,
        )
        self.stats.note(topic, len(data), timestamp_ns)

    def write_json(self, topic: str, payload: Any, timestamp_ns: int) -> None:
        data = payload if isinstance(payload, (bytes, bytearray)) else json.dumps(payload, sort_keys=True).encode("utf-8")
        self.write(topic, bytes(data), timestamp_ns, encoding="json")

    def close(self) -> dict[str, Any]:
        if self._closed:
            return self.stats.as_dict()
        self._closed = True
        finished_at = datetime.now(timezone.utc)
        summary = self.stats.as_dict()
        self._writer.add_metadata(
            name="openbene.session",
            data={
                "started_at": self.started_at.isoformat(),
                "finished_at": finished_at.isoformat(),
                "stats": json.dumps(summary, sort_keys=True),
                **self.extra_metadata,
            },
        )
        self._writer.finish()
        self._file.close()

        sidecar = self.path.with_suffix(self.path.suffix + ".meta.json")
        sidecar.write_text(
            json.dumps(
                {
                    "path": str(self.path),
                    "started_at": self.started_at.isoformat(),
                    "finished_at": finished_at.isoformat(),
                    "stats": summary,
                    **self.extra_metadata,
                },
                indent=2,
                sort_keys=True,
            ),
            encoding="utf-8",
        )
        return summary

    def __enter__(self) -> "McapRecorder":
        return self

    def __exit__(self, *_exc: object) -> None:
        self.close()


def wall_clock_ns() -> int:
    return time.time_ns()
