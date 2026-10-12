"""Copy the shared demo map and marker sheets into the phone projects.

    python shared/tools/sync_demo_assets.py          # copy
    python shared/tools/sync_demo_assets.py --check  # verify, non zero on drift

shared/maps/demo_floor.json and shared/markers/*.png are the single source of
truth for all three implementations. The Android assets, the iOS app resources
and the JSON the iOS tests parse are generated from them, so the map can never
mean different things on different platforms.
"""

from __future__ import annotations

import argparse
import filecmp
import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHARED_MAP = ROOT / "shared" / "maps" / "demo_floor.json"
SHARED_MARKERS = ROOT / "shared" / "markers"

MAP_TARGETS = [
    ROOT / "Android" / "app" / "src" / "main" / "assets" / "demo_floor.json",
    ROOT / "IOS" / "OpenBotAnchorNav" / "Resources" / "demo_floor.json",
    ROOT / "IOS" / "OpenBotNavKit" / "Tests" / "OpenBotNavKitTests" / "Resources" / "demo_floor.json",
]

MARKER_DIRS = [
    ROOT / "Android" / "app" / "src" / "main" / "assets" / "markers",
    ROOT / "IOS" / "OpenBotAnchorNav" / "Resources" / "markers",
]


def marker_files() -> list:
    return sorted(SHARED_MARKERS.glob("*.png"))


def pairs() -> list:
    """(source, target) for everything that has to stay in step."""

    out = [(SHARED_MAP, target) for target in MAP_TARGETS]
    for target_dir in MARKER_DIRS:
        for source in marker_files():
            out.append((source, target_dir / source.name))
    return out


def same(source: Path, target: Path) -> bool:
    if not target.exists():
        return False
    return filecmp.cmp(source, target, shallow=False)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Sync shared demo assets into the apps")
    parser.add_argument("--check", action="store_true", help="only report differences")
    args = parser.parse_args(argv)

    stale = []
    for source, target in pairs():
        if same(source, target):
            continue
        stale.append(target)
        if not args.check:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)

    for target in stale:
        verb = "out of date" if args.check else "updated"
        print(verb + ": " + os.path.relpath(target, ROOT))
    if not stale:
        print("all demo assets are in sync")
    if args.check and stale:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
