import XCTest
@testable import OpenBotNavKit

final class WaypointExecutorTests: XCTestCase {
    private func oneNode(start: Pose2D = Pose2D(x: 0, y: 0), target: Pose2D = .fromDeg(x: 1, y: 0, yawDeg: 90)) -> RecordedMap {
        RecordedMap(name: "直线", anchor: AnchorDefinition.templates[0],
                    start: RecordedWaypoint(name: "起点", pose: start),
                    waypoints: [RecordedWaypoint(name: "终点", pose: target)])
    }

    func testReachingPositionDoesNotFinishBeforeFinalHeading() throws {
        let link = MockRobotLink()
        let executor = WaypointExecutor(map: oneNode(), link: link)
        try executor.start(at: Pose2D(x: 0, y: 0))
        executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, nowS: 0)
        executor.tick(pose: Pose2D(x: 0.25, y: 0), trackingNormal: true, nowS: 2)
        XCTAssertGreaterThan(link.lastLeft, 0)
        XCTAssertEqual(link.lastLeft, link.lastRight)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(link.lastLeft), 160)
        // Just outside the arrival radius still needs enough PWM to move.
        executor.tick(pose: Pose2D(x: 0.69, y: 0), trackingNormal: true, nowS: 2.1)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(link.lastLeft), 160)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(link.lastRight), 160)
        executor.tick(pose: Pose2D(x: 1, y: 0), trackingNormal: true, nowS: 3)
        XCTAssertEqual(executor.phase, .waiting)
        XCTAssertEqual(link.lastLeft, 0)
        executor.tick(pose: Pose2D(x: 1, y: 0), trackingNormal: true, nowS: 4.999)
        XCTAssertEqual(executor.phase, .waiting)
        XCTAssertEqual(link.lastLeft, 0)
        XCTAssertEqual(link.lastRight, 0)
        executor.tick(pose: Pose2D(x: 1, y: 0), trackingNormal: true, nowS: 5)
        XCTAssertEqual(executor.phase, .alignNode)
        XCTAssertLessThan(link.lastLeft, 0)
        XCTAssertGreaterThan(link.lastRight, 0)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(link.lastLeft), -160)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(link.lastRight), 160)
        executor.tick(pose: .fromDeg(x: 1, y: 0, yawDeg: 90), trackingNormal: true, nowS: 5.1)
        XCTAssertEqual(executor.phase, .arrived)
        XCTAssertEqual(link.lastLeft, 0)
        XCTAssertEqual(link.lastRight, 0)
    }

    func testWrongStartingPositionNeverDrives() {
        let link = MockRobotLink()
        let executor = WaypointExecutor(map: oneNode(), link: link)
        XCTAssertThrowsError(try executor.start(at: Pose2D(x: 3, y: 0)))
        XCTAssertEqual(link.commandCount, 0)
        XCTAssertEqual(link.lastLeft, 0)
    }

    func testInitialHeadingIsAdjustedBeforeTranslation() throws {
        let link = MockRobotLink()
        let start = Pose2D.fromDeg(x: 0, y: 0, yawDeg: 90)
        let executor = WaypointExecutor(map: oneNode(start: start), link: link)
        try executor.start(at: start)
        executor.tick(pose: start, trackingNormal: true, nowS: 0)
        XCTAssertEqual(executor.phase, .alignLine)
        XCTAssertGreaterThan(link.lastLeft, 0)
        XCTAssertEqual(link.lastLeft, -link.lastRight)
        executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, nowS: 1)
        XCTAssertEqual(executor.phase, .waiting)
        XCTAssertEqual(link.lastLeft, 0)
        executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, nowS: 2.999)
        XCTAssertEqual(executor.phase, .waiting)
        XCTAssertEqual(link.lastLeft, 0)
        XCTAssertEqual(link.lastRight, 0)
        executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, nowS: 3)
        XCTAssertEqual(executor.phase, .driveLine)
        XCTAssertGreaterThan(link.lastLeft, 0)
    }

    func testTrackingLossStopsAndDoesNotAutomaticallyResume() throws {
        let link = MockRobotLink()
        let executor = WaypointExecutor(map: oneNode(), link: link)
        try executor.start(at: Pose2D(x: 0, y: 0))
        executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, nowS: 0)
        executor.tick(pose: Pose2D(x: 0.1, y: 0), trackingNormal: true, nowS: 2)
        XCTAssertGreaterThan(link.lastLeft, 0)
        executor.tick(pose: nil, trackingNormal: false, nowS: 2.1)
        XCTAssertEqual(executor.phase, .interrupted)
        XCTAssertEqual(link.lastLeft, 0)
        executor.tick(pose: Pose2D(x: 0.1, y: 0), trackingNormal: true, nowS: 5)
        XCTAssertEqual(executor.phase, .interrupted)
        XCTAssertEqual(link.lastLeft, 0)
    }

    func testDisconnectAndObstacleStopExecution() throws {
        for obstacle in [false, true] {
            let link = MockRobotLink()
            var config = WaypointConfig()
            config.sonarInstalled = true
            let executor = WaypointExecutor(map: oneNode(), link: link, config: config)
            try executor.start(at: Pose2D(x: 0, y: 0))
            if obstacle { link.telemetry.sonarCm = 10 }
            executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, linkAvailable: obstacle)
            XCTAssertEqual(executor.phase, obstacle ? .blocked : .interrupted)
            XCTAssertEqual(link.lastLeft, 0)
            XCTAssertEqual(link.lastRight, 0)
        }
    }

    func testSamePositionCanExecuteOnlyAnOrientationChange() throws {
        let map = oneNode(target: .fromDeg(x: 0, y: 0, yawDeg: 90))
        let link = MockRobotLink()
        let executor = WaypointExecutor(map: map, link: link)
        try executor.start(at: Pose2D(x: 0, y: 0))
        executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, nowS: 0)
        executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, nowS: 2)
        XCTAssertEqual(executor.phase, .alignNode)
        XCTAssertEqual(link.lastLeft, -link.lastRight)
        executor.tick(pose: .fromDeg(x: 0, y: 0, yawDeg: 90), trackingNormal: true, nowS: 2.1)
        XCTAssertEqual(executor.phase, .arrived)
    }

    func testHeadingAcrossPiBoundaryDoesNotTurnAFullCircle() throws {
        let current = Pose2D.fromDeg(x: 0, y: 0, yawDeg: 179)
        let map = oneNode(start: current, target: .fromDeg(x: 0, y: 0, yawDeg: -179))
        let link = MockRobotLink()
        let executor = WaypointExecutor(map: map, link: link)
        try executor.start(at: current)
        executor.tick(pose: current, trackingNormal: true, nowS: 0)
        executor.tick(pose: current, trackingNormal: true, nowS: 2)
        XCTAssertEqual(executor.phase, .arrived)
        XCTAssertEqual(link.lastLeft, 0)
    }

    private final class TracedRobot: RobotLink {
        let robot: SimulatedRobotLink
        var telemetry: Telemetry { robot.telemetry }
        var movingPairs: [(Double, Double)] = []
        var lastLeft = 0.0
        var lastRight = 0.0
        init(pose: Pose2D) { robot = SimulatedRobotLink(pose: pose) }
        func drive(left: Double, right: Double) {
            lastLeft = left; lastRight = right
            movingPairs.append((left, right)); robot.drive(left: left, right: right)
        }
        func stop() { lastLeft = 0; lastRight = 0; robot.stop() }
        func close() { robot.close() }
    }

    func testSequenceArrivesAtEveryRecordedNodeAndHeading() throws {
        let map = RecordedTestSupport.map()
        let link = TracedRobot(pose: map.start.pose)
        let executor = WaypointExecutor(map: map, link: link)
        try executor.start(at: link.robot.truePose)
        var phases = Set<WaypointPhase>()
        var visitedFirst = false
        var waitStartedS: Double?
        for step in 0..<8000 {
            let previousIndex = executor.waypointIndex
            let previousPhase = executor.phase
            let now = Double(step) * 0.03
            link.robot.tick(dtS: 0.03)
            executor.tick(pose: link.robot.truePose, trackingNormal: true, nowS: now)
            if executor.phase == .waiting {
                if previousPhase != .waiting { waitStartedS = now }
                XCTAssertEqual(link.lastLeft, 0)
                XCTAssertEqual(link.lastRight, 0)
            } else if let started = waitStartedS {
                XCTAssertGreaterThanOrEqual(now - started, 2)
                waitStartedS = nil
            }
            phases.insert(executor.phase)
            if executor.waypointIndex != previousIndex {
                visitedFirst = true
                XCTAssertLessThanOrEqual(link.robot.truePose.distanceTo(map.waypoints[0].pose), executor.config.positionToleranceM + 0.01)
                XCTAssertLessThanOrEqual(abs(wrapDeg(link.robot.truePose.yawDeg - map.waypoints[0].pose.yawDeg)), executor.config.nodeHeadingToleranceDeg)
            }
            if executor.phase == .arrived { break }
        }
        XCTAssertTrue(visitedFirst)
        XCTAssertEqual(executor.phase, .arrived, executor.message)
        XCTAssertEqual(executor.waypointIndex, 1)
        let last = map.waypoints.last!.pose
        XCTAssertLessThanOrEqual(link.robot.truePose.distanceTo(last), executor.config.positionToleranceM + 0.01)
        XCTAssertLessThanOrEqual(abs(wrapDeg(link.robot.truePose.yawDeg - last.yawDeg)), executor.config.nodeHeadingToleranceDeg)
        XCTAssertTrue(phases.isSuperset(of: [.alignLine, .driveLine, .alignNode, .waiting, .arrived]))
        // Translation drives both wheels forward; turns rotate in place.
        XCTAssertTrue(link.movingPairs.allSatisfy { ($0.0 > 0 && $0.1 > 0) || abs($0.0 + $0.1) < 1e-9 })
    }

    func testUninstalledSonarAndWheelTelemetryCannotChangeNavigation() throws {
        let clean = MockRobotLink(), noisy = MockRobotLink()
        noisy.telemetry.sonarCm = 1
        noisy.telemetry.rpmLeft = 100000
        noisy.telemetry.rpmRight = -100000
        let a = WaypointExecutor(map: oneNode(), link: clean)
        let b = WaypointExecutor(map: oneNode(), link: noisy)
        try a.start(at: Pose2D(x: 0, y: 0))
        try b.start(at: Pose2D(x: 0, y: 0))
        for (index, pose) in [Pose2D(x: 0, y: 0), Pose2D(x: 0.1, y: 0), Pose2D.fromDeg(x: 0.2, y: 0, yawDeg: -3)].enumerated() {
            a.tick(pose: pose, trackingNormal: true, nowS: Double(index) * 2)
            b.tick(pose: pose, trackingNormal: true, nowS: Double(index) * 2)
            XCTAssertEqual(a.phase, b.phase)
            XCTAssertEqual(clean.lastLeft, noisy.lastLeft)
            XCTAssertEqual(clean.lastRight, noisy.lastRight)
        }
        XCTAssertGreaterThan(noisy.lastRight, noisy.lastLeft) // small left correction
        XCTAssertGreaterThan(noisy.lastLeft, 0)
    }

    func testStraightHeadingCorrectionPreservesTurnDirection() throws {
        for yaw in [-3.0, 3.0] {
            let link = MockRobotLink()
            let executor = WaypointExecutor(map: oneNode(), link: link)
            try executor.start(at: Pose2D(x: 0, y: 0))
            executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, nowS: 0)
            executor.tick(pose: .fromDeg(x: 0.1, y: 0, yawDeg: yaw), trackingNormal: true, nowS: 2)
            XCTAssertGreaterThan(link.lastLeft, 0)
            XCTAssertGreaterThan(link.lastRight, 0)
            XCTAssertEqual(link.lastRight > link.lastLeft, yaw < 0)
        }
    }

    func testNextNodeWaitsBeforeItsTurnAndBeforeDriving() throws {
        let map = RecordedMap(name: "两段", anchor: AnchorDefinition.templates[0],
            start: RecordedWaypoint(name: "起点", pose: Pose2D(x: 0, y: 0)), waypoints: [
                RecordedWaypoint(name: "第一点", pose: .fromDeg(x: 1, y: 0, yawDeg: 90)),
                RecordedWaypoint(name: "第二点", pose: Pose2D(x: 1, y: 1))
            ])
        let link = MockRobotLink()
        let executor = WaypointExecutor(map: map, link: link)
        let first = map.waypoints[0].pose
        try executor.start(at: map.start.pose)
        executor.tick(pose: map.start.pose, trackingNormal: true, nowS: 0)
        executor.tick(pose: map.start.pose, trackingNormal: true, nowS: 2)
        executor.tick(pose: Pose2D(x: 1, y: 0), trackingNormal: true, nowS: 3)
        executor.tick(pose: Pose2D(x: 1, y: 0), trackingNormal: true, nowS: 5)
        executor.tick(pose: first, trackingNormal: true, nowS: 6)
        XCTAssertEqual(executor.waypointIndex, 1)
        XCTAssertEqual(executor.phase, .waiting)
        let count = link.commandCount
        executor.tick(pose: first, trackingNormal: true, nowS: 7.999)
        XCTAssertEqual(link.commandCount, count)
        XCTAssertEqual(link.lastLeft, 0)
        // Next leg is already aligned; it still gets its own pre-drive pause.
        executor.tick(pose: first, trackingNormal: true, nowS: 8)
        executor.tick(pose: first, trackingNormal: true, nowS: 9.999)
        XCTAssertEqual(link.commandCount, count)
        executor.tick(pose: first, trackingNormal: true, nowS: 10)
        XCTAssertEqual(executor.phase, .driveLine)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(link.lastLeft), 160)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(link.lastRight), 160)
    }

    func testTrackingDisconnectOrManualStopCancelsPendingMovement() throws {
        for interruption in 0..<3 {
            let link = MockRobotLink()
            let executor = WaypointExecutor(map: oneNode(), link: link)
            let start = Pose2D(x: 0, y: 0)
            try executor.start(at: start)
            executor.tick(pose: start, trackingNormal: true, nowS: 0)
            XCTAssertEqual(executor.phase, .waiting)
            if interruption == 0 {
                executor.tick(pose: nil, trackingNormal: false, nowS: 1)
            } else if interruption == 1 {
                executor.tick(pose: start, trackingNormal: true, linkAvailable: false, nowS: 1)
            } else { executor.stop() }
            executor.tick(pose: start, trackingNormal: true, nowS: 10)
            XCTAssertEqual(executor.phase, .interrupted)
            XCTAssertEqual(link.commandCount, 0)
            XCTAssertEqual(link.lastLeft, 0)
            XCTAssertEqual(link.lastRight, 0)
            // An explicit restart must start a fresh, full pause.
            try executor.start(at: start)
            executor.tick(pose: start, trackingNormal: true, nowS: 20)
            executor.tick(pose: start, trackingNormal: true, nowS: 21.999)
            XCTAssertEqual(link.commandCount, 0)
            executor.tick(pose: start, trackingNormal: true, nowS: 22)
            XCTAssertGreaterThan(link.lastLeft, 0)
        }
    }

    func testWaitExpiryRechecksPoseInsteadOfSendingAStaleStraightCommand() throws {
        let link = MockRobotLink()
        let executor = WaypointExecutor(map: oneNode(), link: link)
        let start = Pose2D(x: 0, y: 0)
        let shifted = Pose2D.fromDeg(x: 0, y: 0, yawDeg: 30)
        try executor.start(at: start)
        executor.tick(pose: start, trackingNormal: true, nowS: 0)
        executor.tick(pose: shifted, trackingNormal: true, nowS: 2)
        XCTAssertEqual(link.commandCount, 0)
        XCTAssertEqual(executor.phase, .waiting)
        executor.tick(pose: shifted, trackingNormal: true, nowS: 3.999)
        XCTAssertEqual(link.commandCount, 0)
        executor.tick(pose: shifted, trackingNormal: true, nowS: 4)
        XCTAssertEqual(executor.phase, .alignLine)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(link.lastLeft), 160)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(link.lastRight), -160)
    }
}
