"""Generate the printable marker sheets for a demo map.

Every marker becomes one square PNG. Print it at the physical size recorded in
the map (marker.size_m) and tape it to the floor with the printed arrow pointing
away from the approaching robot: the arrow shows the marker image +y axis, which
is the direction the map file records in marker.pose.yaw_deg.

    python shared/tools/make_markers.py
    python shared/tools/make_markers.py --map shared/maps/demo_floor.json --out shared/markers
"""

from __future__ import annotations

import argparse
import io
import json
import os
from pathlib import Path

import segno
from PIL import Image, ImageDraw, ImageFont

try:  # Pillow >= 9.2
    RESAMPLE = Image.Resampling.LANCZOS
except AttributeError:  # pragma: no cover - older Pillow
    RESAMPLE = Image.LANCZOS

CANVAS_PX = 1200
BORDER_PX = 26
QR_TARGET_PX = 720
FIDUCIAL_PX = 130
FIDUCIAL_MARGIN_PX = 40


def load_font(size_px: int):
    for name in ("arialbd.ttf", "arial.ttf", "DejaVuSans-Bold.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size_px)
        except OSError:
            continue
    return ImageFont.load_default()


def make_qr(payload: str, target_px: int) -> Image.Image:
    qr = segno.make(payload, error="m")
    width, _ = qr.symbol_size(scale=1, border=2)
    scale = max(1, target_px // width)
    buffer = io.BytesIO()
    qr.save(buffer, kind="png", scale=scale, border=2, dark="black", light="white")
    buffer.seek(0)
    image = Image.open(buffer).convert("RGB")
    return image.resize((target_px, target_px), RESAMPLE)


def make_marker_image(marker: dict, canvas_px: int = CANVAS_PX) -> Image.Image:
    canvas = Image.new("RGB", (canvas_px, canvas_px), "white")
    draw = ImageDraw.Draw(canvas)

    draw.rectangle(
        [BORDER_PX // 2, BORDER_PX // 2, canvas_px - BORDER_PX // 2, canvas_px - BORDER_PX // 2],
        outline="black",
        width=BORDER_PX,
    )

    # Corner fiducials give the AR image tracker strong, stable features.
    for corner_x in (0, 1):
        for corner_y in (0, 1):
            if corner_x == 1 and corner_y == 1:
                continue
            left = FIDUCIAL_MARGIN_PX + corner_x * (canvas_px - 2 * FIDUCIAL_MARGIN_PX - FIDUCIAL_PX)
            top = FIDUCIAL_MARGIN_PX + corner_y * (canvas_px - 2 * FIDUCIAL_MARGIN_PX - FIDUCIAL_PX)
            draw.rectangle([left, top, left + FIDUCIAL_PX, top + FIDUCIAL_PX], fill="black")
            inner = FIDUCIAL_PX // 3
            draw.rectangle(
                [left + inner, top + inner, left + 2 * inner, top + 2 * inner],
                fill="white",
            )

    qr_image = make_qr(marker["payload"], QR_TARGET_PX)
    qr_left = (canvas_px - QR_TARGET_PX) // 2
    qr_top = (canvas_px - QR_TARGET_PX) // 2 - 20
    canvas.paste(qr_image, (qr_left, qr_top))

    # The arrow marks the marker image +y axis: place it pointing away from the robot.
    arrow_top = BORDER_PX + 30
    arrow_center = canvas_px // 2
    draw.polygon(
        [
            (arrow_center, arrow_top),
            (arrow_center - 60, arrow_top + 90),
            (arrow_center + 60, arrow_top + 90),
        ],
        fill="black",
    )
    draw.rectangle(
        [arrow_center - 18, arrow_top + 90, arrow_center + 18, arrow_top + 170],
        fill="black",
    )

    label_font = load_font(46)
    small_font = load_font(30)
    label = marker.get("id", "marker")
    size_m = float(marker.get("size_m", 0.2))
    caption = "{}   {:.0f} mm".format(label, size_m * 1000.0)
    text_width = draw.textlength(caption, font=label_font)
    draw.text(((canvas_px - text_width) / 2, canvas_px - 150), caption, fill="black", font=label_font)
    hint = marker["payload"]
    hint_width = draw.textlength(hint, font=small_font)
    draw.text(((canvas_px - hint_width) / 2, canvas_px - 92), hint, fill="black", font=small_font)
    return canvas


def generate(map_path: str | Path, out_dir: str | Path) -> list:
    raw = json.loads(Path(map_path).read_text(encoding="utf-8"))
    out_path = Path(out_dir)
    out_path.mkdir(parents=True, exist_ok=True)
    written = []
    for marker in raw.get("markers", []):
        image = make_marker_image(marker)
        target = out_path / (marker.get("ar_image", marker["id"]) + ".png")
        image.save(target)
        written.append(target)
    return written


def main(argv=None) -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="Generate printable marker sheets")
    parser.add_argument("--map", default=str(root / "maps" / "demo_floor.json"))
    parser.add_argument("--out", default=str(root / "markers"))
    args = parser.parse_args(argv)

    written = generate(args.map, args.out)
    for path in written:
        print("wrote " + os.path.relpath(path))
    print("")
    print("print every sheet at its recorded size (see the caption on the sheet),")
    print("then tape it to the floor with the arrow pointing away from the robot.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
