"""Command line entry point: openbene-recv."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .recorder import McapRecorder
from .receiver import OpenBeneReceiver


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="openbene-recv",
        description="Receive OpenBene Zenoh streams and optionally record them to MCAP.",
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
        default=None,
        metavar="PATH",
        help="Write an MCAP file (plus a .meta.json sidecar)",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=None,
        help="Stop after N seconds (default: run until Ctrl+C)",
    )
    parser.add_argument("--json", action="store_true", help="Echo JSON samples to stdout")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    recorder = None
    if args.record:
        recorder = McapRecorder(
            Path(args.record),
            metadata={
                "endpoint": args.endpoint,
                "key": args.key,
                "mode": args.mode,
            },
        )

    receiver = OpenBeneReceiver(
        endpoint=args.endpoint,
        key=args.key,
        mode=args.mode,
        listen=args.listen,
        recorder=recorder,
        echo_json=args.json,
    )

    print(f"listening on {args.key} via {args.endpoint} ({args.mode})")
    if recorder:
        print(f"recording to {recorder.path}")

    try:
        stats = receiver.run(duration=args.duration)
    finally:
        summary = recorder.close() if recorder else None

    print(json.dumps(stats.as_dict(), indent=2, sort_keys=True))
    if summary:
        print(f"wrote {summary['messages']} messages, {summary['frames']} frames")
    return 0


if __name__ == "__main__":
    sys.exit(main())
