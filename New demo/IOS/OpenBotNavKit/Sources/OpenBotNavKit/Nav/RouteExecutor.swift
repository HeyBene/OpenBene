import Foundation

public enum ExecutorState: String {
    case idle
    case needAnchor = "need_anchor"
    case scanning
    case driving
    case arrived
    case blocked
    case failed
}

public struct ExecutorConfig {
    public var waypointToleranceM = 0.30
    public var arrivalToleranceM = 0.40
    public var headingToleranceDeg = 15.0
    public var cruiseSpeed = 0.35
    public var turnSpeed = 0.22
    public var steerGain = 1.6
    public var obstacleStopCm = 35.0
    public var obstacleClearCm = 50.0
    public var reanchorAtWaypoints = true
    public var reanchorDriftM = 4.0
    public var markerScanRadiusM = 1.0
    public var markerScanHeadingDeg = 40.0
    public var holdTimeoutS = 2.5
    public var allowScanRotation = true
    public var scanSpeed = 0.25
    public var scanTimeoutS = 30.0

    public init() {}
}

public struct ExecutorStatus {
    public let state: ExecutorState
    public let message: String
    public let legIndex: Int
    public let pointIndex: Int
    public let target: Pose2D?
    public let distanceToTargetM: Double
    public let distanceRemainingM: Double
    public let pose: Pose2D?
    public let driftM: Double
    public let driftWarning: Bool
    public let expectedMarkerId: String?
    public let usedMarkers: [String]
}

/// Route execution state machine. Drives the OpenBot along the route polyline,
/// expects a marker fix during the approach of every anchored location, and
/// stops for obstacles the firmware sonar reports.
///
/// This mirrors openbene_nav.executor.RouteExecutor, which is covered by the
/// Python unit tests in shared/navcore/tests.
public final class RouteExecutor {
    private let mapData: MapData
    private let estimator: PoseEstimator
    private let link: RobotLink
    public let config: ExecutorConfig

    public private(set) var route: Route?
    public private(set) var state: ExecutorState = .idle
    public private(set) var message = "idle"
    public private(set) var legIndex = 0
    public private(set) var pointIndex = 0
    public private(set) var expectedMarkerId: String?
    public private(set) var usedMarkers: [String] = []

    private var legArrivalMarkerId: String?
    private var legMarkerFixed = false
    private var driftWarning = false
    private var scanStartedS: Double?

    public init(mapData: MapData, estimator: PoseEstimator, link: RobotLink, config: ExecutorConfig = ExecutorConfig()) {
        self.mapData = mapData
        self.estimator = estimator
        self.link = link
        self.config = config
    }

    public func start(_ route: Route, startLocationId: String? = nil) throws {
        self.route = route
        legIndex = 0
        pointIndex = 0
        usedMarkers = []
        scanStartedS = nil
        driftWarning = false
        try beginLeg()
        if estimator.aligned {
            state = .driving
            message = "route accepted"
            return
        }
        let location = try mapData.location(startLocationId ?? route.startLocationId)
        requestAnchor(location.markerId, text: "scan marker of " + location.name)
    }

    public func stop() {
        link.stop()
        state = .idle
        message = "stopped"
    }

    @discardableResult
    public func tick(nowS: Double, dtS: Double) -> ExecutorStatus {
        guard let activeRoute = route else {
            link.stop()
            return status()
        }

        if link.telemetry.bumper != nil {
            link.stop()
            state = .failed
            message = "bumper collision: clear the robot and restart the route"
            return status()
        }

        if obstacleAhead() {
            link.stop()
            state = .blocked
            let distance = link.telemetry.sonarCm ?? 0.0
            message = String(format: "obstacle at %.0f cm", distance)
            return status()
        }

        if state == .blocked {
            message = "path clear, resuming"
            state = estimator.aligned ? .driving : .needAnchor
        }

        if state == .arrived || state == .failed {
            link.stop()
            return status()
        }

        if !estimator.aligned || state == .needAnchor || state == .scanning {
            handleAnchorWait(nowS: nowS)
            return status()
        }

        if estimator.driftM > config.reanchorDriftM {
            if let nearby = reachableMarker() {
                requestAnchor(
                    nearby.id,
                    text: String(format: "dead-reckoning drift %.1f m: re-localise on %@", estimator.driftM, nearby.id)
                )
                handleAnchorWait(nowS: nowS)
                return status()
            }
            driftWarning = true
        }

        driveRoute(activeRoute)
        return status()
    }

