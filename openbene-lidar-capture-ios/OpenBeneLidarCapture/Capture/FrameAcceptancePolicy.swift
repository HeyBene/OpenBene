import Foundation
import ARKit

/// 帧接收策略。
/// 作用是过滤掉过密、模糊或跟踪状态差的帧，减少冗余数据。
final class FrameAcceptancePolicy {

    /// 两帧之间的最小平移距离（米）。
    var minTranslationDelta: Float = 0.05  // 5cm

    /// 两帧之间的最小旋转角度（弧度）。
    var minRotationDelta: Float = 0.087  // 约 5 度

    /// 两帧之间的最小时间间隔（秒）。
    var minTimeInterval: TimeInterval = 0.2  // 最多约 5 FPS

    private var lastAcceptedPose: simd_float4x4?
    private var lastAcceptedTime: TimeInterval = 0

    func reset() {
        lastAcceptedPose = nil
        lastAcceptedTime = 0
    }

    /// 返回当前 ARFrame 是否应该被保存。
    func shouldAccept(frame: ARFrame) -> Bool {
        // 先要求 AR 跟踪状态正常。
        guard frame.camera.trackingState == .normal else { return false }

        let currentTime = frame.timestamp
        let currentPose = frame.camera.transform

        // 第一帧直接收下。
        guard let lastPose = lastAcceptedPose else {
            accept(pose: currentPose, time: currentTime)
            return true
        }

        // 时间门限：避免采得太密。
        guard (currentTime - lastAcceptedTime) >= minTimeInterval else { return false }

        // 平移变化量。
        let lastPos = SIMD3<Float>(lastPose.columns.3.x, lastPose.columns.3.y, lastPose.columns.3.z)
        let curPos = SIMD3<Float>(currentPose.columns.3.x, currentPose.columns.3.y, currentPose.columns.3.z)
        let translationDelta = simd_length(curPos - lastPos)

        // 旋转变化量：用相对旋转矩阵近似计算角度。
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

        // 平移或旋转任一超过门限，即接受该帧。
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
