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
        // Must be tracking normally
        guard frame.camera.trackingState == .normal else { return false }

        let currentTime = frame.timestamp
        let currentPose = frame.camera.transform

        // Always accept first frame
        guard let lastPose = lastAcceptedPose else {
            accept(pose: currentPose, time: currentTime)
            return true
        }

        // Time gate
        guard (currentTime - lastAcceptedTime) >= minTimeInterval else { return false }

        // Translation delta
        let lastPos = SIMD3<Float>(lastPose.columns.3.x, lastPose.columns.3.y, lastPose.columns.3.z)
        let curPos = SIMD3<Float>(currentPose.columns.3.x, currentPose.columns.3.y, currentPose.columns.3.z)
        let translationDelta = simd_length(curPos - lastPos)

        // Rotation delta (approximate via rotation matrix difference)
        let lastRot = simd_float3x3(
            SIMD3(lastPose.columns.0.x, lastPose.columns.0.y, lastPose.columns.0.z),
            SIMD3(lastPose.columns.1.x, lastPose.columns.1.y, lastPose.columns.1.z),
            SIMD3(lastPose.columns.2.x, lastPose.columns.2.y, lastPose.columns.2.z)
        )
        let curRot = simd_float3x3(
            SIMD3(currentPose.columns.0.x, currentPose.columns.0.y, currentPose.columns.0.z),
            SIMD3(currentPose.columns.1.x, currentPose.columns.1.y, currentPose.columns.1.z),
            SIMD3(currentPose.columns.2.x, currentPose.columns.2.y, currentPose.columns.2.z)
        )
        let relativeRot = lastRot.transpose * curRot
        let trace = relativeRot.columns.0.x + relativeRot.columns.1.y + relativeRot.columns.2.z
        let cosAngle = (trace - 1.0) / 2.0
        let rotationDelta = acos(min(max(cosAngle, -1.0), 1.0))

        // Accept if either translation or rotation exceeds threshold
        if translationDelta >= minTranslationDelta || rotationDelta >= minRotationDelta {
            accept(pose: currentPose, time: currentTime)
            return true
        }

        return false
    }

    private func accept(pose: simd_float4x4, time: TimeInterval) {
        lastAcceptedPose = pose
        lastAcceptedTime = time
    }
}
