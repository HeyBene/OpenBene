import XCTest
@testable import OpenBotNavKit

final class NavigationStabilityTests: XCTestCase {
    private func p(_ x: Double, _ y: Double = 0, _ degrees: Double = 0) -> Pose2D {
        .fromDeg(x: x, y: y, yawDeg: degrees)
    }
    private func map(_ poses: [Pose2D], manual: [Int]? = nil) throws -> RecordedMap {
        let samples = poses.enumerated().map { TrajectorySample(pose: $1, timestampS: Double($0) / 30, startsSegment: $0 == 0) }
        return try RecordedMap.planned(name: "支架测试", anchor: AnchorDefinition.templates[0],
            start: RecordedWaypoint(name: "起点", pose: poses[0], trajectoryIndex: 0),
            waypoints: (manual ?? [poses.count - 1]).map { RecordedWaypoint(name: "节点\($0)", pose: poses[$0], trajectoryIndex: $0) },
            samples: samples)
    }
    private func turn(_ c: inout SettledTurnController, _ degrees: Double, _ time: Double, yaw: Double = 0) -> SettledTurnAction {
        c.update(errorRad: degrees * .pi / 180, yawRad: yaw * .pi / 180, nowS: time,
                 toleranceDeg: 3, leftSpeed: 160.0 / 255, rightSpeed: 180.0 / 255)
    }
    private func driving(_ action: SettledTurnAction) -> Bool { if case .drive = action { return true }; return false }

    func testDownwardScanCannotInventRobotHeading() {
        for pitch in [-89.0, -90, -91] {
            let camera = RigidTransform.fromYawPitchRoll(position: (0, 0.5, 0), pitchDeg: pitch)
            XCTAssertNil(MarkerGeometry.navigationDeviceInAr(cameraPose: camera))
        }
        let mount = RigidTransform.fromYawPitchRoll(position: (0, 0.5, 0), yawDeg: 30, pitchDeg: -40)
        XCTAssertEqual(MarkerGeometry.navigationDeviceInAr(cameraPose: mount), MarkerGeometry.deviceInAr(cameraPose: mount))
    }

    func testAnchorRequiresStableDurationRatherThanFirstFrame() throws {
        var alignment = StableAnchorAlignment()
        for i in 0..<30 {
            XCTAssertNil(alignment.observe(p(1, 2, 179), timestampS: Double(i) / 60))
        }
        let pose = try XCTUnwrap(alignment.observe(p(1, 2, -179), timestampS: 0.5))
        XCTAssertEqual(pose.x, 1, accuracy: 1e-9)
        XCTAssertLessThan(abs(wrapDeg(pose.yawDeg - 180)), 1.1)
    }

    func testAnchorOutlierAndMissingFramesRestartConfirmation() {
        var alignment = StableAnchorAlignment()
        for i in 0..<20 { _ = alignment.observe(p(0), timestampS: Double(i) / 60) }
        XCTAssertNil(alignment.observe(p(0.2), timestampS: 0.34))
        XCTAssertNil(alignment.observe(p(0.2), timestampS: 1))
        for i in 1..<30 { XCTAssertNil(alignment.observe(p(0.2), timestampS: 1 + Double(i) / 60)) }
        XCTAssertNotNil(alignment.observe(p(0.2), timestampS: 1.51))
    }

    func testRecordedDepartureCanBeBesideImageRatherThanOverItsCenter() throws {
        let samples = [TrajectorySample(pose: p(0.5), timestampS: 0, startsSegment: true),
                       TrajectorySample(pose: p(1), timestampS: 0.1, startsSegment: false),
                       TrajectorySample(pose: p(2), timestampS: 0.2, startsSegment: false)]
        let route = try RecordedMap.planned(name: "支架出发", anchor: AnchorDefinition.templates[0],
            start: RecordedWaypoint(name: "起点", pose: samples[1].pose, trajectoryIndex: 1),
            waypoints: [RecordedWaypoint(name: "终点", pose: samples[2].pose, trajectoryIndex: 2)], samples: samples,
            anchorStart: RecordedWaypoint(name: "支架处", pose: samples[0].pose, trajectoryIndex: 0))
        try route.validate()
        XCTAssertEqual(route.executionStart.pose, p(0.5))
    }

    func testCurrentPoseFurtherThanTenCMCanEnterWithoutMovingPhone() throws {
        let route = try map([p(0), p(2)])
        let current = p(0.5, 0.04, 30)
        XCTAssertTrue(RouteEntryPlanner.canEnter(map: route, from: current))
        let entry = try RouteEntryPlanner.plan(map: route, from: current)
        XCTAssertEqual(entry.points.first?.pose, current)
        XCTAssertEqual(entry.points.last?.id, route.waypoints.last?.id)
        XCTAssertEqual(entry.points.count, 2)
        let robot = MockRobotLink()
        let executor = WaypointExecutor(map: route, link: robot)
        try executor.start(at: current)
        XCTAssertEqual(executor.points.first?.pose, current)
        XCTAssertEqual(robot.commandCount, 0)
        executor.tick(pose: current, trackingNormal: true, nowS: 0)
        XCTAssertGreaterThan(robot.lastLeft, 0)
        XCTAssertLessThan(robot.lastRight, 0)
    }

