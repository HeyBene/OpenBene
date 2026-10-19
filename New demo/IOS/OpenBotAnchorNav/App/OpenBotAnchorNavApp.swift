import SwiftUI
import ARKit
import AVFoundation

@main
struct OpenBotAnchorNavApp: App {
    @StateObject private var demo = DemoSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(demo)
                .onAppear { demo.load(); recordCameraCapabilities() }
        }
    }

    private func recordCameraCapabilities() {
        #if DEBUG
        // Read-only capability inspection: no capture session or motor action.
        let formats: [[String: Any]] = ARWorldTrackingConfiguration.supportedVideoFormats.map {
            ["cameraType": $0.captureDeviceType.rawValue, "width": $0.imageResolution.width,
             "height": $0.imageResolution.height, "fps": $0.framesPerSecond]
        }
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera],
            mediaType: .video, position: .back).devices
        let hardware: [[String: Any]] = devices.map {
            ["cameraType": $0.deviceType.rawValue, "defaultFormatFovDeg": $0.activeFormat.videoFieldOfView,
             "minZoom": $0.minAvailableVideoZoomFactor, "maxZoom": $0.maxAvailableVideoZoomFactor]
        }
        FollowDiagnostics(fileName: "camera.jsonl", tag: "Camera").record([
            "event": "capabilities", "worldFormats": formats, "rearCameraHardware": hardware,
            "sceneDepthSupported": ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)])
        #endif
    }
}
