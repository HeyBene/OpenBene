import Foundation

/// One image observation establishes the map frame for this AR session.
/// Later image observations never move the saved nodes. Camera tracking remains
/// the sole source of motion, including after the image leaves the camera view.
public struct FixedAnchorFrame {
    public private(set) var mapFromAr: Pose2D?
    public init() {}

    @discardableResult
    public mutating func alignOnce(markerInAr: Pose2D) -> Bool {
        guard mapFromAr == nil else { return false }
        mapFromAr = markerInAr.inverse()
        return true
    }

    public func pose(deviceInAr: Pose2D, trackingNormal: Bool) -> Pose2D? {
        guard trackingNormal else { return nil }
        return mapFromAr?.compose(deviceInAr)
    }

    /// Explicit terminal-return correction. Capture and ordinary route replay
    /// still call alignOnce, so later observations cannot move their map.
    public mutating func realignForReturn(markerInAr: Pose2D) -> Bool {
        guard mapFromAr != nil, TrajectoryCorridor.finite(markerInAr) else { return false }
        mapFromAr = markerInAr.inverse()
        return true
    }
}