    func testEntryPreservesCornerAndAllManualNodes() throws {
        let route = try map([p(0), p(0.5), p(0.5, 1), p(1.5, 1)], manual: [2, 3])
        let current = p(0.25, 0.04)
        let entry = try RouteEntryPlanner.plan(map: route, from: current)
        let first = route.routePlan!.legs[0], line = first.centerline(in: route.trajectory!)
        XCTAssertEqual(entry.legIndices.count, entry.points.count - 1)
        XCTAssertEqual(entry.points.filter { $0.isAutomatic != true }.dropFirst().map { $0.id }, route.waypoints.map { $0.id })
        for (index, pair) in zip(entry.points, entry.points.dropFirst()).enumerated() where entry.legIndices[index] == 0 {
            XCTAssertTrue(TrajectoryCorridor.containsSegment(from: pair.0.pose, to: pair.1.pose, centerline: line, radius: first.planningRadiusM))
        }
        XCTAssertFalse(TrajectoryCorridor.containsSegment(from: current, to: p(0.5, 1), centerline: line, radius: 0.15))
    }

    func testEntryRejectsUnknownFloorAndLaterLeg() throws {
        let route = try map([p(0), p(1), p(1, 1)], manual: [1, 2])
        for pose in [p(0.2, 0.16), p(1, 0.5), p(-1)] {
            XCTAssertFalse(RouteEntryPlanner.canEnter(map: route, from: pose))
            XCTAssertThrowsError(try RouteEntryPlanner.plan(map: route, from: pose))
        }
    }

    func testPWMReversalHasActualZeroAndTwoSecondPause() {
        var c = SettledTurnController()
        XCTAssertTrue(driving(turn(&c, 8, 0, yaw: -8)))
        XCTAssertFalse(driving(turn(&c, -8, 0.04, yaw: 8)))
        XCTAssertFalse(driving(turn(&c, -8, 0.4, yaw: 8)))
        XCTAssertFalse(driving(turn(&c, -8, 2.039, yaw: 8)))
        let result = turn(&c, -8, 2.05, yaw: 8)
        XCTAssertEqual(result, .drive(left: 180.0 / 255, right: -180.0 / 255))
    }

    func testSmallErrorUsesShortPulseThenStopsAtConfiguredPWM() {
        var c = SettledTurnController()
        XCTAssertEqual(turn(&c, 8, 0), .drive(left: -160.0 / 255, right: 160.0 / 255))
        XCTAssertFalse(driving(turn(&c, 7, 0.05)))
        XCTAssertFalse(driving(turn(&c, 7, 0.29)))
        XCTAssertTrue(driving(turn(&c, 6, 0.31)))
    }

    func testHeadingRequiresSettledHoldAndHasHysteresis() {
        var c = SettledTurnController()
        XCTAssertFalse(driving(turn(&c, 2, 0)))
        XCTAssertNotEqual(turn(&c, -2, 0.2), .aligned)
        XCTAssertEqual(turn(&c, 4, 0.36), .aligned)
        c.reset()
        XCTAssertNotEqual(turn(&c, 2, 1), .aligned)
        XCTAssertFalse(driving(turn(&c, 8, 1.1)))
        XCTAssertTrue(driving(turn(&c, 8, 1.26)))
    }

    func testNoImprovementOrYawJumpStopsRatherThanSpinsForever() {
        var c = SettledTurnController()
        _ = turn(&c, 45, 0)
        if case .failed = turn(&c, 45, 8.01) {} else { XCTFail("stalled turn must stop") }
        c.reset()
        _ = turn(&c, 45, 0, yaw: 0)
        if case .failed = turn(&c, 45, 0.02, yaw: 179) {} else { XCTFail("jump must stop") }
    }

    func testAngleWrapAcrossPiDoesNotTriggerJump() {
        var c = SettledTurnController()
        _ = turn(&c, 20, 0, yaw: 179)
        if case .failed = turn(&c, 18, 0.02, yaw: -179) { XCTFail("two degree change is continuous") }
    }