    /// Called by the AR layer right after a successful marker alignment.
    public func noteMarker(_ markerId: String) {
        if !usedMarkers.contains(markerId) { usedMarkers.append(markerId) }
        if markerId == legArrivalMarkerId { legMarkerFixed = true }

        if state == .scanning {
            if markerId == expectedMarkerId {
                legIndex += 1
                pointIndex = 0
                try? beginLeg()
                state = .driving
                message = "re-localised on " + markerId
                scanStartedS = nil
            }
            return
        }
        if state == .needAnchor {
            state = .driving
            message = "localised on " + markerId
            scanStartedS = nil
        }
    }

    // ------------------------------------------------------------- internals

    private func beginLeg() throws {
        guard let activeRoute = route, legIndex < activeRoute.legs.count else {
            legArrivalMarkerId = nil
            legMarkerFixed = false
            return
        }
        let arrival = try mapData.location(activeRoute.legs[legIndex].toId)
        legArrivalMarkerId = arrival.markerId
        legMarkerFixed = false
    }

    private func driveRoute(_ activeRoute: Route) {
        guard legIndex < activeRoute.legs.count else {
            finish(activeRoute)
            return
        }
        let leg = activeRoute.legs[legIndex]
        let target = leg.path[pointIndex]
        guard let pose = estimator.pose else {
            state = .needAnchor
            return
        }
        let distance = pose.distanceTo(target)
        let lastPoint = pointIndex == leg.path.count - 1
        let lastLeg = legIndex == activeRoute.legs.count - 1
        let tolerance = (lastPoint && lastLeg) ? config.arrivalToleranceM : config.waypointToleranceM

        if distance <= tolerance {
            if !lastPoint {
                pointIndex += 1
                return
            }
            if !lastLeg {
                advanceLeg(activeRoute)
                return
            }
            finish(activeRoute)
            return
        }

        state = .driving
        message = String(format: "driving to waypoint %d, %.1f m", pointIndex, distance)
        steerTowards(target, pose: pose)
    }

    private func advanceLeg(_ activeRoute: Route) {
        let arrival = try? mapData.location(activeRoute.legs[legIndex].toId)
        if config.reanchorAtWaypoints, let markerId = arrival?.markerId, !legMarkerFixed {
            requestAnchor(markerId, text: "re-localise on marker of " + (arrival?.name ?? markerId))
            state = .scanning
            return
        }
        legIndex += 1
        pointIndex = 0
        try? beginLeg()
        state = .driving
    }

    private func finish(_ activeRoute: Route) {
        link.stop()
        state = .arrived
        message = "arrived at " + activeRoute.room.name
    }

    private func requestAnchor(_ markerId: String?, text: String) {
        link.stop()
        state = .needAnchor
        expectedMarkerId = markerId
        message = text
        scanStartedS = nil
    }

    private func handleAnchorWait(nowS: Double) {
        if expectedMarkerId == nil { expectedMarkerId = nearestMarkerId() }
        guard let wanted = expectedMarkerId else {
            link.stop()
            state = .failed
            message = "no marker available to localise"
            return
        }
        if scanStartedS == nil { scanStartedS = nowS }
        let elapsed = nowS - (scanStartedS ?? nowS)
        if elapsed > config.scanTimeoutS {
            link.stop()
            state = .failed
            message = String(format: "marker %@ not found within %.0f s", wanted, config.scanTimeoutS)
            return
        }
        let holding = facingWantedMarker() && elapsed < config.holdTimeoutS
        if holding {
            link.stop()
            message = "hold position, looking for marker " + wanted
        } else if config.allowScanRotation {
            link.drive(left: -config.scanSpeed, right: config.scanSpeed)
            message = "rotating to find marker " + wanted
        } else {
            link.stop()
            message = "waiting for marker " + wanted
        }
    }

