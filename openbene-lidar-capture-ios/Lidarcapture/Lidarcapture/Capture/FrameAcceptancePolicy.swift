import Foundation
import ARKit

enum AutoCaptureRejectionReason {
    case trackingUnstable
    case waitingForMinInterval
    case waitingForMotion
    case movementTooFast
}

enum FrameAcceptanceDecision {
    case accept
    case reject(AutoCaptureRejectionReason)
}

/// Controls whether a given ARFrame should be accepted for capture.
/// Reduces redundancy, blur, and low-quality frames.
final class FrameAcceptancePolicy {

    /// Minimum translation (meters) between accepted frames.
    var minTranslationDelta: Float = 0.035  // 3.5cm

    /// Minimum rotation (radians) between accepted frames.
    var minRotationDelta: Float = 0.07  // ~4 degrees

    /// Minimum time interval (seconds) between accepted frames.
    var minTimeInterval: TimeInterval = 0.2  // 5 FPS max

    /// If auto capture has paused for too long, allow a slightly smaller motion.
    var forcedAcceptAfterStallInterval: TimeInterval = 1.0
    var minTranslationDeltaAfterStall: Float = 0.02  // 2cm
    var minRotationDeltaAfterStall: Float = 0.044  // ~2.5 degrees

    private var lastAcceptedPose: simd_float4x4?
    private var lastAcceptedTime: TimeInterval = 0

    func reset() {
        lastAcceptedPose = nil
        lastAcceptedTime = 0
    }

    /// Returns true if this frame should be saved.
    func shouldAccept(frame: ARFrame) -> Bool {
        switch evaluate(frame: frame) {
        case .accept:
            return true
        case .reject:
            return false
        }
    }

    func evaluate(frame: ARFrame) -> FrameAcceptanceDecision {
        guard frame.camera.trackingState == .normal else { return .reject(.trackingUnstable) }

        let currentTime = frame.timestamp
        let currentPose = frame.camera.transform

        guard let lastPose = lastAcceptedPose else {
            accept(pose: currentPose, time: currentTime)
            return .accept
        }

        let elapsed = currentTime - lastAcceptedTime
        guard elapsed >= minTimeInterval else { return .reject(.waitingForMinInterval) }

        let delta = poseDeltaMetrics(from: lastPose, to: currentPose)
        guard delta.severity == .none else { return .reject(.movementTooFast) }

        if delta.translationMeters >= minTranslationDelta || delta.rotationRadians >= minRotationDelta {
            accept(pose: currentPose, time: currentTime)
            return .accept
        }

        if elapsed >= forcedAcceptAfterStallInterval,
           delta.translationMeters >= minTranslationDeltaAfterStall || delta.rotationRadians >= minRotationDeltaAfterStall {
            accept(pose: currentPose, time: currentTime)
            return .accept
        }

        return .reject(.waitingForMotion)
    }

    private func poseDeltaMetrics(from previousPose: simd_float4x4, to currentPose: simd_float4x4) -> (translationMeters: Float, rotationRadians: Float, severity: PoseJumpSeverity) {
        let previousPosition = SIMD3<Float>(previousPose.columns.3.x, previousPose.columns.3.y, previousPose.columns.3.z)
        let currentPosition = SIMD3<Float>(currentPose.columns.3.x, currentPose.columns.3.y, currentPose.columns.3.z)
        let translationMeters = simd_length(currentPosition - previousPosition)

        let previousRotation = simd_float3x3(
            SIMD3(previousPose.columns.0.x, previousPose.columns.0.y, previousPose.columns.0.z),
            SIMD3(previousPose.columns.1.x, previousPose.columns.1.y, previousPose.columns.1.z),
            SIMD3(previousPose.columns.2.x, previousPose.columns.2.y, previousPose.columns.2.z)
        )
        let currentRotation = simd_float3x3(
            SIMD3(currentPose.columns.0.x, currentPose.columns.0.y, currentPose.columns.0.z),
            SIMD3(currentPose.columns.1.x, currentPose.columns.1.y, currentPose.columns.1.z),
            SIMD3(currentPose.columns.2.x, currentPose.columns.2.y, currentPose.columns.2.z)
        )
        let relativeRotation = previousRotation.transpose * currentRotation
        let trace = relativeRotation.columns.0.x + relativeRotation.columns.1.y + relativeRotation.columns.2.z
        let cosAngle = (trace - 1.0) / 2.0
        let rotationRadians = acos(min(max(cosAngle, -1.0), 1.0))
        let rotationDegrees = rotationRadians * 180.0 / .pi

        let severity: PoseJumpSeverity
        if translationMeters > 0.22 || rotationDegrees > 30 {
            severity = .severe
        } else if translationMeters > 0.12 || rotationDegrees > 18 {
            severity = .suspicious
        } else {
            severity = .none
        }

        return (translationMeters, rotationRadians, severity)
    }

    private func accept(pose: simd_float4x4, time: TimeInterval) {
        lastAcceptedPose = pose
        lastAcceptedTime = time
    }
}
