import Foundation

/// One AR frame in which a marker was visible. Both poses are planar projections
/// of the AR session poses: x and y are the horizontal position, yaw is the
/// heading around the gravity axis.
public struct ArObservation {
    public let markerId: String
    public let markerInAr: Pose2D
    public let deviceInAr: Pose2D
    public let timestampS: Double

    public init(markerId: String, markerInAr: Pose2D, deviceInAr: Pose2D, timestampS: Double = 0.0) {
        self.markerId = markerId
        self.markerInAr = markerInAr
        self.deviceInAr = deviceInAr
        self.timestampS = timestampS
    }
}

/// Robot pose estimation: AR anchor alignment plus wheel-odometry dead reckoning.
/// Mirrors openbene_nav.pose.PoseEstimator.
public final class PoseEstimator {
    private let mapData: MapData
    private let wheelBaseM: Double
    private let wheelRadiusM: Double

    public private(set) var aligned = false
    public private(set) var mapFromAr: Pose2D?
    public private(set) var pose: Pose2D?
    public private(set) var lastMarkerId: String?
    public private(set) var lastFixTimeS = 0.0
    public private(set) var driftM = 0.0
    public private(set) var arUpdates = 0
    public private(set) var odometryUpdates = 0

    public init(mapData: MapData, wheelBaseM: Double = 0.30, wheelRadiusM: Double = 0.0325) {
        self.mapData = mapData
        self.wheelBaseM = wheelBaseM
        self.wheelRadiusM = wheelRadiusM
    }

    // -------------------------------------------------------------- anchors

    /// Solve the map/AR transform from a marker detection and snap the pose.
    @discardableResult
    public func align(_ observation: ArObservation) throws -> Pose2D {
        let marker = try mapData.marker(observation.markerId)
        let transform = marker.pose.compose(observation.markerInAr.inverse())
        mapFromAr = transform
        aligned = true
        lastMarkerId = observation.markerId
        lastFixTimeS = observation.timestampS
        let updated = transform.compose(observation.deviceInAr)
        pose = updated
        driftM = 0.0
        arUpdates += 1
        return updated
    }

    /// Update the pose from an AR frame while already aligned.
    @discardableResult
    public func updateFromAr(_ deviceInAr: Pose2D, timestampS: Double = 0.0) -> Pose2D? {
        guard aligned, let transform = mapFromAr else { return nil }
        let updated = transform.compose(deviceInAr)
        pose = updated
        driftM = 0.0
        lastFixTimeS = timestampS
        arUpdates += 1
        return updated
    }

    // ------------------------------------------------------------- odometry

    /// Dead-reckon the pose from the wheel speeds the firmware reports.
    @discardableResult
    public func integrateOdometry(rpmLeft: Double, rpmRight: Double, dtS: Double) -> Pose2D? {
        guard let current = pose, dtS > 0.0 else { return pose }
        let circumference = 2.0 * Double.pi * wheelRadiusM
        let vLeft = rpmLeft / 60.0 * circumference
        let vRight = rpmRight / 60.0 * circumference
        let linear = 0.5 * (vLeft + vRight)
        let angular = (vRight - vLeft) / wheelBaseM

        let moved = current.translated(forwardM: linear * dtS)
        pose = Pose2D(x: moved.x, y: moved.y, yawRad: wrapRad(current.yawRad + angular * dtS))
        driftM += abs(linear * dtS)
        odometryUpdates += 1
        return pose
    }

    // -------------------------------------------------------------- helpers

    public func requirePose() throws -> Pose2D {
        guard let pose = pose else { throw MapError.invalidMap("pose is not known yet: align on a marker first") }
        return pose
    }

    public func reset() {
        aligned = false
        mapFromAr = nil
        pose = nil
        lastMarkerId = nil
        driftM = 0.0
    }
}
