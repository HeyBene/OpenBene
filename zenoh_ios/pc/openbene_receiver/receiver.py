"""Zenoh subscriber that decodes OpenBene samples and records them to MCAP."""

from __future__ import annotations

import json
import threading
import time
from collections import Counter
from dataclasses import dataclass, field
from typing import Any, Callable

from .protocol import (
    FrameCodecError,
    decode_capture_frame,
    decode_legacy_video,
    parse_key,
)
from .recorder import RecordingController, wall_clock_ns

WALL_CLOCK_FLOOR_NS = 1_000_000_000_000_000  # below this the source clock is monotonic


@dataclass
class ReceiverStats:
    samples: int = 0
    bytes: int = 0
    frames: int = 0
    legacy_frames: int = 0
    gaps: int = 0
    decode_errors: int = 0
    ignored: int = 0
    topics: Counter = field(default_factory=Counter)
    robots: Counter = field(default_factory=Counter)
    last_frame_id: dict[str, int] = field(default_factory=dict)
    started_at: float = field(default_factory=time.time)

    @property
    def fps(self) -> float:
        elapsed = max(1e-3, time.time() - self.started_at)
        return self.frames / elapsed

    @property
    def primary_robot(self) -> str | None:
        return self.robots.most_common(1)[0][0] if self.robots else None

    def as_dict(self) -> dict[str, Any]:
        return {
            "samples": self.samples,
            "bytes": self.bytes,
            "frames": self.frames,
            "legacy_frames": self.legacy_frames,
            "gaps": self.gaps,
            "decode_errors": self.decode_errors,
            "ignored": self.ignored,
            "topics": dict(self.topics),
            "robot": self.primary_robot,
            "elapsed_s": round(time.time() - self.started_at, 3),
        }


