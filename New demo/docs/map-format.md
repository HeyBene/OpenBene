# Demo map format

One JSON file describes the demo floor: the printed marker sheets, the graph the
robot can drive on, and the rooms the user picks. `shared/maps/demo_floor.json`
is the single source of truth; `shared/tools/sync_demo_assets.py` copies it into
the Android assets and the iOS resources, and `shared/tools/validate_map.py`
checks it.

## Frame

x points east, y points north, yaw is measured counter-clockwise from +x and the
floor is the z = 0 plane. Positions are in metres.

## Top level

| field | meaning |
| --- | --- |
| `map_id`, `name` | identifiers shown in the apps |
| `units` | always `meters` |
| `markers` | printed anchor sheets |
| `locations` | graph nodes the router can start from or drive through |
| `edges` | drivable connections between two locations |
| `rooms` | user visible destinations, each pointing at one location |

## markers

| field | meaning |
| --- | --- |
| `id` | stable identifier, also the ARCore/ARKit image anchor name |
| `kind` | `qr` for the printed sheets of this demo |
| `payload` | the string encoded in the QR code, e.g. `openbene:mk_entrance` |
| `ar_image` | file name (without extension) of the printable sheet in `shared/markers` |
| `size_m` | physical width of the printed sheet, 0.2 m here |
| `pose` | where the sheet lies on the floor |

`pose.yaw_deg` is the map direction of the marker image **+y axis**, that is the
direction from the bottom edge of the print to the top edge. On the sheets this
is the printed arrow, so tape every sheet down with the arrow pointing away from
the approaching robot: the arrow shows the direction of travel at that point.

## locations

`pose` is where the robot should end up when the leg finishes, normally about a
metre past the marker of the previous leg so the down-tilted camera can still
see it. `marker_id` links the node to the sheet that re-localises the robot when
it arrives; it may be omitted for a node that has no sheet.

## edges

`path` is the drivable polyline from `from` to `to`, and `bidirectional` says
whether the robot may travel it in both directions. `direction` is a human
readable hint (`forward`, `left`, ...) used by the documentation and the demo
UI. The router builds a Dijkstra graph weighted by the path length.

## rooms

Each room points at the location where the robot should stop, which is what the
user picks in the app.

## Adding a floor

1. Copy `demo_floor.json`, change `map_id` and the entries.
2. Add the sheets to `shared/maps`-adjacent `shared/markers` by adding markers
   and running `python shared/tools/make_markers.py`.
3. Run `python shared/tools/validate_map.py` and
   `python shared/tools/sync_demo_assets.py`.
4. Run the Python demo (`python shared/navcore/run_demo.py --destination "..."`)
   and the unit tests before touching the phone apps.
