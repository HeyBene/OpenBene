import Foundation
import ARKit
import Combine

/// Manages the ARSession lifecycle for LiDAR capture.
final class CaptureSessionManager: NSObject, ObservableObject {

    // MARK: - Published state

    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    @Published var trackingStateDescription: String = "Not Available"
    @Published var isSessionRunning: Bool = false
    @Published var isCapturing: Bool = false
    @Published var frameCount: Int = 0
    @Published var depthAvailable: Bool = false

    // MARK: - Internal

    private let session = ARSession()
    private var datasetWriter: NerfstudioDatasetWriter?
    private let acceptancePolicy = FrameAcceptancePolicy()

    /// Callback invoked for each accepted frame (for upload / dual-write).
    var onFrameAccepted: ((CaptureFrameRecord) -> Void)?

    override init() {
        super.init()
        session.delegate = self
        depthAvailable = DeviceCapabilities.isLiDARAvailable
    }

    // MARK: - Session control

    func startSession() {
        let config = ARWorldTrackingConfiguration()

        // Enable LiDAR depth if available
        if DeviceCapabilities.isLiDARAvailable {
            config.frameSemantics.insert(.sceneDepth)
        }

        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isSessionRunning = true
    }

    func stopSession() {
        session.pause()
        isSessionRunning = false
    }

    // MARK: - Capture control

    func startCapture(sessionName: String? = nil) {
        let name = sessionName ?? "session_\(Int(Date().timeIntervalSince1970))"

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sessionURL = documentsURL.appendingPathComponent("captures/\(name)")

        datasetWriter = NerfstudioDatasetWriter(outputDirectory: sessionURL, depthAvailable: depthAvailable)
        datasetWriter?.beginSession()

        frameCount = 0
        acceptancePolicy.reset()
        isCapturing = true
    }

    func stopCapture() {
        isCapturing = false
        datasetWriter?.finalizeSession()
        datasetWriter = nil
    }

    // MARK: - Frame processing (called from ARSessionDelegate)

    private func processFrame(_ frame: ARFrame) {
        guard isCapturing else { return }
        guard acceptancePolicy.shouldAccept(frame: frame) else { return }

        // Build frame record
        let record = CaptureFrameRecord(frame: frame, index: frameCount, depthAvailable: depthAvailable)

        // Write locally
        datasetWriter?.writeFrame(record)

        // Notify transport layer (for WebSocket upload)
        onFrameAccepted?(record)

        frameCount += 1
    }
}

// MARK: - ARSessionDelegate

extension CaptureSessionManager: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Update tracking state on main thread
        let state = frame.camera.trackingState
        DispatchQueue.main.async { [weak self] in
            self?.trackingState = state
            self?.trackingStateDescription = state.displayString
        }

        processFrame(frame)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.trackingStateDescription = "Session Error: \(error.localizedDescription)"
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            self?.trackingStateDescription = "Session Interrupted"
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async { [weak self] in
            self?.trackingStateDescription = "Resuming..."
        }
    }
}

// MARK: - TrackingState display helper

extension ARCamera.TrackingState {
    var displayString: String {
        switch self {
        case .notAvailable:
            return "Not Available"
        case .limited(let reason):
            switch reason {
            case .initializing:
                return "Initializing"
            case .excessiveMotion:
                return "Excessive Motion"
            case .insufficientFeatures:
                return "Insufficient Features"
            case .relocalizing:
                return "Relocalizing"
            @unknown default:
                return "Limited"
            }
        case .normal:
            return "Tracking Normal"
        }
    }
}
