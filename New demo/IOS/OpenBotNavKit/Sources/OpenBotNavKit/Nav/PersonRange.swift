import Foundation

public struct NormalizedCameraIntrinsics {
    public let fx: Double, fy: Double, cx: Double, cy: Double
    public init(fx: Double, fy: Double, cx: Double, cy: Double) {
        self.fx = fx; self.fy = fy; self.cx = cx; self.cy = cy
    }
}

/// Depth is optical-axis Z in meters, not a distance inferred from body size.
public enum PersonRangeEstimator {
    public static func horizontalDistance(depthM: Double, u: Double, v: Double,
        intrinsics k: NormalizedCameraIntrinsics, cameraInAr: RigidTransform) -> Double? {
        guard [depthM, u, v, k.fx, k.fy, k.cx, k.cy].allSatisfy({ $0.isFinite }),
              depthM >= 0.1, depthM <= 8, k.fx > 0, k.fy > 0,
              cameraInAr.rotation.count == 9, cameraInAr.rotation.allSatisfy({ $0.isFinite }) else { return nil }
        // Native captured-image coordinates: image Y points down, AR camera Y
        // up and camera forward -Z. Gravity-aligned AR removes camera pitch.
        let ray = [(u - k.cx) / k.fx * depthM, -(v - k.cy) / k.fy * depthM, -depthM]
        let world = cameraInAr.rotate(ray)
        let distance = hypot(world[0], world[2])
        return distance.isFinite && distance >= 0.05 ? distance : nil
    }

    public static func robustDistance(_ samples: [Double], attempted: Int) -> Double? {
        let values = samples.filter { $0.isFinite && (0.05...8).contains($0) }.sorted()
        guard values.count >= 12, attempted > 0, Double(values.count) / Double(attempted) >= 0.4 else { return nil }
        let median = values[values.count / 2]
        // An ROI split between the body and a distant wall is not a reliable
        // range. Do not silently call an uncertain measurement "far away".
        let spread = values[values.count * 3 / 4] - values[values.count / 4]
        guard spread <= max(0.25, median * 0.20) else { return nil }
        return median
    }
}
