import XCTest
@testable import OpenBotNavKit

final class ReturnRouteTests: XCTestCase {
    private func p(_ x: Double, _ y: Double = 0, _ yaw: Double = 0) -> Pose2D {
        .fromDeg(x: x, y: y, yawDeg: yaw)
    }
    private func map() throws -> RecordedMap {
        let poses = [p(0.4, 0, 30), p(0.8), p(2), p(2, 2, 90), p(3, 2)]
        let samples = poses.enumerated().map { TrajectorySample(pose: $1, timestampS: Double($0) / 30, startsSegment: $0 == 0) }
        return try RecordedMap.planned(name: "返程拐角", anchor: AnchorDefinition.templates[0],
            start: RecordedWaypoint(name: "起点", pose: poses[1], trajectoryIndex: 1),
            waypoints: [RecordedWaypoint(name: "节点1", pose: poses[3], trajectoryIndex: 3),
                        RecordedWaypoint(name: "节点2", pose: poses[4], trajectoryIndex: 4)],
            samples: samples, anchorStart: RecordedWaypoint(name: "支架出发位置", pose: poses[0], trajectoryIndex: 0))
    }

    func testReturnPrefixReversesCornersAndCorridorsWithoutChangingSavedMap() throws {
        let map = try map(), saved = try JSONEncoder().encode(map)
        let route = try RouteEntryPlanner.traversal(map: map, returningFrom: map.waypoints.last!.id)
        XCTAssertEqual(route.points, map.executionPoints.reversed())
        XCTAssertEqual(route.legIndices, map.executionLegIndices.reversed())
        XCTAssertEqual(route.points.last?.pose, p(0.4, 0, 30))
        XCTAssertEqual(try JSONDecoder().decode(RecordedMap.self, from: saved), map)
        XCTAssertTrue(route.points.contains { $0.isAutomatic == true })
    }

    func testReturnFromIntermediateNodeExcludesLaterNodes() throws {
        let map = try map(), node = map.waypoints[0]
        let route = try RouteEntryPlanner.traversal(map: map, returningFrom: node.id)
        XCTAssertEqual(route.points.first?.id, node.id)
        XCTAssertFalse(route.points.contains { $0.id == map.waypoints[1].id })
        XCTAssertEqual(route.points.last?.id, map.anchorStart?.id)
        XCTAssertEqual(route.points.filter { $0.isAutomatic != true }.map(\.id), [node.id, map.start.id, map.anchorStart!.id])
    }

    func testReturnEntryFromNearbyPosePreservesWallCornerAndManualNodes() throws {
        let map = try map(), pose = p(2.04, 1.8, 50)
        let route = try RouteEntryPlanner.plan(map: map, from: pose, returningFrom: map.waypoints[0].id)
        XCTAssertEqual(route.points.first?.pose, pose)
        XCTAssertEqual(route.points.last?.pose, map.executionStart.pose)
        XCTAssertEqual(route.legIndices.count, route.points.count - 1)
        for (index, pair) in zip(route.points, route.points.dropFirst()).enumerated() {
            let leg = map.routePlan!.legs[route.legIndices[index]]
            XCTAssertTrue(TrajectoryCorridor.containsSegment(from: pair.0.pose, to: pair.1.pose,
                centerline: leg.centerline(in: map.trajectory!), radius: leg.planningRadiusM))
        }
        XCTAssertGreaterThan(route.points.count, 3) // a direct chord cuts the corner
        XCTAssertEqual(route.points.filter { $0.isAutomatic != true }.dropFirst().map(\.id), [map.start.id, map.anchorStart!.id])
    }

    func testReturnEntryRejectsWrongNodeUnknownFloorAndUnsupportedMap() throws {
        let map = try map(), node = map.waypoints[0]
        for pose in [p(3, 2), p(2.2, 1.8), p(1, 1)] {
            XCTAssertFalse(RouteEntryPlanner.canEnter(map: map, from: pose, returningFrom: node.id))
            XCTAssertThrowsError(try RouteEntryPlanner.plan(map: map, from: pose, returningFrom: node.id))
        }
        XCTAssertThrowsError(try RouteEntryPlanner.traversal(map: map, returningFrom: UUID()))
        XCTAssertThrowsError(try RouteEntryPlanner.traversal(map: map, returningFrom: map.anchorStart!.id))
        let old = RecordedMap(name: "旧", anchor: map.anchor, start: map.start, waypoints: map.waypoints)
        let robot = MockRobotLink(), executor = WaypointExecutor(map: old, link: robot)
        XCTAssertThrowsError(try executor.start(at: old.waypoints.last!.pose, returningFrom: old.waypoints.last!.id))
        XCTAssertEqual(robot.commandCount, 0)
    }

