import XCTest
@testable import OpenBotNavKit

final class ReturnImageHomingTests: XCTestCase {
    private func p(_ x: Double, _ y: Double = 0, _ yaw: Double = 0) -> Pose2D { .fromDeg(x: x, y: y, yawDeg: yaw) }
    private func map() throws -> RecordedMap {
        let poses = [p(0.4, 0, 30), p(0.8), p(1.6, 0, 180)]
        let samples = poses.enumerated().map { TrajectorySample(pose: $1, timestampS: Double($0) / 10, startsSegment: $0 == 0) }
        return try RecordedMap.planned(name: "图片归位", anchor: AnchorDefinition.templates[0],
            start: RecordedWaypoint(name: "起点", pose: poses[1], trajectoryIndex: 1),
            waypoints: [RecordedWaypoint(name: "终点", pose: poses[2], trajectoryIndex: 2)], samples: samples,
            anchorStart: RecordedWaypoint(name: "支架出发位置", pose: poses[0], trajectoryIndex: 0))
    }
    private func setup() throws -> (RecordedMap, WaypointExecutor, MockRobotLink) {
        let map = try map(), link = MockRobotLink()
        var config = WaypointConfig(); config.requireReturnImage = true
        let executor = WaypointExecutor(map: map, link: link, config: config)
        try executor.start(at: p(0.65, 0, 180), returningFrom: map.start.id)
        return (map, executor, link)
    }
    private func tick(_ e: WaypointExecutor, _ pose: Pose2D, _ t: Double) { e.tick(pose: pose, trackingNormal: true, nowS: t) }
    private func advanceToImageWait(_ e: WaypointExecutor, goal: Pose2D, at t: Double) {
        tick(e, goal, t); tick(e, goal, t + 2.1); tick(e, goal, t + 2.5); tick(e, goal, t + 4.6)
    }

    func testImageTransformCorrectsCoordinateEstimateWithoutPretendingRobotMoved() {
        var frame = FixedAnchorFrame()
        let oldMarker = p(2.8, -2.1, 22), currentMarker = p(3, -2, 30)
        let actual = p(0.55, 0.04, 70), cameraInAr = currentMarker.compose(actual)
        frame.alignOnce(markerInAr: oldMarker)
        let before = frame.pose(deviceInAr: cameraInAr, trackingNormal: true)!
        XCTAssertGreaterThan(before.distanceTo(actual), 0.1)
        XCTAssertTrue(frame.realignForReturn(markerInAr: currentMarker))
        let corrected = frame.pose(deviceInAr: cameraInAr, trackingNormal: true)!
        XCTAssertEqual(corrected.x, actual.x, accuracy: 1e-9)
        XCTAssertEqual(corrected.y, actual.y, accuracy: 1e-9)
        XCTAssertEqual(corrected.yawDeg, actual.yawDeg, accuracy: 1e-9)
        XCTAssertGreaterThan(corrected.distanceTo(p(0.4, 0, 30)), 0.15)
    }

    func testInvalidOrUninitializedFrameCannotRecalibrate() {
        var frame = FixedAnchorFrame()
        XCTAssertFalse(frame.realignForReturn(markerInAr: p(1)))
        frame.alignOnce(markerInAr: p(1))
        let saved = frame.mapFromAr
        XCTAssertFalse(frame.realignForReturn(markerInAr: p(.nan)))
        XCTAssertEqual(frame.mapFromAr, saved)
        XCTAssertFalse(frame.alignOnce(markerInAr: p(2)))
    }

    func testOnlyTerminalReturnCanRequestImageVerification() throws {
        let (map, e, link) = try setup()
        XCTAssertTrue(e.canVerifyReturnImage)
        e.beginReturnImageVerification(nowS: 0)
        XCTAssertEqual(e.phase, .verifyingImage); XCTAssertEqual(link.lastLeft, 0)
        e.stop(); e.acceptReturnImagePose(map.executionStart.pose, nowS: 1)
        XCTAssertEqual(e.phase, .interrupted)
        try e.start(at: map.waypoints[0].pose, returningFrom: map.waypoints[0].id)
        XCTAssertFalse(e.isReturnTerminal); XCTAssertFalse(e.canVerifyReturnImage)
        e.beginReturnImageVerification(nowS: 2)
        XCTAssertEqual(e.phase, .alignLine)
    }

