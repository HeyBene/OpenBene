"""Check a demo map json before you print markers and tape them to the floor."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def validate(raw: dict, tolerance_m: float = 0.25) -> list:
    problems = []
    markers = {item["id"]: item for item in raw.get("markers", [])}
    locations = {item["id"]: item for item in raw.get("locations", [])}
    edges = raw.get("edges", [])
    rooms = raw.get("rooms", [])

    if not markers:
        problems.append("map has no markers")
    if not locations:
        problems.append("map has no locations")

    payloads = {}
    for marker in raw.get("markers", []):
        payload = marker.get("payload")
        if not payload:
            problems.append("marker {} has no payload".format(marker.get("id")))
        elif payload in payloads:
            problems.append("markers {} and {} share payload {}".format(payloads[payload], marker.get("id"), payload))
        else:
            payloads[payload] = marker.get("id")
        size = float(marker.get("size_m", 0.0))
        if size <= 0.05 or size > 1.0:
            problems.append("marker {} has an implausible size_m: {}".format(marker.get("id"), size))
        if "pose" not in marker:
            problems.append("marker {} has no pose".format(marker.get("id")))

    for location in raw.get("locations", []):
        marker_id = location.get("marker_id")
        if marker_id is not None and marker_id not in markers:
            problems.append("location {} references unknown marker {}".format(location["id"], marker_id))

    seen_edges = set()
    for edge in edges:
        for endpoint in ("from", "to"):
            if edge[endpoint] not in locations:
                problems.append("edge {} references unknown location {}".format(edge["id"], edge[endpoint]))
        if edge["id"] in seen_edges:
            problems.append("duplicate edge id {}".format(edge["id"]))
        seen_edges.add(edge["id"])
        path = edge.get("path", [])
        if len(path) < 2:
            problems.append("edge {} has fewer than two path points".format(edge["id"]))
            continue
        for end, point in (("from", path[0]), ("to", path[-1])):
            location = locations.get(edge[end])
            if location is None:
                continue
            dx = location["pose"]["x"] - point["x"]
            dy = location["pose"]["y"] - point["y"]
            distance = (dx * dx + dy * dy) ** 0.5
            if distance > tolerance_m:
                problems.append(
                    "edge {} {} end is {:.2f} m away from location {} pose".format(
                        edge["id"], end, distance, edge[end]
                    )
                )

    for room in rooms:
        if room.get("location_id") not in locations:
            problems.append("room {} references unknown location {}".format(room.get("id"), room.get("location_id")))

    for location in raw.get("locations", []):
        if not any(edge["from"] == location["id"] or edge["to"] == location["id"] for edge in edges):
            problems.append("location {} is not connected to any edge".format(location["id"]))
    return problems


def main(argv=None) -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="Validate a demo map json")
    parser.add_argument("--map", default=str(root / "maps" / "demo_floor.json"))
    args = parser.parse_args(argv)

    raw = json.loads(Path(args.map).read_text(encoding="utf-8"))
    problems = validate(raw)
    if problems:
        print("map {} has {} problem(s):".format(args.map, len(problems)))
        for problem in problems:
            print("  - " + problem)
        return 1
    print("map {} looks good: {} markers, {} locations, {} edges, {} rooms".format(
        args.map,
        len(raw.get("markers", [])),
        len(raw.get("locations", [])),
        len(raw.get("edges", [])),
        len(raw.get("rooms", [])),
    ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
