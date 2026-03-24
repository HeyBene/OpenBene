import Foundation
import ARKit

/// Controls whether a given ARFrame should be accepted for capture.
/// Reduces redundancy, blur, and low-quality frames.
final class FrameAcceptancePolicy {

    /// Minimum translation (meters) between accepted frames.
    var minTranslationDelta: Float = 0.05  // 5cm

    /// Minimum rotation (radians) between accepted frames.
    var minRotationDelta: Float = 0.087  // ~5 degrees

    /// Minimum time interval (seconds) between accepted frames.
    var minTimeInterval: TimeInterval = 0.2  // 5 FPS max

    private var lastAcceptedPose: simd_float4x4?
    private var lastAcceptedTime: TimeInterval = 0

    func reset() {
        lastAcceptedPose = nil
        lastAcceptedTime = 0
    }

    /// Returns true if this frame should be saved.
    func shouldAccept(frame: ARFrame) -> Bool {
        guard frame.camera.trackingState == .normal else { return false }

        let currentTime = frame.timestamp
        let currentPose = frame.camera.transform

        guard let lastPose = lastAcceptedPose else {
            accept(pose: currentPose, time: currentTime)
            return true
        }

        guard (currentTime - lastAcceptedTime) >= minTimeInterval else { return false }

        let delta = poseDeltaMetrics(from: lastPose, to: currentPose)
        guard delta.severity == .none else { return false }

        if delta.translationMeters >= minTranslationDelta || delta.rotationRadians >= minRotationDelta {
            accept(pose: currentPose, time: currentTime)
            return true
        }

        return false
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
        if translationMeters > 0.15 || rotationDegrees > 20 {
            severity = .severe
        } else if translationMeters > 0.08 || rotationDegrees > 12 {
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
