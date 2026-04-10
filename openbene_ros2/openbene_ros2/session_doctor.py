from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

from .capture_manifest import load_capture_manifest


def build_session_report(session_dir: str | Path) -> list[str]:
    manifest = load_capture_manifest(session_dir)

    total_frames = len(manifest.frames)
    depth_frames = [frame for frame in manifest.frames if frame.depth_path is not None and frame.depth_path.exists()]
    confidence_frames = [
        frame for frame in manifest.frames if frame.confidence_path is not None and frame.confidence_path.exists()
    ]
    tracking_states = [frame.tracking_state for frame in manifest.frames if frame.tracking_state]
    depth_sources = [frame.depth_source for frame in manifest.frames if frame.depth_source]
    missing_image_count = sum(1 for frame in manifest.frames if frame.image_path is None)
    missing_depth_file_count = sum(
        1 for frame in manifest.frames if frame.depth_path is not None and not frame.depth_path.exists()
    )
    missing_confidence_file_count = sum(
        1 for frame in manifest.frames if frame.confidence_path is not None and not frame.confidence_path.exists()
    )

    tracking_counter = Counter(tracking_states)
    depth_source_counter = Counter(depth_sources)

    lines = [
        "OpenBene Session Doctor",
        "=======================",
        f"[INFO] session_dir={manifest.dataset_dir}",
        f"[INFO] total_frames={total_frames}",
        f"[INFO] depth_frames={len(depth_frames)}",
        f"[INFO] confidence_frames={len(confidence_frames)}",
        f"[INFO] frames_with_tracking_state={len(tracking_states)}",
        f"[INFO] frames_with_depth_source={len(depth_sources)}",
        f"[INFO] frames_without_image={missing_image_count}",
    ]

    if tracking_counter:
        breakdown = ", ".join(f"{name}={count}" for name, count in sorted(tracking_counter.items()))
        lines.append(f"[INFO] tracking_state_breakdown={breakdown}")
    else:
        lines.append("[WARN] tracking_state is missing for all frames.")

    if depth_source_counter:
        breakdown = ", ".join(f"{name}={count}" for name, count in sorted(depth_source_counter.items()))
        lines.append(f"[INFO] depth_source_breakdown={breakdown}")
    else:
        lines.append("[WARN] depth_source is missing for all frames.")

    if total_frames == 0:
        lines.append("[ERROR] manifest contains zero frames.")
    if not depth_frames:
        lines.append("[ERROR] no readable depth frames were found.")
    if missing_depth_file_count > 0:
        lines.append(f"[WARN] {missing_depth_file_count} frame(s) reference missing depth files.")
    if missing_confidence_file_count > 0:
        lines.append(f"[WARN] {missing_confidence_file_count} frame(s) reference missing confidence files.")
    if not confidence_frames:
        lines.append("[WARN] no readable confidence frames were found. 2D filtering will fall back to raw depth only.")
    if "normal" not in tracking_counter:
        lines.append("[WARN] no frames are marked with tracking_state=normal.")
    if depth_source_counter and "smoothed_scene_depth" not in depth_source_counter:
        lines.append("[WARN] no frames are marked with depth_source=smoothed_scene_depth.")
    if total_frames > 0 and len(depth_frames) == total_frames:
        lines.append("[OK] all frames have readable depth.")
    if total_frames > 0 and len(tracking_states) == total_frames:
        lines.append("[OK] all frames include tracking_state.")
    if total_frames > 0 and len(depth_sources) == total_frames:
        lines.append("[OK] all frames include depth_source.")
    if depth_frames:
        lines.append("[OK] session is usable for the current 2D ROS2 scan pipeline.")

    return lines


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Inspect an OpenBene capture session for the 2D ROS2 pipeline.")
    parser.add_argument("session_dir", help="Path to a session directory containing transforms.json")
    args = parser.parse_args(argv)

    for line in build_session_report(args.session_dir):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
