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
        executor.tick(pose: Pose2D(x: 0.25, y: 0), trackingNormal: true, nowS: 0.4)
        XCTAssertGreaterThan(link.lastLeft, 0)
        XCTAssertEqual(link.lastLeft, link.lastRight)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(link.lastLeft), 160)
        // Just outside the arrival radius still needs enough PWM to move.
        executor.tick(pose: Pose2D(x: 0.69, y: 0), trackingNormal: true, nowS: 0.5)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(link.lastLeft), 160)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(link.lastRight), 160)
        executor.tick(pose: Pose2D(x: 1, y: 0), trackingNormal: true, nowS: 0.6)
        XCTAssertEqual(executor.phase, .waiting)
        XCTAssertEqual(link.lastLeft, 0)
        executor.tick(pose: Pose2D(x: 1, y: 0), trackingNormal: true, nowS: 0.849)
        XCTAssertEqual(executor.phase, .waiting)
        XCTAssertEqual(link.lastLeft, 0)
        XCTAssertEqual(link.lastRight, 0)
        executor.tick(pose: Pose2D(x: 1, y: 0), trackingNormal: true, nowS: 0.85)
        XCTAssertEqual(executor.phase, .alignNode)
        XCTAssertLessThan(link.lastLeft, 0)
        XCTAssertGreaterThan(link.lastRight, 0)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(link.lastLeft), -160)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(link.lastRight), 160)
        executor.tick(pose: .fromDeg(x: 1, y: 0, yawDeg: 90), trackingNormal: true, nowS: 0.86)
        executor.tick(pose: .fromDeg(x: 1, y: 0, yawDeg: 90), trackingNormal: true, nowS: 0.87)
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
        executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, nowS: 0.1)
        XCTAssertEqual(executor.phase, .driveLine)
        XCTAssertGreaterThan(link.lastLeft, 0)
        executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, nowS: 0.2)
        XCTAssertGreaterThan(link.lastLeft, 0)
        XCTAssertGreaterThan(link.lastRight, 0)
    }

    func testTrackingLossStopsAndDoesNotAutomaticallyResume() throws {
        let link = MockRobotLink()
        let executor = WaypointExecutor(map: oneNode(), link: link)
        try executor.start(at: Pose2D(x: 0, y: 0))
        executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, nowS: 0)
        executor.tick(pose: Pose2D(x: 0.1, y: 0), trackingNormal: true, nowS: 2)
        XCTAssertGreaterThan(link.lastLeft, 0)
        executor.tick(pose: nil, trackingNormal: false, nowS: 2.1)
        XCTAssertEqual(executor.phase, .recovering)
        XCTAssertEqual(link.lastLeft, 0)
        executor.tick(pose: Pose2D(x: 0.1, y: 0), trackingNormal: true, nowS: 5)
        XCTAssertEqual(executor.phase, .recovering)
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
        executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, nowS: 0.1)
        XCTAssertEqual(executor.phase, .waiting)
        XCTAssertEqual(link.lastLeft, 0)
        XCTAssertEqual(link.lastRight, 0)
        executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, nowS: 0.3)
        XCTAssertEqual(executor.phase, .alignNode)
        XCTAssertLessThan(link.lastLeft, 0)
        XCTAssertGreaterThan(link.lastRight, 0)
        executor.tick(pose: .fromDeg(x: 0, y: 0, yawDeg: 90), trackingNormal: true, nowS: 0.4)
        XCTAssertEqual(executor.phase, .arrived)
    }

    func testHeadingAcrossPiBoundaryDoesNotTurnAFullCircle() throws {
        let current = Pose2D.fromDeg(x: 0, y: 0, yawDeg: 179)
        let map = oneNode(start: current, target: .fromDeg(x: 0, y: 0, yawDeg: -179))
        let link = MockRobotLink()
        let executor = WaypointExecutor(map: map, link: link)
        try executor.start(at: current)
        executor.tick(pose: current, trackingNormal: true, nowS: 0)
        executor.tick(pose: current, trackingNormal: true, nowS: 0.4)
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
        var reachedFirst = false
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
                XCTAssertGreaterThanOrEqual(now - started, executor.config.stagePauseS - 0.01)
                waitStartedS = nil
            }
            phases.insert(executor.phase)
            if executor.waypointIndex != previousIndex {
                visitedFirst = true
                if previousIndex == 0 { reachedFirst = true }
                if previousIndex == 0 {
                    XCTAssertLessThanOrEqual(link.robot.truePose.distanceTo(map.waypoints[0].pose), 0.55)
                }
            }
            if executor.phase == .arrived { break }
        }
        XCTAssertTrue(visitedFirst)
        XCTAssertEqual(executor.phase, .arrived, executor.message)
        XCTAssertEqual(executor.waypointIndex, 1)
        let last = map.waypoints.last!.pose
        XCTAssertLessThanOrEqual(link.robot.truePose.distanceTo(last), 0.55)
        XCTAssertLessThanOrEqual(abs(wrapDeg(link.robot.truePose.yawDeg - last.yawDeg)), executor.config.nodeHeadingToleranceDeg)
        XCTAssertTrue(reachedFirst)
        XCTAssertTrue(phases.isSuperset(of: [.driveLine, .arrived]))
        // Translation drives both wheels forward; turns rotate in place.
        // Deliberate recovery may briefly reverse both wheels.
        XCTAssertTrue(link.movingPairs.allSatisfy {
            ($0.0 > 0 && $0.1 > 0) || ($0.0 < 0 && $0.1 < 0) || abs($0.0 + $0.1) < 1e-9
        })
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
        for (index, pose) in [Pose2D(x: 0, y: 0), Pose2D(x: 0.1, y: 0), Pose2D.fromDeg(x: 0.2, y: 0.05, yawDeg: 0)].enumerated() {
            a.tick(pose: pose, trackingNormal: true, nowS: Double(index) * 2)
            b.tick(pose: pose, trackingNormal: true, nowS: Double(index) * 2)
            XCTAssertEqual(a.phase, b.phase)
            XCTAssertEqual(clean.lastLeft, noisy.lastLeft)
            XCTAssertEqual(clean.lastRight, noisy.lastRight)
        }
        XCTAssertGreaterThan(noisy.lastLeft, noisy.lastRight) // left of line: slow right wheel
        XCTAssertGreaterThan(noisy.lastLeft, 0)
    }

    func testStraightHeadingCorrectionPreservesTurnDirection() throws {
        for yaw in [-3.0, 3.0] {
            let link = MockRobotLink()
            let executor = WaypointExecutor(map: oneNode(), link: link)
            try executor.start(at: Pose2D(x: 0, y: 0))
            executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, nowS: 0)
            executor.tick(pose: .fromDeg(x: 0.1, y: 0, yawDeg: yaw), trackingNormal: true, nowS: 0.01)
            XCTAssertGreaterThan(link.lastLeft, 0)
            XCTAssertGreaterThan(link.lastRight, 0)
            XCTAssertEqual(link.lastRight > link.lastLeft, yaw < 0)
        }
    }

    func testHeadingAloneKeepsBothWheelsForward() throws {
        for yaw in [-24.0, 24.0] {
            let link = MockRobotLink()
            let executor = WaypointExecutor(map: oneNode(), link: link)
            try executor.start(at: Pose2D(x: 0, y: 0))
            executor.tick(pose: Pose2D(x: 0, y: 0), trackingNormal: true, nowS: 0)
            executor.tick(pose: .fromDeg(x: 0.1, y: 0, yawDeg: yaw), trackingNormal: true, nowS: 0.01)
            XCTAssertEqual(executor.phase, .driveLine)
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
        executor.tick(pose: map.start.pose, trackingNormal: true, nowS: 0.4)
        executor.tick(pose: Pose2D(x: 1, y: 0), trackingNormal: true, nowS: 0.5)
        XCTAssertEqual(executor.waypointIndex, 1)
        XCTAssertEqual(executor.phase, .waiting)
        let count = link.commandCount
        executor.tick(pose: first, trackingNormal: true, nowS: 0.849)
        XCTAssertEqual(link.commandCount, count)
        XCTAssertEqual(link.lastLeft, 0)
        // The node heading starts after a short settle.
        executor.tick(pose: first, trackingNormal: true, nowS: 0.85)
        XCTAssertEqual(executor.phase, .alignNode)
        XCTAssertLessThan(link.lastLeft, 0)
        XCTAssertGreaterThan(link.lastRight, 0)
        executor.tick(pose: .fromDeg(x: 1, y: 0.5, yawDeg: 90), trackingNormal: true, nowS: 1.3)
        XCTAssertEqual(executor.phase, .driveLine)
        executor.tick(pose: .fromDeg(x: 1, y: 0.5, yawDeg: 90), trackingNormal: true, nowS: 1.4)
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
            XCTAssertEqual(executor.phase, .driveLine)
            if interruption == 0 {
                executor.tick(pose: nil, trackingNormal: false, nowS: 1)
            } else if interruption == 1 {
                executor.tick(pose: start, trackingNormal: true, linkAvailable: false, nowS: 1)
            } else { executor.stop() }
            executor.tick(pose: start, trackingNormal: true, nowS: 10)
            XCTAssertEqual(executor.phase, interruption == 0 ? .recovering : .interrupted)
            XCTAssertEqual(link.commandCount, 0)
            XCTAssertEqual(link.lastLeft, 0)
            XCTAssertEqual(link.lastRight, 0)
            // Restarting clears the pending stage and reuses fresh pose frames.
            try executor.start(at: start)
            executor.tick(pose: start, trackingNormal: true, nowS: 20)
            XCTAssertEqual(link.commandCount, 0)
            executor.tick(pose: start, trackingNormal: true, nowS: 20.01)
            XCTAssertGreaterThan(link.lastLeft, 0)
        }
    }

    func testLargeHeadingChangePivotsInsteadOfDrivingWithAStaleStraightCommand() throws {
        let link = MockRobotLink()
        let executor = WaypointExecutor(map: oneNode(), link: link)
        let start = Pose2D(x: 0, y: 0)
        let shifted = Pose2D.fromDeg(x: 0.05, y: 0, yawDeg: 120)
        try executor.start(at: start)
        executor.tick(pose: start, trackingNormal: true, nowS: 0)
        XCTAssertEqual(link.commandCount, 0)
        executor.tick(pose: shifted, trackingNormal: true, nowS: 0.1)
        XCTAssertEqual(executor.phase, .alignLine)
        XCTAssertEqual(link.commandCount, 0)
        executor.tick(pose: shifted, trackingNormal: true, nowS: 0.2)
        XCTAssertEqual(executor.phase, .alignLine)
        XCTAssertLessThan(link.lastLeft * link.lastRight, 0)
    }

    func testStartPlacementAdviceIsInCentimetresInTheLiveChassisFrame() throws {
        let map = RecordedMap(name: "起点建议", anchor: AnchorDefinition.templates[0],
            start: RecordedWaypoint(name: "起点", pose: .fromDeg(x: 0, y: 0, yawDeg: 0)),
            waypoints: [RecordedWaypoint(name: "终点", pose: Pose2D(x: 1, y: 0))])
        let advice = try XCTUnwrap(StartAlignment.advice(map: map, from: .fromDeg(x: -0.08, y: -0.05, yawDeg: 0)))
        XCTAssertEqual(advice.forwardM, 0.08, accuracy: 1e-9)
        XCTAssertEqual(advice.leftM, 0.05, accuracy: 1e-9)
        XCTAssertTrue(advice.setupText.contains("向前8 cm"))
        XCTAssertTrue(advice.setupText.contains("向左5 cm"))
        XCTAssertTrue(advice.canEnter)
    }
}
