import Foundation
import ARKit

/// Detects device capabilities relevant to LiDAR capture.
final class DeviceCapabilities {

    /// Whether the device has a LiDAR sensor (supports scene depth).
    static var isLiDARAvailable: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    /// Whether ARKit world tracking is supported at all.
    static var isARWorldTrackingAvailable: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    /// Human-readable summary for UI display.
    static var summary: String {
        var lines: [String] = []
        lines.append("ARKit World Tracking: \(isARWorldTrackingAvailable ? "Supported" : "Not Supported")")
        lines.append("LiDAR Depth: \(isLiDARAvailable ? "Supported" : "Not Available")")
        return lines.joined(separator: "\n")
    }
}