    func testImageCorrectionStartsPhysicalMovementButCannotReapplySameMovingObservation() throws {
        let (_, e, link) = try setup()
        e.beginReturnImageVerification(nowS: 0)
        e.acceptReturnImagePose(p(0.6, 0, 180), nowS: 0.6)
        XCTAssertEqual(e.phase, .waiting)
        XCTAssertEqual(e.imageCorrectionCount, 1)
        XCTAssertFalse(e.canVerifyReturnImage)
        e.beginReturnImageVerification(nowS: 0.7)
        XCTAssertEqual(e.phase, .waiting)
        tick(e, p(0.6, 0, 180), 2.7); tick(e, p(0.6, 0, 180), 3.1)
        tick(e, p(0.6, 0, 180), 5.2)
        XCTAssertEqual(e.phase, .driveLine)
        XCTAssertGreaterThan(link.lastLeft, 0); XCTAssertGreaterThan(link.lastRight, 0)
    }

    func testCorrectionBeyondThirtyCentimetresStopsInsteadOfDrivingUnknownFloor() throws {
        let (_, e, link) = try setup()
        e.beginReturnImageVerification(nowS: 0)
        e.acceptReturnImagePose(p(0.75, 0, 30), nowS: 0.6)
        XCTAssertEqual(e.phase, .interrupted)
        XCTAssertTrue(e.message.contains("30cm")); XCTAssertEqual(link.lastLeft, 0)
    }

    func testArrivalRequiresFreshImageAndCanFinishImmediatelyWhenAlreadyCorrect() throws {
        let (map, e, _) = try setup()
        advanceToImageWait(e, goal: map.executionStart.pose, at: 0)
        XCTAssertEqual(e.phase, .awaitingImage)
        XCTAssertTrue(e.active)
        e.beginReturnImageVerification(nowS: 5)
        e.acceptReturnImagePose(map.executionStart.pose, nowS: 5.6)
        XCTAssertEqual(e.phase, .arrived)
        XCTAssertTrue(e.message.contains("图片已复核"))
    }

    func testVerificationLossResumesBoundedImageSearchAndHasTotalTimeout() throws {
        let (_, e, link) = try setup()
        e.beginReturnImageVerification(nowS: 0)
        tick(e, p(0.5, 0, 30), 5.1)
        XCTAssertEqual(e.phase, .awaitingImage)
        XCTAssertEqual(link.lastLeft, 0)
        tick(e, p(0.5, 0, 30), 91)
        XCTAssertEqual(e.phase, .interrupted)
        XCTAssertTrue(e.message.contains("90秒"))
    }

    func testCameraPivotResidualAfterFinalHeadingRequestsAnotherCorrectionAndIsBounded() throws {
        let (map, e, link) = try setup()
        e.beginReturnImageVerification(nowS: 0)
        e.acceptReturnImagePose(p(0.5, 0, 30), nowS: 0.6)
        for round in 0..<3 {
            let time = 3 + Double(round) * 10
            advanceToImageWait(e, goal: map.executionStart.pose, at: time)
            XCTAssertEqual(e.phase, .awaitingImage)
            e.beginReturnImageVerification(nowS: time + 5)
            e.acceptReturnImagePose(p(0.5, 0, 30), nowS: time + 5.6)
        }
        XCTAssertEqual(e.phase, .interrupted)
        XCTAssertTrue(e.message.contains("已微调3次"))
        XCTAssertEqual(link.lastLeft, 0); XCTAssertEqual(link.lastRight, 0)
    }

    func testSimulatedImageHomingRemovesVioBiasByActuallyDrivingBackToSavedPose() throws {
        let map = try map()
        var config = WaypointConfig(); config.requireReturnImage = true
        let robot = SimulatedRobotLink(pose: p(0.67, 0, 180))
        let e = WaypointExecutor(map: map, link: robot, config: config)
        try e.start(at: p(0.55, 0, 180), returningFrom: map.start.id)
        var correctedFrame = false, verifyingAt: Double?
        for step in 0..<15000 {
            let time = Double(step) / 60
            robot.tick(dtS: 1.0 / 60)
            let pose = correctedFrame ? robot.truePose : p(robot.truePose.x - 0.12, robot.truePose.y, robot.truePose.yawDeg)
            if e.canVerifyReturnImage, (e.imageCorrectionCount == 0 || e.phase == .awaitingImage) {
                e.beginReturnImageVerification(nowS: time); verifyingAt = time
            }
            if let began = verifyingAt, e.phase == .verifyingImage, time - began >= 0.5 {
                correctedFrame = true
                e.acceptReturnImagePose(robot.truePose, nowS: time); verifyingAt = nil
            }
            tick(e, correctedFrame ? robot.truePose : pose, time)
            if !e.active { break }
        }
        XCTAssertEqual(e.phase, .arrived, e.message)
        XCTAssertGreaterThanOrEqual(e.imageCorrectionCount, 2)
        XCTAssertLessThanOrEqual(robot.truePose.distanceTo(map.executionStart.pose), 0.05)
        XCTAssertLessThanOrEqual(abs(wrapDeg(robot.truePose.yawDeg - map.executionStart.pose.yawDeg)), 5)
    }
}
