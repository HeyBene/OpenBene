from __future__ import annotations

import os
import sys


def _check_import(module_name: str) -> tuple[bool, str]:
    try:
        __import__(module_name)
        return True, "ok"
    except Exception as exc:
        return False, str(exc)


def main() -> int:
    print("OpenBene ROS2 Doctor")
    print("====================")

    ros_distro = os.environ.get("ROS_DISTRO", "")
    if ros_distro:
        print(f"[OK] ROS_DISTRO={ros_distro}")
    else:
        print("[WARN] ROS_DISTRO is not set.")
        print("       Run: source /opt/ros/humble/setup.bash")

    checks = [
        ("rclpy", "ROS 2 Python client library"),
        ("geometry_msgs", "ROS 2 message package"),
        ("openbene", "OpenBene Python SDK"),
        ("PIL", "Pillow image library"),
        ("openbene.session_ros2_bridge", "OpenBene camera-topic ROS2 bridge"),
    ]

    results = {}

    for module_name, label in checks:
        ok, detail = _check_import(module_name)
        results[module_name] = ok
        prefix = "[OK]" if ok else "[WARN]"
        print(f"{prefix} {label}: {module_name}")
        if not ok:
            print(f"       Import detail: {detail}")

    if not results.get("openbene", False):
        print("Hint:")
        print("  If openbene import failed, install the local SDK with:")
        print("  python3 -m pip install -e /path/to/OpenBene/openbene_sdk")
    elif not results.get("openbene.session_ros2_bridge", False):
        print("Hint:")
        print("  If the camera bridge import failed after a recent git pull, refresh the SDK install with:")
        print("  python3 -m pip install -e /path/to/OpenBene/openbene_sdk")
        print("  If the error mentions PIL, you can also run:")
        print("  python3 -m pip install pillow")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
