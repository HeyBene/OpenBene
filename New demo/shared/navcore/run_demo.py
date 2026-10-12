"""Run the reference navigation episode from the command line.

Example:

    python run_demo.py --destination "Room 101"
    python run_demo.py --destination "Room 102" --start loc_room101
    python run_demo.py --destination "Room 101" --obstacle
"""

from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from openbene_nav import GuidanceBuilder, MapData, Router  # noqa: E402
from openbene_nav.executor import ExecutorConfig  # noqa: E402
from openbene_nav.harness import run_episode  # noqa: E402
from openbene_nav.simulation import Obstacle, SimConfig  # noqa: E402

DEFAULT_MAP = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "maps", "demo_floor.json"
)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="OpenBene anchor navigation demo")
    parser.add_argument("--map", default=DEFAULT_MAP, help="path to the demo map json")
    parser.add_argument("--start", default="loc_entrance", help="start location id")
    parser.add_argument("--destination", default="Room 101", help="destination room name")
    parser.add_argument("--obstacle", action="store_true", help="drop a crate on the way to Room 101")
    parser.add_argument("--trace-every", type=float, default=2.0, help="trace period in seconds")
    parser.add_argument("--max-time", type=float, default=240.0, help="episode time limit in seconds")
    parser.add_argument("--quiet", action="store_true", help="only print the final report")
    args = parser.parse_args(argv)

    map_data = MapData.load(args.map)
    router = Router(map_data)
    route = router.route_to_room(args.start, args.destination)
    if route is None:
        print("no route from {} to {}".format(args.start, args.destination))
        return 2

    print("map        : {} ({})".format(map_data.name, map_data.map_id))
    print("start      : {}".format(map_data.location(args.start).name))
    print("destination: {}".format(route.room.name))
    print("distance   : {:.1f} m".format(route.total_distance_m))
    print("route      : {}".format(" -> ".join(route.location_sequence())))
    print("")
    print("turn-by-turn guidance")
    for step in GuidanceBuilder(map_data).build(route):
        print("  [{:11s}] {:6.1f} m  {}".format(step.kind.value, step.distance_m, step.message))
    print("")

    obstacles = []
    if args.obstacle:
        # A crate in the corridor that is moved out of the way after 20 seconds.
        obstacles.append(Obstacle(x=2.0, y=0.0, radius_m=0.30, clear_after_s=20.0))

    def emit(event):
        if not args.quiet:
            print(event.format())

    result = run_episode(
        map_data,
        route,
        sim_config=SimConfig(),
        executor_config=ExecutorConfig(),
        obstacles=obstacles,
        max_time_s=args.max_time,
        trace_every_s=args.trace_every,
        on_event=emit,
    )

    print("")
    print("state changes")
    for change in result.state_changes:
        print("  " + change)
    print("")
    print(result.report())
    return 0 if result.arrived else 1


if __name__ == "__main__":
    raise SystemExit(main())