    func testSimulatedReturnFromEachManualNodeEndsAtDeparturePoseInsideBand() throws {
        let map = try map()
        for source in [map.start] + map.waypoints {
            let robot = SimulatedRobotLink(pose: source.pose)
            let executor = WaypointExecutor(map: map, link: robot)
            try executor.start(at: source.pose, returningFrom: source.id)
            for step in 0..<18000 {
                robot.tick(dtS: 1.0 / 60)
                executor.tick(pose: robot.truePose, trackingNormal: true, nowS: Double(step) / 60)
                XCTAssertTrue(TrajectoryCorridor.contains(point: robot.truePose,
                    centerline: map.trajectory!.map(\.pose), radius: 0.15))
                if !executor.active { break }
            }
            XCTAssertEqual(executor.phase, .arrived, "\(source.name): \(executor.message)")
            XCTAssertLessThanOrEqual(robot.truePose.distanceTo(map.executionStart.pose), 0.03)
            XCTAssertLessThanOrEqual(abs(wrapDeg(robot.truePose.yawDeg - map.executionStart.pose.yawDeg)), 5)
            XCTAssertTrue(executor.message.contains("未执行图片重识别"))
        }
    }

    func testReturnInitialTurnUsesSavedPwmAndWaitsTwoSecondsBeforeForward() throws {
        let map = try map(), source = map.waypoints.last!
        let robot = MockRobotLink()
        var config = WaypointConfig(); config.leftTurnSpeed = 180.0 / 255; config.rightTurnSpeed = 140.0 / 255
        let executor = WaypointExecutor(map: map, link: robot, config: config)
        try executor.start(at: source.pose, returningFrom: source.id)
        executor.tick(pose: source.pose, trackingNormal: true, nowS: 0)
        XCTAssertLessThan(robot.lastLeft * robot.lastRight, 0)
        let aligned = p(source.pose.x, source.pose.y, 180)
        executor.tick(pose: aligned, trackingNormal: true, nowS: 0.3)
        executor.tick(pose: aligned, trackingNormal: true, nowS: 0.7)
        XCTAssertEqual(executor.phase, .waiting)
        executor.tick(pose: aligned, trackingNormal: true, nowS: 2.69)
        XCTAssertEqual(robot.lastLeft, 0); XCTAssertEqual(robot.lastRight, 0)
        executor.tick(pose: aligned, trackingNormal: true, nowS: 2.71)
        XCTAssertGreaterThan(robot.lastLeft, 0); XCTAssertGreaterThan(robot.lastRight, 0)
    }

    func testReturnTrackingLossAutomaticallyResumesCurrentTarget() throws {
        let map = try map(), source = map.waypoints.last!, robot = MockRobotLink()
        let executor = WaypointExecutor(map: map, link: robot)
        try executor.start(at: source.pose, returningFrom: source.id)
        executor.tick(pose: source.pose, trackingNormal: true, nowS: 0)
        let target = executor.target?.id, points = executor.points
        executor.tick(pose: nil, trackingNormal: false, nowS: 0.02)
        XCTAssertEqual(executor.phase, .recovering)
        let count = robot.commandCount
        for i in 0...6 { executor.tick(pose: source.pose, trackingNormal: true, nowS: 1 + Double(i) * 0.1) }
        XCTAssertEqual(executor.phase, .waiting)
        XCTAssertEqual(robot.commandCount, count)
        XCTAssertEqual(executor.target?.id, target); XCTAssertEqual(executor.points, points)
        executor.tick(pose: source.pose, trackingNormal: true, nowS: 3.7)
        XCTAssertEqual(executor.phase, .alignLine)
        XCTAssertLessThan(robot.lastLeft * robot.lastRight, 0)
        XCTAssertEqual(executor.recoveryCount, 1)
    }

    private func stable(_ executor: WaypointExecutor, pose: Pose2D, from time: Double) {
        for i in 0...6 { executor.tick(pose: pose, trackingNormal: true, nowS: time + Double(i) * 0.1) }
    }

