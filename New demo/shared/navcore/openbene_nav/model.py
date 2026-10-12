"""Map data model shared by the Android and iOS demos.

Everything lives in one 2D map frame: x points east, y points north and yaw is
measured counter-clockwise from +x. See docs/map-format.md for the JSON schema.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple


def wrap_deg(angle_deg: float) -> float:
    """Wrap an angle in degrees into (-180, 180]."""

    return (float(angle_deg) + 180.0) % 360.0 - 180.0


def wrap_rad(angle_rad: float) -> float:
    """Wrap an angle in radians into (-pi, pi]."""

    return (float(angle_rad) + math.pi) % (2.0 * math.pi) - math.pi


@dataclass(frozen=True)
class Pose2D:
    """A planar pose. yaw_rad is counter-clockwise from +x."""

    x: float
    y: float
    yaw_rad: float = 0.0

    @staticmethod
    def from_deg(x: float, y: float, yaw_deg: float = 0.0) -> "Pose2D":
        return Pose2D(float(x), float(y), math.radians(float(yaw_deg)))

    @property
    def yaw_deg(self) -> float:
        return math.degrees(self.yaw_rad)

    def compose(self, other: "Pose2D") -> "Pose2D":
        """Compose with another pose, which is expressed in this pose's frame."""

        cos_y = math.cos(self.yaw_rad)
        sin_y = math.sin(self.yaw_rad)
        return Pose2D(
            self.x + cos_y * other.x - sin_y * other.y,
            self.y + sin_y * other.x + cos_y * other.y,
            wrap_rad(self.yaw_rad + other.yaw_rad),
        )

    def inverse(self) -> "Pose2D":
        cos_y = math.cos(self.yaw_rad)
        sin_y = math.sin(self.yaw_rad)
        return Pose2D(
            -cos_y * self.x - sin_y * self.y,
            sin_y * self.x - cos_y * self.y,
            wrap_rad(-self.yaw_rad),
        )

    def translated(self, forward_m: float, left_m: float = 0.0) -> "Pose2D":
        cos_y = math.cos(self.yaw_rad)
        sin_y = math.sin(self.yaw_rad)
        return Pose2D(
            self.x + cos_y * forward_m - sin_y * left_m,
            self.y + sin_y * forward_m + cos_y * left_m,
            self.yaw_rad,
        )

    def distance_to(self, other: "Pose2D") -> float:
        return math.hypot(other.x - self.x, other.y - self.y)

    def bearing_to(self, other: "Pose2D") -> float:
        return math.atan2(other.y - self.y, other.x - self.x)

    def heading_error_to(self, other: "Pose2D") -> float:
        """Signed angle the robot has to turn to face another pose."""

        return wrap_rad(self.bearing_to(other) - self.yaw_rad)


@dataclass(frozen=True)
class Marker:
    """A printed anchor sheet lying on the floor.

    pose is the pose of the sheet in the map frame. pose.yaw_deg is the map
    direction of the marker image +y axis, that is the direction from the bottom
    edge of the print to its top edge.
    """

    id: str
    kind: str
    payload: str
    ar_image: str
    size_m: float
    pose: Pose2D


@dataclass(frozen=True)
class Location:
    """A graph node the router can start from or drive through."""

    id: str
    name: str
    pose: Pose2D
    marker_id: Optional[str] = None


@dataclass(frozen=True)
class Edge:
    id: str
    from_id: str
    to_id: str
    path: Tuple[Pose2D, ...]
    bidirectional: bool = True
    direction: str = "forward"

    def distance_m(self) -> float:
        total = 0.0
        for first, second in zip(self.path, self.path[1:]):
            total += first.distance_to(second)
        return total

    def path_from(self, start_location_id: str) -> Tuple[Pose2D, ...]:
        """Return the path oriented so that it starts at start_location_id."""

        if start_location_id == self.from_id:
            return self.path
        if start_location_id == self.to_id:
            return tuple(reversed(self.path))
        raise ValueError(f"{start_location_id!r} is not part of edge {self.id!r}")

    def other_end(self, location_id: str) -> str:
        if location_id == self.from_id:
            return self.to_id
        if location_id == self.to_id:
            return self.from_id
        raise ValueError(f"{location_id!r} is not part of edge {self.id!r}")


@dataclass(frozen=True)
class Room:
    id: str
    name: str
    location_id: str


