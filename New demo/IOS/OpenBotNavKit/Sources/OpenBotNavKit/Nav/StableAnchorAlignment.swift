import Foundation

/// Only the initial observation is averaged. A locked map never follows later
/// image estimates, so looking away from the print cannot move the route.
public struct StableAnchorAlignment {
    private var observations: [(pose: Pose2D, time: Double)] = []
    public init() {}
    public mutating func reset() { observations.removeAll(keepingCapacity: true) }

    public mutating func observe(_ pose: Pose2D, timestampS: Double) -> Pose2D? {
        guard TrajectoryCorridor.finite(pose), timestampS.isFinite else { reset(); return nil }
        if let last = observations.last {
            if timestampS == last.time { return nil }
            if timestampS < last.time || timestampS - last.time > 0.15 { reset() }
        }
        if let first = observations.first,
           pose.distanceTo(first.pose) > 0.025 || abs(wrapRad(pose.yawRad - first.pose.yawRad)) > 3 * .pi / 180 {
            reset()
        }
        observations.append((pose, timestampS))
        if observations.count > 90 { observations.removeFirst() }
        guard let first = observations.first, observations.count >= 12,
              timestampS - first.time >= 0.5 else { return nil }
        let count = Double(observations.count)
        return Pose2D(x: observations.reduce(0) { $0 + $1.pose.x } / count,
            y: observations.reduce(0) { $0 + $1.pose.y } / count,
            yawRad: atan2(observations.reduce(0) { $0 + sin($1.pose.yawRad) },
                          observations.reduce(0) { $0 + cos($1.pose.yawRad) }))
    }
}