class OpenBeneReceiver:
    """Decodes openbene/** samples; optionally records them.

    handle_sample is transport independent and is what the tests drive.
    run() opens a zenoh session and blocks for the requested duration.
    """

    def __init__(
        self,
        endpoint: str = "tcp/127.0.0.1:7447",
        *,
        key: str = "openbene/**",
        mode: str = "client",
        listen: str | None = None,
        recording: RecordingController | None = None,
        viewer: Any | None = None,
        command_robot: str = "rtr520",
        on_record: Callable[[str, int], None] | None = None,
        echo_json: bool = False,
    ) -> None:
        self.endpoint = endpoint
        self.key = key
        self.mode = mode
        self.listen = listen
        self.recording = recording
        self.viewer = viewer
        self.command_robot = command_robot
        self._command_lock = threading.Lock()
        self._command_seq = 0
        self.on_record = on_record
        self.echo_json = echo_json
        self.stats = ReceiverStats()
        self.last_meta: dict[str, Any] = {}
        self._session: Any = None
        self._subscriber: Any = None
        self._frame_clock_offset: int | None = None

    # -- decoding ---------------------------------------------------------

    def handle_sample(self, key: str, payload: bytes, received_ns: int | None = None) -> None:
        self.stats.samples += 1
        self.stats.bytes += len(payload)
        self.stats.topics[key] += 1

        parsed = parse_key(key)
        if parsed is None:
            self.stats.ignored += 1
            self._push_stats()
            return
        robot_id, topic = parsed
        self.stats.robots[robot_id] += 1
        received_ns = received_ns or wall_clock_ns()

        try:
            if topic == "frame":
                frame = decode_capture_frame(payload)
                self._record_frame(key, robot_id, frame, received_ns)
            elif topic == "video":
                _frame_id, timestamp_ns, jpeg = decode_legacy_video(payload)
                self.stats.legacy_frames += 1
                log_time = self._log_time(timestamp_ns, received_ns)
                if self.recording:
                    self.recording.write(key, jpeg, log_time, encoding="jpeg")
                    self.recording.note_legacy_frame()
                if self.viewer:
                    self.viewer.update_frame(
                        {"frame_id": _frame_id, "metadata": {"width": 0, "height": 0}},
                        jpeg,
                        None,
                        None,
                    )
                self._after_write(key, len(jpeg))
            else:
                document = json.loads(payload.decode("utf-8"))
                if topic == "cmd" and self.viewer:
                    self.viewer.update_command(document)
                if topic == "sensors" and self.viewer:
                    self.viewer.update_sensors(document)
                if self.echo_json:
                    print(f"[{key}] {json.dumps(document, sort_keys=True)}")
                if self.recording:
                    self.recording.write_json(key, payload, received_ns)
                self._after_write(key, len(payload))
        except (FrameCodecError, ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            self.stats.decode_errors += 1
            print(f"[decode-error] {key}: {error}")
        finally:
            self._push_stats()

    def _record_frame(self, key: str, robot_id: str, frame: Any, received_ns: int) -> None:
        previous = self.stats.last_frame_id.get(robot_id)
        if previous is not None and frame.frame_id > previous + 1:
            self.stats.gaps += frame.frame_id - previous - 1
        self.stats.last_frame_id[robot_id] = frame.frame_id
        self.stats.frames += 1

        log_time = self._log_time(frame.timestamp_ns, received_ns)
        meta = {
            "frame_id": frame.frame_id,
            "source_timestamp_ns": frame.timestamp_ns,
            "received_timestamp_ns": received_ns,
            "flags": frame.flags,
            "metadata": frame.metadata.as_dict(),
            "pose": list(frame.pose) if frame.pose else None,
            "sizes": {
                "rgb": len(frame.rgb_jpeg or b""),
                "depth": len(frame.depth_png or b""),
                "confidence": len(frame.confidence_png or b""),
            },
        }
        self.last_meta = meta

        if self.recording:
            self.recording.write_json(f"{key}/meta", meta, log_time)
            if frame.rgb_jpeg is not None:
                self.recording.write(f"{key}/rgb", frame.rgb_jpeg, log_time, encoding="jpeg")
            if frame.depth_png is not None:
                self.recording.write(f"{key}/depth", frame.depth_png, log_time, encoding="png")
            if frame.confidence_png is not None:
                self.recording.write(f"{key}/confidence", frame.confidence_png, log_time, encoding="png")
            self.recording.note_frame()

        if self.viewer:
            self.viewer.update_frame(meta, frame.rgb_jpeg, frame.depth_png, frame.confidence_png)

        self._after_write(key, len(frame.rgb_jpeg or b""))

    def _log_time(self, source_ns: int, received_ns: int) -> int:
        """Keep MCAP timestamps in wall-clock time.

        iOS monotonic clocks (DispatchTime) start near zero, so map them onto
        the receive wall clock only when the source value is clearly not a Unix
        timestamp. Real wall-clock nanoseconds pass through untouched.
        """
        if source_ns >= WALL_CLOCK_FLOOR_NS:
            return source_ns
        if self._frame_clock_offset is None:
            self._frame_clock_offset = received_ns - source_ns
        return source_ns + self._frame_clock_offset

    def _after_write(self, key: str, size: int) -> None:
        if self.on_record:
            self.on_record(key, size)

    def _push_stats(self) -> None:
        if self.viewer:
            self.viewer.update_stats(self.stats.as_dict())

    # -- control (PC -> phone) -------------------------------------------

    def send_drive(self, left: float, right: float) -> None:
        """Publishes a drive command for the phone to apply over BLE."""
        if self._session is None:
            raise RuntimeError("zenoh session is not open")
        robot = self.stats.primary_robot or self.command_robot
        now = int(time.time() * 1000)
        with self._command_lock:
            self._command_seq += 1
            sequence = self._command_seq
        payload = {
            "version": 1,
            "cmd": "drive",
            "val": [round(max(-1.0, min(1.0, float(left))), 3),
                    round(max(-1.0, min(1.0, float(right))), 3)],
            "seq": sequence,
            "sent_at": now,
            "ttl_ms": 250,
        }
        self._session.put(
            f"openbene/{robot}/cmd",
            json.dumps(payload, sort_keys=True).encode("utf-8"),
        )

    # -- zenoh transport --------------------------------------------------

    def open(self) -> None:
        import zenoh  # imported lazily so decoding tests need no native library

        config = zenoh.Config()
        config.insert_json5("mode", json.dumps("peer" if self.mode == "peer" else "client"))
        if self.listen:
            config.insert_json5("listen/endpoints", json.dumps([self.listen]))
        if self.endpoint:
            config.insert_json5("connect/endpoints", json.dumps([self.endpoint]))
        self._session = zenoh.open(config)
        self._subscriber = self._session.declare_subscriber(self.key, self._on_sample)

    def _on_sample(self, sample: Any) -> None:
        payload = getattr(sample, "payload", b"")
        data = payload.to_bytes() if hasattr(payload, "to_bytes") else bytes(payload)
        key = str(getattr(sample, "key_expr", getattr(sample, "keyexpr", "")))
        self.handle_sample(key, data)

    def run(
        self,
        duration: float | None = None,
        on_tick: Callable[[], None] | None = None,
    ) -> ReceiverStats:
        self.open()
        next_tick = time.time() + 2
        try:
            deadline = None if duration is None else time.time() + duration
            while deadline is None or time.time() < deadline:
                time.sleep(0.2)
                if on_tick is not None and time.time() >= next_tick:
                    next_tick = time.time() + 2
                    on_tick()
        except KeyboardInterrupt:
            pass
        finally:
            self.close()
        return self.stats

    def close(self) -> None:
        if self._subscriber is not None:
            try:
                self._subscriber.undeclare()
            except Exception:
                pass
            self._subscriber = None
        if self._session is not None:
            try:
                self._session.close()
            except Exception:
                pass
            self._session = None
