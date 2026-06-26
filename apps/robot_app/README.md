# Robot App

`robot_app` is the imported robot-side Flutter app inside OpenBene.
It stays self-contained and talks to the PC SDK through the OpenBene protocol
instead of being folded into `openbene_sdk/`.

## Entry Path

```text
lib/main.dart
  -> lib/app/robot_app.dart
  -> lib/features/setup/presentation/setup_screen.dart
  -> lib/features/robot_camera/presentation/robot_camera_screen.dart
```

## What It Covers

- setup and connection flow
- live camera preview
- drive / auto / track controls
- telemetry and robot state presentation
- OpenBene-compatible `status` and `sensor_data` publishing
- UDP discovery broadcast on port `12345`
- WebSocket server on port `8765`

## Folder Structure

```text
robot_app/
  android/
  ios/
  assets/
  lib/
    app/
    core/
    features/
    services/
  test/
```

## How It Relates To OpenBene

- The PC SDK listens for the same discovery and WebSocket protocol that this app emits.
- `openbot-mobile-control/` remains the existing mobile app in the repo.
- `apps/` is the home for self-contained app-level Flutter projects.

## Run

```powershell
cd C:\Users\jiken\Desktop\OpenBene\apps\robot_app
flutter pub get
flutter analyze
flutter run
```

For repo-wide context, read [../../docs/architecture.md](../../docs/architecture.md).