    func testSlowLargeTurnWithFrameNoiseDoesNotExhaustRotationLimit() {
        for sign in [-1.0, 1] {
            var controller = SettledTurnController(), aligned = false
            for i in 0..<1800 {
                let time = Double(i) / 60
                let yaw = sign * min(174, time * 12) + (i % 2 == 0 ? 0.4 : -0.4)
                let action = turn(&controller, sign * 174 - yaw, time, yaw: yaw)
                if case .failed(let reason) = action { XCTFail(reason); break }
                if case .aligned = action { aligned = true; break }
            }
            XCTAssertTrue(aligned)
            XCTAssertLessThan(controller.diagnostics["rotationDeg"] ?? .infinity, 190)
        }
    }

    func testBackslideThenLocalImprovementIsNotMistakenForEightSecondStall() {
        var controller = SettledTurnController()
        let samples: [(Double, Double)] = [(0, 10), (1, 4), (2.9, 40), (4, 30), (6, 20), (8.5, 10), (9.5, 6), (10, 2)]
        for (time, error) in samples {
            if case .failed(let reason) = turn(&controller, error, time, yaw: -error) { XCTFail(reason) }
        }
        XCTAssertEqual(turn(&controller, 2, 10.4, yaw: -2), .aligned)
    }

    func testRealLargeExcursionsStillStopAtRotationLimit() {
        var controller = SettledTurnController(), failed = false
        for i in 0..<6 {
            let yaw = i % 2 == 0 ? -40.0 : 40
            if case .failed(let reason) = turn(&controller, -yaw, Double(i), yaw: yaw) {
                XCTAssertTrue(reason.contains("270°")); failed = true; break
            }
        }
        XCTAssertTrue(failed)
    }

    func testTimeLimitStillStopsEvenWithSlowContinuousProgress() {
        var controller = SettledTurnController(), failed = false
        for i in 0..<2800 {
            let time = Double(i) / 60, yaw = time / 2
            if case .failed(let reason) = turn(&controller, 90 - yaw, time, yaw: yaw) {
                XCTAssertTrue(reason.contains("45秒")); failed = true; break
            }
        }
        XCTAssertTrue(failed)
    }

    func testManualStopCancelsTrackingRecoveryWithoutAnotherPulse() throws {
        let route = try map([p(0), p(2)])
        let robot = MockRobotLink()
        let executor = WaypointExecutor(map: route, link: robot)
        try executor.start(at: p(0, 0, 30))
        executor.tick(pose: p(0, 0, 30), trackingNormal: true, nowS: 0)
        executor.tick(pose: nil, trackingNormal: false, nowS: 0.02)
        XCTAssertEqual(executor.phase, .recovering)
        executor.stop()
        XCTAssertEqual(executor.phase, .interrupted)
        executor.tick(pose: p(0, 0, 30), trackingNormal: true, nowS: 3)
        XCTAssertEqual(executor.phase, .interrupted)
        XCTAssertEqual(robot.lastLeft, 0)
    }
    func testNodeHeadingCompletesWithoutRecheckingCameraPosition() throws {
        let route = try map([p(0), p(1, 0, 90)])
        let robot = MockRobotLink()
        let executor = WaypointExecutor(map: route, link: robot)
        try executor.start(at: p(0))
        executor.tick(pose: p(0), trackingNormal: true, nowS: 0)
        executor.tick(pose: p(0), trackingNormal: true, nowS: 0.4)
        executor.tick(pose: p(0), trackingNormal: true, nowS: 2.4)
        executor.tick(pose: p(1), trackingNormal: true, nowS: 3)
        executor.tick(pose: p(1), trackingNormal: true, nowS: 5)
        // Position was confirmed before the turn. Camera motion around a
        // stationary pivot must not restart position control or reject the yaw.
        executor.tick(pose: p(0.97, 0.1, 30), trackingNormal: true, nowS: 5.2)
        executor.tick(pose: p(0.9, 0.17, 60), trackingNormal: true, nowS: 5.4)
        executor.tick(pose: p(0.8, 0.2, 90), trackingNormal: true, nowS: 5.6)
        executor.tick(pose: p(0.8, 0.2, 90), trackingNormal: true, nowS: 6)
        XCTAssertEqual(executor.phase, .arrived)
        XCTAssertEqual(executor.headingErrorDeg, 0, accuracy: 1e-9)
        XCTAssertEqual(robot.lastLeft, 0)
        XCTAssertEqual(robot.lastRight, 0)
    }

