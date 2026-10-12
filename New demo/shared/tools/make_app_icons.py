"""Generate the launcher icons for both demo apps from one drawing.

    python shared/tools/make_app_icons.py

Android icons land in Android/app/src/main/res/mipmap-*/ic_launcher.png and the
iOS icon in IOS/OpenBotAnchorNav/Assets.xcassets/AppIcon.appiconset.
"""

from __future__ import annotations

import os
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]

NAVY = (16, 35, 59, 255)
TEAL = (20, 184, 166, 255)
WHITE = (247, 250, 252, 255)

ANDROID_SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}


def draw_icon(px: int) -> Image.Image:
    """A route on a navy tile: the demo in one picture."""

    scale = 4
    size = px * scale
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.18), fill=NAVY)

    unit = size / 100.0
    route = [
        (24 * unit, 78 * unit),
        (24 * unit, 46 * unit),
        (50 * unit, 46 * unit),
        (50 * unit, 26 * unit),
    ]
    draw.line(route, fill=WHITE, width=max(1, int(unit * 7)), joint="curve")
    for point in ((24 * unit, 78 * unit), (50 * unit, 46 * unit)):
        radius = unit * 7
        draw.ellipse(
            [point[0] - radius, point[1] - radius, point[0] + radius, point[1] + radius],
            fill=TEAL,
        )
    draw.polygon(
        [(50 * unit, 12 * unit), (41 * unit, 30 * unit), (59 * unit, 30 * unit)],
        fill=WHITE,
    )
    return image.resize((px, px), Image.LANCZOS)


def write_android() -> list:
    written = []
    for folder, px in ANDROID_SIZES.items():
        target_dir = ROOT / "Android" / "app" / "src" / "main" / "res" / ("mipmap-" + folder)
        target_dir.mkdir(parents=True, exist_ok=True)
        target = target_dir / "ic_launcher.png"
        draw_icon(px).save(target)
        written.append(target)
    return written


def write_ios() -> list:
    appicon = ROOT / "IOS" / "OpenBotAnchorNav" / "Assets.xcassets" / "AppIcon.appiconset"
    appicon.mkdir(parents=True, exist_ok=True)
    target = appicon / "AppIcon-1024.png"
    draw_icon(1024).save(target)
    return [target]


def main() -> int:
    for path in write_android() + write_ios():
        print("wrote " + os.path.relpath(path, ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
