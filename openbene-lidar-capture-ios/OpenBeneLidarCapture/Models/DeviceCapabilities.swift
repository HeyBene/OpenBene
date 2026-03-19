import Foundation
import ARKit

/// 设备能力检测。
/// 这里只关心采集链路是否可运行，不做更复杂的硬件分类。
final class DeviceCapabilities {

    /// 是否支持 LiDAR 深度。
    /// 对应 ARKit 的 sceneDepth 语义能力。
    static var isLiDARAvailable: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    /// 是否支持 AR 世界跟踪。
    static var isARWorldTrackingAvailable: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    /// 给 UI 展示的简要能力摘要。
    static var summary: String {
        var lines: [String] = []
        lines.append("ARKit World Tracking: \(isARWorldTrackingAvailable ? "Supported" : "Not Supported")")
        lines.append("LiDAR Depth: \(isLiDARAvailable ? "Supported" : "Not Available")")
        return lines.joined(separator: "\n")
    }
}