    func testTurnConvergesWithAsymmetricMotorResponseAndInertia() {
        for goal in [-160.0, 95.0] {
            var controller = SettledTurnController()
            var yaw = 0.0, rate = 0.0, requestedRate = 0.0
            var commands: [(at: Double, value: Double)] = []
            var aligned = false
            let dt = 1.0 / 60
            for frame in 0..<2700 {
                let time = Double(frame) * dt
                let error = wrapDeg(goal - yaw)
                let decision = turn(&controller, error, time, yaw: yaw)
                let request: Double
                switch decision {
                case .drive(let left, let right): request = (right - left) * 70
                case .aligned: aligned = true; request = 0
                case .failed(let reason): XCTFail("\(goal): \(reason)"); request = 0
                case .hold: request = 0
                }
                commands.append((time + 0.04, request))
                while let first = commands.first, first.at <= time {
                    requestedRate = first.value; commands.removeFirst()
                }
                rate += (requestedRate - rate) * dt / 0.18
                yaw = wrapDeg(yaw + rate * dt)
                if aligned { break }
                if case .failed = decision { break }
            }
            XCTAssertTrue(aligned, "target \(goal), actual \(yaw)")
            XCTAssertLessThanOrEqual(abs(wrapDeg(goal - yaw)), 5)
        }
    }

    func testTurnPulseExpiresEvenWithoutAnotherARFrame() throws {
        let route = try map([p(0), p(2)])
        let robot = MockRobotLink(), stopped = expectation(description: "pulse expires")
        let executor = WaypointExecutor(map: route, link: robot)
        try executor.start(at: p(0, 0, 8))
        executor.tick(pose: p(0, 0, 8), trackingNormal: true, nowS: 0)
        XCTAssertNotEqual(robot.lastLeft, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            XCTAssertEqual(robot.lastLeft, 0)
            XCTAssertEqual(robot.lastRight, 0)
            stopped.fulfill()
        }
        wait(for: [stopped], timeout: 1)
        executor.stop()
    }

    func testCancelledPulseTimerCannotStopRestartedStraightStage() throws {
        let route = try map([p(0), p(2)])
        let robot = MockRobotLink(), checked = expectation(description: "stale pulse cancelled")
        let executor = WaypointExecutor(map: route, link: robot)
        try executor.start(at: p(0, 0, 8))
        executor.tick(pose: p(0, 0, 8), trackingNormal: true, nowS: 0)
        executor.stop()
        try executor.start(at: p(0))
        executor.tick(pose: p(0), trackingNormal: true, nowS: 10)
        executor.tick(pose: p(0), trackingNormal: true, nowS: 10.4)
        executor.tick(pose: p(0), trackingNormal: true, nowS: 12.4)
        XCTAssertGreaterThan(robot.lastLeft, 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            XCTAssertGreaterThan(robot.lastLeft, 0)
            XCTAssertGreaterThan(robot.lastRight, 0)
            checked.fulfill()
        }
        wait(for: [checked], timeout: 1)
        executor.stop()
    }

    func testNoPositionProgressStopsAcrossTurnAndDriveStages() throws {
        let route = try map([p(0), p(2)])
        let robot = MockRobotLink()
        let executor = WaypointExecutor(map: route, link: robot)
        try executor.start(at: p(0))
        executor.tick(pose: p(0), trackingNormal: true, nowS: 0)
        executor.tick(pose: p(0), trackingNormal: true, nowS: 0.4)
        executor.tick(pose: p(0), trackingNormal: true, nowS: 2.4)
        for time in 3...31 { executor.tick(pose: p(0), trackingNormal: true, nowS: Double(time)) }
        XCTAssertEqual(executor.phase, .interrupted)
        XCTAssertTrue(executor.message.contains("30秒"))
        XCTAssertEqual(robot.lastLeft, 0)
        XCTAssertEqual(robot.lastRight, 0)
    }

    func testCameraMovedByNodeRotationCannotDriveOutsideNextCorridor() throws {
        let route = try map([p(0), p(1, 0, 90), p(1, 2, 90)], manual: [1, 2])
        let robot = MockRobotLink()
        let executor = WaypointExecutor(map: route, link: robot)
        try executor.start(at: p(0))
        for (time, pose) in [(0.0, p(0)), (0.4, p(0)), (2.4, p(0)), (3.0, p(1)),
                             (5.0, p(1)), (5.2, p(0.97, 0.1, 30)), (5.4, p(0.9, 0.17, 60)),
                             (5.6, p(0.8, 0.2, 90)), (6.0, p(0.8, 0.2, 90))] {
            executor.tick(pose: pose, trackingNormal: true, nowS: time)
        }
        XCTAssertEqual(executor.waypointIndex, 1) // heading completes normally
        executor.tick(pose: p(0.8, 0.2, 90), trackingNormal: true, nowS: 8)
        executor.tick(pose: p(0.8, 0.2, 84), trackingNormal: true, nowS: 8.2)
        executor.tick(pose: p(0.8, 0.2, 84), trackingNormal: true, nowS: 8.6)
        executor.tick(pose: p(0.8, 0.2, 84), trackingNormal: true, nowS: 10.6)
        XCTAssertEqual(executor.phase, .interrupted)
        XCTAssertTrue(executor.message.contains("带状范围"))
        XCTAssertEqual(robot.lastLeft, 0)
        XCTAssertEqual(robot.lastRight, 0)
    }

}
