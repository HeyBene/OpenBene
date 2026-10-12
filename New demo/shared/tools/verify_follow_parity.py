"""Static parity check for the three follow controller ports.

    python shared/tools/verify_follow_parity.py

There is no Kotlin or Swift compiler on the development machine, so this script
compares the numbers and the user visible strings of

    shared/navcore/openbene_nav/follow.py
    Android/app/src/main/java/com/openbene/anchornav/nav/FollowController.kt
    IOS/OpenBotNavKit/Sources/OpenBotNavKit/Nav/FollowController.swift

by reading them as text. It cannot prove that the ports compile or behave the
same; it does catch the failure that hand written ports actually have, which is
a constant that was tuned in one file and forgotten in the others.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PYTHON = ROOT / "shared" / "navcore" / "openbene_nav" / "follow.py"
KOTLIN = (
    ROOT
    / "Android"
    / "app"
    / "src"
    / "main"
    / "java"
    / "com"
    / "openbene"
    / "anchornav"
    / "nav"
    / "FollowController.kt"
)
SWIFT = (
    ROOT
    / "IOS"
    / "OpenBotNavKit"
    / "Sources"
    / "OpenBotNavKit"
    / "Nav"
    / "FollowController.swift"
)

# snake_case name in follow.py -> camelCase name in the two native ports.
GAINS = {
    "target_height": "targetHeight",
    "height_deadband": "heightDeadband",
    "centre_deadband": "centreDeadband",
    "turn_speed": "turnSpeed",
    "cruise_speed": "cruiseSpeed",
    "steer_gain": "steerGain",
    "lost_timeout_s": "lostTimeoutS",
    "obstacle_stop_cm": "obstacleStopCm",
}

# The Android preset, used because ML Kit reports a face box instead of a person
# box. Both native ports have to agree with this script.
FACE_PRESET = {"targetHeight": 0.16, "heightDeadband": 0.30}

PHRASES = (
    "obstacle at",
    "target lost",
    "searching for the target",
    "turning right",
    "turning left",
    "closing in",
    "too close, holding",
    "holding distance",
)

NUMBER = r"(-?\d+(?:\.\d+)?)"


def gain(text: str, name: str):
    match = re.search(re.escape(name) + r"\s*:\s*\w+\s*=\s*" + NUMBER, text)
    return None if match is None else float(match.group(1))


def preset(text: str, name: str):
    match = re.search(re.escape(name) + r"\s*=\s*FollowConfig\((.*?)\)", text)
    if match is None:
        return None
    return {
        key: float(value)
        for key, value in re.findall(r"(\w+)\s*[:=]\s*" + NUMBER, match.group(1))
    }


def main() -> int:
    python_text = PYTHON.read_text(encoding="utf-8")
    kotlin_text = KOTLIN.read_text(encoding="utf-8")
    swift_text = SWIFT.read_text(encoding="utf-8")

    problems = []
    reference = {}
    for snake, camel in GAINS.items():
        value = gain(python_text, snake)
        if value is None:
            problems.append("follow.py: " + snake + " is missing")
            continue
        reference[camel] = value

    for label, text in (
        ("FollowController.kt", kotlin_text),
        ("FollowController.swift", swift_text),
    ):
        for camel, expected in reference.items():
            value = gain(text, camel)
            if value is None:
                problems.append(label + ": " + camel + " is missing")
            elif abs(value - expected) > 1e-9:
                problems.append(
                    label + ": " + camel + " is " + str(value)
                    + ", follow.py has " + str(expected)
                )

    for label, text, name in (
        ("FollowController.kt", kotlin_text, "FACE_BOX"),
        ("FollowController.swift", swift_text, "faceBox"),
    ):
        found = preset(text, name)
        if found is None:
            problems.append(label + ": the " + name + " preset is missing")
            continue
        for key, expected in FACE_PRESET.items():
            if key not in found:
                problems.append(label + ": " + name + " does not set " + key)
            elif abs(found[key] - expected) > 1e-9:
                problems.append(
                    label + ": " + name + " sets " + key + " to "
                    + str(found[key]) + ", expected " + str(expected)
                )

    for phrase in PHRASES:
        for label, text in (
            ("follow.py", python_text),
            ("FollowController.kt", kotlin_text),
            ("FollowController.swift", swift_text),
        ):
            if phrase not in text:
                problems.append(label + ": action text " + repr(phrase) + " is missing")

    for label, text, pattern in (
        ("FollowController.kt", kotlin_text, r"BOX_TTL_S\s*(?::\s*\w+\s*)?=\s*" + NUMBER),
        ("FollowController.swift", swift_text, r"boxTtlS\s*=\s*" + NUMBER),
    ):
        match = re.search(pattern, text)
        if match is None:
            problems.append(label + ": the box time to live is missing")
        elif abs(float(match.group(1)) - 0.6) > 1e-9:
            problems.append(
                label + ": the box time to live is " + match.group(1) + ", expected 0.6"
            )

    print(
        "compared {} gains, {} action strings and the face preset across three ports".format(
            len(GAINS), len(PHRASES)
        )
    )
    if problems:
        for problem in problems:
            print("problem: " + problem)
        return 1
    print("result: ok, the three follow controllers agree")
    return 0


if __name__ == "__main__":
    sys.exit(main())