    func testRecoveryNeedsContinuousStableFramesAndDoesNotDriveDuringConfirmation() throws {
        let map = try map(), pose = map.waypoints.last!.pose, robot = MockRobotLink()
        let executor = WaypointExecutor(map: map, link: robot)
        try executor.start(at: pose, returningFrom: map.waypoints.last!.id)
        executor.tick(pose: pose, trackingNormal: true, nowS: 0)
        executor.pauseForTracking(nowS: 0.1)
        executor.tick(pose: pose, trackingNormal: true, nowS: 1)
        executor.tick(pose: pose, trackingNormal: true, nowS: 2) // isolated frames do not suffice
        XCTAssertEqual(executor.phase, .recovering)
        stable(executor, pose: pose, from: 2.1)
        XCTAssertEqual(executor.phase, .waiting)
        XCTAssertEqual(robot.lastLeft, 0); XCTAssertEqual(robot.lastRight, 0)
    }

    func testDiscontinuousWorldPoseNeverResumesAndTimesOut() throws {
        let map = try map(), pose = map.waypoints.last!.pose, robot = MockRobotLink()
        let executor = WaypointExecutor(map: map, link: robot)
        try executor.start(at: pose, returningFrom: map.waypoints.last!.id)
        executor.tick(pose: pose, trackingNormal: true, nowS: 0)
        executor.pauseForTracking(nowS: 0.1)
        stable(executor, pose: p(pose.x + 1, pose.y), from: 1)
        XCTAssertEqual(executor.phase, .recovering)
        executor.tick(pose: p(pose.x + 1, pose.y), trackingNormal: true, nowS: 15.2)
        XCTAssertEqual(executor.phase, .interrupted)
        XCTAssertEqual(robot.lastLeft, 0); XCTAssertEqual(robot.lastRight, 0)
        stable(executor, pose: pose, from: 16)
        XCTAssertEqual(executor.phase, .interrupted)
    }

    func testManualStopOrDisconnectCancelsPendingRecovery() throws {
        let map = try map(), pose = map.waypoints.last!.pose
        for disconnect in [false, true] {
            let robot = MockRobotLink()
            let actual = WaypointExecutor(map: map, link: robot)
            try actual.start(at: pose, returningFrom: map.waypoints.last!.id)
            actual.tick(pose: pose, trackingNormal: true, nowS: 0)
            actual.pauseForTracking(nowS: 0.1)
            if disconnect { actual.tick(pose: nil, trackingNormal: false, linkAvailable: false, nowS: 0.2) }
            else { actual.stop() }
            stable(actual, pose: pose, from: 1)
            XCTAssertEqual(actual.phase, .interrupted)
            XCTAssertEqual(robot.lastLeft, 0); XCTAssertEqual(robot.lastRight, 0)
        }
    }

    func testThreeRecoveryAttemptsPerTargetAreBounded() throws {
        let map = try map(), pose = map.waypoints.last!.pose, robot = MockRobotLink()
        let executor = WaypointExecutor(map: map, link: robot)
        try executor.start(at: pose, returningFrom: map.waypoints.last!.id)
        executor.tick(pose: pose, trackingNormal: true, nowS: 0)
        for i in 0..<3 {
            let time = Double(i) * 2 + 0.1
            executor.pauseForTracking(nowS: time)
            stable(executor, pose: pose, from: time + 0.1)
            XCTAssertEqual(executor.phase, .waiting)
        }
        executor.pauseForTracking(nowS: 6.2)
        XCTAssertEqual(executor.phase, .interrupted)
        XCTAssertEqual(executor.recoveryCount, 3)
    }

    func testRecoveryPreservesNodeHeadingStageAndNeverRechecksPositionArrival() throws {
        let map = try map(), source = map.waypoints.last!, robot = MockRobotLink()
        let executor = WaypointExecutor(map: map, link: robot)
        try executor.start(at: source.pose, returningFrom: source.id)
        let node = map.waypoints[0], arrived = p(node.pose.x, node.pose.y)
        executor.tick(pose: arrived, trackingNormal: true, nowS: 0)
        executor.tick(pose: arrived, trackingNormal: true, nowS: 2)
        XCTAssertEqual(executor.phase, .alignNode)
        executor.pauseForTracking(nowS: 2.1)
        let offset = p(arrived.x + 0.1, arrived.y + 0.05)
        stable(executor, pose: offset, from: 3)
        executor.tick(pose: offset, trackingNormal: true, nowS: 5.7)
        XCTAssertEqual(executor.phase, .alignNode)
        XCTAssertEqual(executor.target?.id, node.id)
    }

