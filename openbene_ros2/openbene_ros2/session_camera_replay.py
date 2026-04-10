from __future__ import annotations

from ._sdk_bridge import run_sdk_bridge


def main() -> int:
    return run_sdk_bridge("openbene.session_ros2_bridge", "OpenBene session camera replay")


if __name__ == "__main__":
    raise SystemExit(main())
