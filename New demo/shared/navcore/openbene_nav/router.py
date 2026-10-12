"""Dijkstra routing over the demo map graph."""

from __future__ import annotations

import heapq
from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence, Tuple

from .model import Edge, MapData, Pose2D, Room


@dataclass(frozen=True)
class RouteLeg:
    edge: Edge
    from_id: str
    to_id: str
    path: Tuple[Pose2D, ...]

    @property
    def distance_m(self) -> float:
        total = 0.0
        for first, second in zip(self.path, self.path[1:]):
            total += first.distance_to(second)
        return total


@dataclass(frozen=True)
class Route:
    start_location_id: str
    destination_location_id: str
    room: Room
    legs: Tuple[RouteLeg, ...]
    polyline: Tuple[Pose2D, ...]
    total_distance_m: float

    def location_sequence(self) -> List[str]:
        sequence = [self.start_location_id]
        sequence.extend(leg.to_id for leg in self.legs)
        return sequence


class Router:
    """Shortest-path routing between locations, driven by room names."""

    def __init__(self, map_data: MapData) -> None:
        self.map_data = map_data

    def route_to_room(self, start_location_id: str, room_name: str) -> Optional[Route]:
        """Route to the closest room carrying the requested name."""

        rooms = self.map_data.rooms_named(room_name)
        if not rooms:
            return None
        best: Optional[Route] = None
        for room in rooms:
            candidate = self.route_to_location(start_location_id, room.location_id, room=room)
            if candidate is None:
                continue
            if best is None or candidate.total_distance_m < best.total_distance_m:
                best = candidate
        return best

    def route_to_location(
        self,
        start_location_id: str,
        destination_location_id: str,
        room: Optional[Room] = None,
    ) -> Optional[Route]:
        if not self.map_data.has_location(start_location_id):
            raise KeyError("unknown start location: " + start_location_id)
        if not self.map_data.has_location(destination_location_id):
            raise KeyError("unknown destination location: " + destination_location_id)

        resolved_room = room or Room(
            id=destination_location_id,
            name=self.map_data.location(destination_location_id).name,
            location_id=destination_location_id,
        )
        if start_location_id == destination_location_id:
            pose = self.map_data.location(start_location_id).pose
            return Route(
                start_location_id=start_location_id,
                destination_location_id=destination_location_id,
                room=resolved_room,
                legs=(),
                polyline=(pose,),
                total_distance_m=0.0,
            )

        previous, distance = self._dijkstra(start_location_id)
        if destination_location_id not in distance:
            return None

        location_ids: List[str] = [destination_location_id]
        cursor = destination_location_id
        while cursor != start_location_id:
            cursor = previous[cursor]
            location_ids.append(cursor)
        location_ids.reverse()

        legs: List[RouteLeg] = []
        for from_id, to_id in zip(location_ids, location_ids[1:]):
            edge = self._edge_between(from_id, to_id)
            if edge is None:  # pragma: no cover - dijkstra only walks existing edges
                raise RuntimeError("no edge between " + from_id + " and " + to_id)
            legs.append(RouteLeg(edge=edge, from_id=from_id, to_id=to_id, path=edge.path_from(from_id)))

        polyline = self._join_polyline(legs)
        total = 0.0
        for first, second in zip(polyline, polyline[1:]):
            total += first.distance_to(second)
        return Route(
            start_location_id=start_location_id,
            destination_location_id=destination_location_id,
            room=resolved_room,
            legs=tuple(legs),
            polyline=polyline,
            total_distance_m=total,
        )

    def _dijkstra(self, start_location_id: str) -> Tuple[Dict[str, str], Dict[str, float]]:
        distance: Dict[str, float] = {start_location_id: 0.0}
        previous: Dict[str, str] = {}
        queue: List[Tuple[float, str]] = [(0.0, start_location_id)]
        while queue:
            current_distance, current = heapq.heappop(queue)
            if current_distance > distance.get(current, float("inf")):
                continue
            for edge in self.map_data.edges_from(current):
                neighbour = edge.other_end(current)
                candidate = current_distance + edge.distance_m()
                if candidate < distance.get(neighbour, float("inf")):
                    distance[neighbour] = candidate
                    previous[neighbour] = current
                    heapq.heappush(queue, (candidate, neighbour))
        return previous, distance

    def _edge_between(self, from_id: str, to_id: str) -> Optional[Edge]:
        for edge in self.map_data.edges_from(from_id):
            if edge.other_end(from_id) == to_id:
                return edge
        return None

    @staticmethod
    def _join_polyline(legs: Sequence[RouteLeg]) -> Tuple[Pose2D, ...]:
        points: List[Pose2D] = []
        for leg in legs:
            leg_points = list(leg.path)
            if points and points[-1].distance_to(leg_points[0]) < 1e-6:
                leg_points = leg_points[1:]
            points.extend(leg_points)
        return tuple(points)