    private func steerTowards(_ target: Pose2D, pose: Pose2D) {
        let error = pose.headingErrorTo(target)
        if abs(error) > config.headingToleranceDeg * Double.pi / 180.0 {
            if error > 0 {
                link.drive(left: -config.turnSpeed, right: config.turnSpeed)
            } else {
                link.drive(left: config.turnSpeed, right: -config.turnSpeed)
            }
            return
        }
        let steer = min(1.0, max(-1.0, config.steerGain * error))
        var left = config.cruiseSpeed * (1.0 - steer)
        var right = config.cruiseSpeed * (1.0 + steer)
        let scale = max(max(abs(left), abs(right)), 1e-6)
        if scale > 1.0 {
            left /= scale
            right /= scale
        }
        link.drive(left: left, right: right)
    }

    private func obstacleAhead() -> Bool {
        guard let sonar = link.telemetry.sonarCm else { return false }
        return state == .blocked ? sonar <= config.obstacleClearCm : sonar <= config.obstacleStopCm
    }

    private func markerPose(_ markerId: String?) -> Pose2D? {
        guard let markerId = markerId else { return nil }
        return mapData.markers.first { $0.id == markerId }?.pose
    }

    private func facingWantedMarker() -> Bool {
        guard let pose = estimator.pose, let marker = markerPose(expectedMarkerId) else { return false }
        return abs(pose.headingErrorTo(marker)) <= config.markerScanHeadingDeg * Double.pi / 180.0
    }

    private func reachableMarker() -> Marker? {
        guard let pose = estimator.pose else { return nil }
        let candidates = mapData.markers
            .filter { pose.distanceTo($0.pose) <= config.markerScanRadiusM }
            .sorted { pose.distanceTo($0.pose) < pose.distanceTo($1.pose) }
        return candidates.first
    }

    private func nearestMarkerId() -> String? {
        if let pose = estimator.pose, let location = mapData.nearestLocation(to: pose) {
            return location.markerId
        }
        guard let route = route, let start = try? mapData.location(route.startLocationId) else { return nil }
        return start.markerId
    }

    private func remainingDistance() -> Double {
        guard let activeRoute = route, let pose = estimator.pose, state != .arrived else { return 0.0 }
        var remaining = 0.0
        for index in legIndex..<activeRoute.legs.count {
            let leg = activeRoute.legs[index]
            let startIndex = index == legIndex ? pointIndex : 0
            var previous = index == legIndex ? pose : leg.path[0]
            for indexInLeg in startIndex..<leg.path.count {
                let point = leg.path[indexInLeg]
                remaining += previous.distanceTo(point)
                previous = point
            }
        }
        return remaining
    }

    public func status() -> ExecutorStatus {
        let pose = estimator.pose
        var target: Pose2D?
        var distanceToTarget = 0.0
        if let activeRoute = route, legIndex < activeRoute.legs.count {
            let leg = activeRoute.legs[legIndex]
            if pointIndex < leg.path.count {
                target = leg.path[pointIndex]
                if let pose = pose { distanceToTarget = pose.distanceTo(target!) }
            }
        }
        return ExecutorStatus(
            state: state,
            message: message,
            legIndex: legIndex,
            pointIndex: pointIndex,
            target: target,
            distanceToTargetM: distanceToTarget,
            distanceRemainingM: remainingDistance(),
            pose: pose,
            driftM: estimator.driftM,
            driftWarning: driftWarning,
            expectedMarkerId: expectedMarkerId,
            usedMarkers: usedMarkers
        )
    }
}
