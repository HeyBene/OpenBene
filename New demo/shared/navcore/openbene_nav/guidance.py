"""Turn-by-turn guidance built from the route polyline.

This is the geometric equivalent of the direction guide produced by the QR-code
reference project (At location X, go straight to the left / turn right ...).
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from enum import Enum
from typing import List, Optional, Tuple

from .model import MapData, Pose2D, wrap_deg
from .router import Route


class StepKind(str, Enum):
    FORWARD = "forward"
    TURN_LEFT = "turn_left"
    TURN_RIGHT = "turn_right"
    TURN_BACK = "turn_back"
    ARRIVE = "arrive"


@dataclass(frozen=True)
class GuidanceStep:
    kind: StepKind
    distance_m: float
    at_location_id: Optional[str]
    at_location_name: Optional[str]
    message: str


class GuidanceBuilder:
    """Turn a route into a short list of instructions."""

    def __init__(self, map_data: MapData, turn_threshold_deg: float = 25.0) -> None:
        self.map_data = map_data
        self.turn_threshold_deg = float(turn_threshold_deg)

    def build(self, route: Route) -> List[GuidanceStep]:
        polyline = route.polyline
        if len(polyline) < 2:
            return [
                GuidanceStep(
                    kind=StepKind.ARRIVE,
                    distance_m=0.0,
                    at_location_id=route.destination_location_id,
                    at_location_name=self.map_data.location(route.destination_location_id).name,
                    message="Already at " + route.room.name,
                )
            ]

        steps: List[GuidanceStep] = []
        pending_distance = 0.0
        heading: Optional[float] = None

        for index in range(len(polyline) - 1):
            start = polyline[index]
            end = polyline[index + 1]
            segment_heading = start.bearing_to(end)
            segment_length = start.distance_to(end)

            if heading is not None:
                turn = wrap_deg(math.degrees(segment_heading - heading))
                if abs(turn) >= self.turn_threshold_deg:
                    kind = self._turn_kind(turn)
                    location = self._closest_location(start)
                    steps.append(
                        GuidanceStep(
                            kind=kind,
                            distance_m=pending_distance,
                            at_location_id=location.id if location else None,
                            at_location_name=location.name if location else None,
                            message=self._turn_message(kind, location.name if location else None, pending_distance),
                        )
                    )
                    pending_distance = 0.0

            pending_distance += segment_length
            heading = segment_heading

        destination = self.map_data.location(route.destination_location_id)
        steps.append(
            GuidanceStep(
                kind=StepKind.ARRIVE,
                distance_m=pending_distance,
                at_location_id=destination.id,
                at_location_name=destination.name,
                message="Forward {:.1f} m, then arrive at {}".format(pending_distance, route.room.name),
            )
        )
        return steps

    @staticmethod
    def _turn_kind(turn_deg: float) -> StepKind:
        if abs(turn_deg) >= 150.0:
            return StepKind.TURN_BACK
        return StepKind.TURN_LEFT if turn_deg > 0 else StepKind.TURN_RIGHT

    @staticmethod
    def _turn_message(kind: StepKind, location_name: Optional[str], distance_m: float) -> str:
        where = " at " + location_name if location_name else ""
        if kind is StepKind.TURN_LEFT:
            return "Forward {:.1f} m, then turn left{}".format(distance_m, where)
        if kind is StepKind.TURN_RIGHT:
            return "Forward {:.1f} m, then turn right{}".format(distance_m, where)
        if kind is StepKind.TURN_BACK:
            return "Forward {:.1f} m, then turn back{}".format(distance_m, where)
        return "Forward {:.1f} m".format(distance_m)

    def _closest_location(self, pose: Pose2D):
        if not self.map_data.locations:
            return None
        nearest = min(self.map_data.locations, key=lambda location: location.pose.distance_to(pose))
        if nearest.pose.distance_to(pose) > 1.5:
            return None
        return nearest
