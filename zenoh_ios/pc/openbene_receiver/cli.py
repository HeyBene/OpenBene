"""Command line entry point: openbene-recv."""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from .recorder import RecordingController
from .receiver import OpenBeneReceiver
from .viewer import LiveViewer


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="openbene-recv",
        description="Receive OpenBene Zenoh streams, optionally preview and record them.",
    )
    parser.add_argument(
        "--endpoint",
        default="tcp/127.0.0.1:7447",
        help="Zenoh endpoint to connect to (default: tcp/127.0.0.1:7447)",
    )
    parser.add_argument("--key", default="openbene/**", help="Key expression to subscribe to")
    parser.add_argument(
        "--mode",
        choices=("client", "peer"),
        default="client",
        help="Session mode; use peer when no router is running",
    )
    parser.add_argument(
        "--listen",
        default=None,
        help="Optional listen endpoint, e.g. tcp/0.0.0.0:7447 (peer mode)",
    )
    parser.add_argument(
        "--record",
        nargs="?",
        const="",
        default=None,
        metavar="PATH",
        help="Start recording immediately (optional explicit path)",
    )
    parser.add_argument(
        "--record-dir",
        default="runs",
        help="Directory used by the viewer's 开始录制 button (default: runs)",
    )
    parser.add_argument("--view", action="store_true", help="Serve the live preview page")
    parser.add_argument("--view-port", type=int, default=8080, help="Preview HTTP port (default: 8080)")
    parser.add_argument("--view-host", default="127.0.0.1", help="Preview bind address (default: 127.0.0.1)")
    parser.add_argument("--robot", default="rtr520", help="Robot ID used for outgoing commands")
    parser.add_argument(
        "--duration",
        type=float,
        default=None,
        help="Stop after N seconds (default: run until Ctrl+C)",
    )
    parser.add_argument("--json", action="store_true", help="Echo JSON samples to stdout")
    parser.add_argument(
        "--stats",
        action="store_true",
        help="Print received fps, gaps and enabled planes every 2 seconds",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    recording = RecordingController(Path(args.record_dir))

    viewer = None
    if args.view:
        viewer = LiveViewer(args.view_host, args.view_port, recording=recording)
        try:
            url = viewer.start()
        except OSError as error:
            print(f"cannot start live view on {args.view_host}:{args.view_port}: {error}", file=sys.stderr)
            return 1
        print(f"live view : {url}")

    if args.record is not None:
        path = recording.start(args.record or None)
        print(f"recording : {path}")
    elif args.view:
        print("recording : off (press 开始录制 in the viewer)")

    receiver = OpenBeneReceiver(
        endpoint=args.endpoint,
        key=args.key,
        mode=args.mode,
        listen=args.listen,
        recording=recording,
        viewer=viewer,
        command_robot=args.robot,
        echo_json=args.json,
    )

    if viewer:
        # The viewer publishes through the same session the receiver already
        # owns, so control and recording share one router connection.
        viewer.command_publisher = receiver.send_drive

    print(f"listening on {args.key} via {args.endpoint} ({args.mode})")

    report_state = {"frames": 0, "bytes": 0, "at": time.time()}

    def report() -> None:
        stats = receiver.stats
        meta = receiver.last_meta or {}
        info = meta.get("metadata", {}) if isinstance(meta, dict) else {}
        planes = info.get("enabledPlanes")
        # Instantaneous rate over the last interval, matching the web console.
        now = time.time()
        elapsed = max(1e-3, now - report_state["at"])
        fps = (stats.frames - report_state["frames"]) / elapsed
        mbps = (stats.bytes - report_state["bytes"]) / elapsed / 1e6
        report_state.update(frames=stats.frames, bytes=stats.bytes, at=now)
        print(
            f"[stats] {fps:5.1f} fps  frames={stats.frames}  "
            f"gaps={stats.gaps}  errors={stats.decode_errors}  "
            f"mbps={mbps:5.2f}  "
            f"planes={','.join(planes) if planes else '-'}"
        )

    try:
        stats = receiver.run(duration=args.duration, on_tick=report if args.stats else None)
    finally:
        summary = recording.stop()
        if viewer:
            viewer.stop()

    print(json.dumps(stats.as_dict(), indent=2, sort_keys=True))
    if summary:
        print(f"wrote {summary['messages']} messages, {summary['frames']} frames")
    return 0


if __name__ == "__main__":
    sys.exit(main())