class MapData:
    """Parsed demo map: markers, locations, edges and rooms."""

    def __init__(
        self,
        map_id: str,
        name: str,
        markers: Sequence[Marker],
        locations: Sequence[Location],
        edges: Sequence[Edge],
        rooms: Sequence[Room],
    ) -> None:
        self.map_id = map_id
        self.name = name
        self.markers: Tuple[Marker, ...] = tuple(markers)
        self.locations: Tuple[Location, ...] = tuple(locations)
        self.edges: Tuple[Edge, ...] = tuple(edges)
        self.rooms: Tuple[Room, ...] = tuple(rooms)

        self._markers_by_id: Dict[str, Marker] = {marker.id: marker for marker in self.markers}
        self._markers_by_payload: Dict[str, Marker] = {marker.payload: marker for marker in self.markers}
        self._locations_by_id: Dict[str, Location] = {loc.id: loc for loc in self.locations}
        self._rooms_by_id: Dict[str, Room] = {room.id: room for room in self.rooms}
        self._adjacency: Dict[str, List[Edge]] = {loc.id: [] for loc in self.locations}
        for edge in self.edges:
            self._adjacency.setdefault(edge.from_id, []).append(edge)
            if edge.bidirectional:
                self._adjacency.setdefault(edge.to_id, []).append(edge)

    @staticmethod
    def load(path: str | Path) -> "MapData":
        raw = json.loads(Path(path).read_text(encoding="utf-8"))
        return MapData.from_dict(raw)

    @staticmethod
    def from_dict(raw: dict) -> "MapData":
        markers = [
            Marker(
                id=item["id"],
                kind=item.get("kind", "qr"),
                payload=item.get("payload", "openbene:" + item["id"]),
                ar_image=item.get("ar_image", item["id"]),
                size_m=float(item.get("size_m", 0.2)),
                pose=_pose(item["pose"]),
            )
            for item in raw.get("markers", [])
        ]
        locations = [
            Location(
                id=item["id"],
                name=item.get("name", item["id"]),
                pose=_pose(item["pose"]),
                marker_id=item.get("marker_id"),
            )
            for item in raw.get("locations", [])
        ]
        edges = []
        for item in raw.get("edges", []):
            path = tuple(_pose(point) for point in item["path"])
            if len(path) < 2:
                raise ValueError("edge needs at least two path points: " + str(item.get("id")))
            edges.append(
                Edge(
                    id=item["id"],
                    from_id=item["from"],
                    to_id=item["to"],
                    path=path,
                    bidirectional=bool(item.get("bidirectional", True)),
                    direction=item.get("direction", "forward"),
                )
            )
        rooms = [
            Room(id=item["id"], name=item["name"], location_id=item["location_id"])
            for item in raw.get("rooms", [])
        ]
        return MapData(
            map_id=raw.get("map_id", "map"),
            name=raw.get("name", raw.get("map_id", "map")),
            markers=markers,
            locations=locations,
            edges=edges,
            rooms=rooms,
        )

    def marker(self, marker_id: str) -> Marker:
        return self._markers_by_id[marker_id]

    def marker_for_payload(self, payload: str) -> Optional[Marker]:
        return self._markers_by_payload.get(payload.strip())

    def location(self, location_id: str) -> Location:
        return self._locations_by_id[location_id]

    def room(self, room_id: str) -> Room:
        return self._rooms_by_id[room_id]

    def rooms_named(self, name: str) -> List[Room]:
        wanted = name.strip().lower()
        return [room for room in self.rooms if room.name.lower() == wanted]

    def room_names(self) -> List[str]:
        return sorted({room.name for room in self.rooms})

    def edges_from(self, location_id: str) -> List[Edge]:
        return list(self._adjacency.get(location_id, []))

    def has_location(self, location_id: str) -> bool:
        return location_id in self._locations_by_id

    def location_with_marker(self, marker_id: str) -> Optional[Location]:
        for location in self.locations:
            if location.marker_id == marker_id:
                return location
        return None

    def nearest_location(self, pose: Pose2D) -> Location:
        return min(self.locations, key=lambda location: location.pose.distance_to(pose))


def _pose(raw: dict) -> Pose2D:
    return Pose2D.from_deg(raw.get("x", 0.0), raw.get("y", 0.0), raw.get("yaw_deg", 0.0))
