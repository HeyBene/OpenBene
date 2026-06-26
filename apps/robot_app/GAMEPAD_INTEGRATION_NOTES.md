# Robot App gamepad integration notes

## Current verified behavior

Tested on the current Robot App + RTR_520 setup:

- App-side `START/STOP` is the master latch.
- The robot should only accept drive input after the app enters the armed state.
- Gamepad input path is working on-device.
- Current observed RTR_520 mapping:
  - `LT` / `RT` control reverse / forward
  - left stick controls left / right steering
- The UI `START/STOP` should stay tied to the app's armed state, not flip just because the robot is physically moving or stopping.

## Architecture

### Native Android capture

Gamepad input is captured on Android native side and forwarded to Flutter through an `EventChannel`.

Files:
- `android/app/src/main/kotlin/com/openbothci/robot_app/MainActivity.kt`
- `android/app/src/main/kotlin/com/openbothci/robot_app/GamepadInputBridge.kt`

Responsibilities:
- detect gamepad key events
- detect joystick / trigger motion events
- normalize event payloads into simple Flutter-friendly maps
- send button/axes events over `com.openbothci.robot_app/gamepad/events`

### Dart service/bootstrap layer

Files:
- `lib/services/android_gamepad_service_adapter.dart`
- `lib/app/robot_app_bootstrap.dart`

Responsibilities:
- subscribe to the native gamepad event channel
- expose a Dart stream of gamepad events
- initialize/dispose the gamepad listener along with other app services

### Robot control orchestration

File:
- `lib/features/robot_camera/state/robot_camera_controller.dart`

Responsibilities:
- app `START/STOP` arming/disarming
- ignore gamepad movement unless:
  - USB is connected
  - mode is `DRIVE`
  - app is armed
- compute drive output from axes
- forward left/right motor commands to the USB robot connection service
- stop on inactivity/background/disconnect conditions
- expose temporary gamepad debug text for mapping verification

### UI state

File:
- `lib/features/robot_camera/state/robot_camera_state.dart`

Important fields:
- `driveArmed`
- `gamepadConnected`
- `gamepadDebug`

### UI button and diagnostics

File:
- `lib/features/robot_camera/presentation/robot_camera_screen.dart`

Responsibilities:
- main `START/STOP` button
- top tray temporary diagnostics:
  - `GAMEPAD: ON/OFF`
  - `ARMED: YES/NO`
  - latest button/axes debug line

## Current control logic

### Arming
- user taps app `START`
- app enters armed state
- gamepad commands are then allowed through
- user taps app `STOP`
- app stops drive output and disarms

### Accepted input path
- native Android receives gamepad event
- Flutter gamepad adapter forwards event
- `RobotCameraController` checks safety gates
- controller converts input to `left/right`
- USB bridge sends OpenBot/OpenBene-style drive command to robot hardware

## Current mapping logic in code

Primary logic currently accepts both patterns, but RTR_520 is currently behaving as:
- steering from `lx`
- throttle from triggers (`lt` / `rt`)

The controller also has fallback handling for right-stick throttle (`ry` / `ryAlt`) and alternate Android axis names.

## Reuse checklist for another app

If you want to reuse this in another app, copy/adapt these layers in order:

1. Native bridge
   - `MainActivity.kt`
   - `GamepadInputBridge.kt`
2. Flutter adapter
   - `android_gamepad_service_adapter.dart`
3. Orchestration / safety layer
   - `robot_camera_controller.dart`
4. UI state fields
   - `robot_camera_state.dart`
5. UI trigger + diagnostics
   - `robot_camera_screen.dart`

## Key folders

- `apps/robot_app/android/app/src/main/kotlin/com/openbothci/robot_app/`
- `apps/robot_app/lib/services/`
- `apps/robot_app/lib/app/`
- `apps/robot_app/lib/features/robot_camera/state/`
- `apps/robot_app/lib/features/robot_camera/presentation/`

## Notes for future reuse

- Prefer app-side arming over hand-controller START.
- Keep the armed state separate from real-time motion telemetry.
- Different controllers may report different Android axes; keep a temporary debug overlay available when bringing up a new robot/controller combination.
- RTR_520 on this setup is currently most naturally driven by triggers + left stick steering.
