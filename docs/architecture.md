# Architecture

This repo is easiest to understand if we keep the boundaries explicit:

- `openbene_sdk/` is the PC-side Python SDK.
- `openbot-mobile-control/` is the existing Flutter mobile app.
- `apps/robot_app/` is the imported robot-side Flutter app.
- `openbot/` is the firmware baseline.

## Current Structure

```text
OpenBene/
- openbene_sdk/
- openbot-mobile-control/
- apps/
  - robot_app/
- openbot/
- docs/
- openbene_mobility/
- openbene_local/
```

## Message Flow

The phone and the PC talk over WebSocket JSON messages.

- PC -> phone: drive commands, stop commands, and control requests.
- phone -> PC: status, telemetry, and session state.

Keep those transport concerns out of UI code and SDK helpers.

## Future Shape

The long-term goal is not to collapse the apps into one folder.
Instead:

- keep `openbot-mobile-control/` as the existing app until it is intentionally replaced
- keep `apps/robot_app/` as a self-contained app with its own README, assets, and platform bridges
- place any future Flutter app under `apps/<name>/`
- keep shared protocol helpers in `openbene_sdk/`, not inside the UI trees

## Repository Boundaries

- Keep Flutter code in the mobile app tree.
- Keep Python code in `openbene_sdk/`.
- Keep protocol notes small and explicit.
- If a compatibility path must remain, document it clearly instead of mixing it into the main newcomer path.
- Keep auxiliary local workspaces (`openbene_local/`, `openbene_mobility/`) out of the main newcomer path.

## New Contributor Path

- PC control and scripting: `openbene_sdk/README.md`
- Current phone/mobile app: `openbot-mobile-control/README.md`
- Imported robot app: `apps/robot_app/README.md`
- Repo map and migration boundaries: this file
