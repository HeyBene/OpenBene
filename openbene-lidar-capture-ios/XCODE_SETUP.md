# OpenBene LiDAR Capture — Xcode Project Setup

Since the Xcode `.xcodeproj` must be created on macOS (it contains binary-encoded
project references that cannot be reliably hand-written), follow these steps on
your Mac mini to turn this source tree into a buildable Xcode project.

## One-time setup on Mac

1. Open Xcode → File → New → Project
2. Choose: iOS → App
3. Configure:
   - Product Name: `OpenBeneLidarCapture`
   - Team: (your dev team)
   - Organization Identifier: `com.openbene`  (or your preferred reverse-domain)
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Uncheck "Include Tests" for now
4. Save location: choose the `openbene-lidar-capture-ios/` folder in your repo
   - Xcode will create `OpenBeneLidarCapture.xcodeproj` inside it
5. **Delete** the auto-generated `ContentView.swift` and `OpenBeneLidarCaptureApp.swift`
   that Xcode creates (we already have our own versions)
6. In Xcode's Project Navigator, right-click the `OpenBeneLidarCapture` group →
   "Add Files to OpenBeneLidarCapture" → select all `.swift` files from:
   - `App/`
   - `UI/`
   - `Capture/`
   - `Models/`
   - `Dataset/`
   - `Utils/`
   - `Transport/` (empty for now, will be added in Module 4)
7. Also add `Assets.xcassets` if not already included
8. Add `Info.plist`:
   - In Build Settings → search "Info.plist File"
   - Set to: `OpenBeneLidarCapture/Info.plist`

## Build Settings to verify

- Deployment Target: **iOS 16.0** (minimum for stable LiDAR APIs)
- Frameworks: `ARKit` should be auto-linked; if not, add it under
  Build Phases → Link Binary With Libraries
- Also ensure `CoreVideo`, `ImageIO`, `UIKit` are linked (usually automatic)

## Run on device

- This app **requires a physical iPhone** (ARKit does not work in Simulator)
- For LiDAR depth: iPhone 12 Pro / 13 Pro / 14 Pro / 15 Pro or iPad Pro with LiDAR
- For RGB-only test mode: any iPhone with ARKit support (iPhone 6s+)

## File Sharing

The Info.plist enables `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`.
This means captured datasets will be accessible via:
- Finder (macOS) → iPhone → Files → OpenBeneLidarCapture
- iTunes File Sharing (Windows)
- iOS Files app (if available on the device)

This is the fallback export method. Primary export will be Wi-Fi/WebSocket (Module 4).