    func testHeadingJumpWaitsForContinuityThenRecomputesLiveLineBearing() throws {
        let map = try map(), source = map.waypoints.last!, robot = MockRobotLink()
        let executor = WaypointExecutor(map: map, link: robot)
        try executor.start(at: source.pose, returningFrom: source.id)
        executor.tick(pose: source.pose, trackingNormal: true, nowS: 0)
        executor.tick(pose: p(source.pose.x, source.pose.y, 90), trackingNormal: true, nowS: 0.02)
        XCTAssertEqual(executor.phase, .recovering)
        let recovered = p(source.pose.x, source.pose.y + 0.08, 5)
        stable(executor, pose: recovered, from: 1)
        executor.tick(pose: recovered, trackingNormal: true, nowS: 3.7)
        XCTAssertEqual(executor.phase, .alignLine)
        XCTAssertEqual(executor.headingErrorDeg, recovered.headingErrorTo(executor.target!.pose) * 180 / .pi, accuracy: 1e-8)
    }

    func testRecoveredPoseStillCannotTranslateOutsideOriginalCorridor() throws {
        let map = try map(), source = map.waypoints.last!, robot = MockRobotLink()
        let executor = WaypointExecutor(map: map, link: robot)
        let initial = p(source.pose.x, source.pose.y, 180)
        try executor.start(at: initial, returningFrom: source.id)
        executor.tick(pose: initial, trackingNormal: true, nowS: 0)
        executor.pauseForTracking(nowS: 0.1)
        let outside = p(initial.x, initial.y + 0.2, 180)
        stable(executor, pose: outside, from: 1)
        executor.tick(pose: outside, trackingNormal: true, nowS: 3.7)
        let aligned = Pose2D(x: outside.x, y: outside.y, yawRad: outside.bearingTo(executor.target!.pose))
        executor.tick(pose: aligned, trackingNormal: true, nowS: 4)
        executor.tick(pose: aligned, trackingNormal: true, nowS: 4.4)
        executor.tick(pose: aligned, trackingNormal: true, nowS: 6.5)
        XCTAssertEqual(executor.phase, .interrupted)
        XCTAssertTrue(executor.message.contains("带状"))
        XCTAssertEqual(robot.lastLeft, 0); XCTAssertEqual(robot.lastRight, 0)
    }

    func testSlowPoseDriftDoesNotPassRecoveryStabilityWindow() throws {
        let map = try map(), source = map.waypoints.last!, robot = MockRobotLink()
        let executor = WaypointExecutor(map: map, link: robot)
        try executor.start(at: source.pose, returningFrom: source.id)
        executor.tick(pose: source.pose, trackingNormal: true, nowS: 0)
        executor.pauseForTracking(nowS: 0.1)
        for i in 0..<10 {
            executor.tick(pose: p(source.pose.x, source.pose.y, Double(i) * 2), trackingNormal: true, nowS: 1 + Double(i) * 0.1)
        }
        XCTAssertEqual(executor.phase, .recovering)
        XCTAssertEqual(robot.lastLeft, 0); XCTAssertEqual(robot.lastRight, 0)
        stable(executor, pose: p(source.pose.x, source.pose.y, 18), from: 2)
        XCTAssertEqual(executor.phase, .waiting)
    }

    func testSimulatedFullReturnCompletesAfterLossDuringTurnDriveAndNodeHeading() throws {
        let map = try map(), source = map.waypoints.last!
        let robot = SimulatedRobotLink(pose: source.pose)
        let executor = WaypointExecutor(map: map, link: robot)
        try executor.start(at: source.pose, returningFrom: source.id)
        var injected = Set<WaypointPhase>(), lostUntil = -1.0
        let wanted: Set<WaypointPhase> = [.alignLine, .driveLine, .alignNode]
        for step in 0..<24000 {
            let time = Double(step) / 60
            robot.tick(dtS: 1.0 / 60)
            if wanted.contains(executor.phase), !injected.contains(executor.phase) {
                injected.insert(executor.phase); lostUntil = time + 0.4
            }
            executor.tick(pose: time < lostUntil ? nil : robot.truePose, trackingNormal: time >= lostUntil, nowS: time)
            XCTAssertTrue(TrajectoryCorridor.contains(point: robot.truePose, centerline: map.trajectory!.map(\.pose), radius: 0.15))
            if !executor.active { break }
        }
        XCTAssertEqual(injected, wanted)
        XCTAssertEqual(executor.phase, .arrived, executor.message)
        XCTAssertEqual(executor.recoveryCount, 3)
        XCTAssertLessThanOrEqual(robot.truePose.distanceTo(map.executionStart.pose), 0.03)
        XCTAssertLessThanOrEqual(abs(wrapDeg(robot.truePose.yawDeg - map.executionStart.pose.yawDeg)), 5)
    }
}
