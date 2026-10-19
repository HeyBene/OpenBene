import XCTest
@testable import OpenBotNavKit

final class FollowExecutorTests: XCTestCase {
    private let pwm = NavigationPwmSettings(drivePwm: 173, leftTurnPwm: 195, rightTurnPwm: 137)
    private func box(_ height: Double = 0.3, x: Double = 0.5, top: Double? = nil, width: Double = 0.1) -> PersonBox {
        PersonBox(centreX: x, centreY: top.map { $0 + height / 2 } ?? 0.5, width: width, height: height)
    }
    private func setup(_ options: FollowTestOptions = FollowTestOptions()) -> (FollowExecutor, MockRobotLink) {
        let link = MockRobotLink(); link.telemetry.connected = true
        let executor = FollowExecutor(link: link, pwm: pwm); executor.applyOptions(options)
        return (executor, link)
    }
    private func observe(_ executor: FollowExecutor, _ boxes: [PersonBox], timestampS: Double, distanceM: Double? = 2) {
        executor.observeDetections(boxes.map { PersonDetection(box: $0, confidence: 1, distanceM: distanceM) }, timestampS: timestampS)
    }
    private func tick(_ executor: FollowExecutor, _ time: Double) {
        executor.tick(nowS: time, trackingNormal: true, linkAvailable: true)
    }
    private func frame(_ link: MockRobotLink) -> String {
        String(decoding: OpenBotProtocol.ctrlCommand(left: link.lastLeft, right: link.lastRight), as: UTF8.self)
    }
    private func start(_ executor: FollowExecutor, _ target: PersonBox, at time: Double = 0, distanceM: Double? = 2) {
        observe(executor, [target], timestampS: time, distanceM: distanceM)
        executor.requestStart(nowS: time, delayS: 0); tick(executor, time)
    }

    func testNearPersonStopIsOnByDefaultAndOtherExperimentsAreOff() {
        let (executor, link) = setup()
        XCTAssertEqual(executor.options.enabledNames, ["距离停车"])
        start(executor, box())
        XCTAssertTrue(executor.active)
        XCTAssertEqual(frame(link), "c173,173\n")
        XCTAssertEqual(executor.gateReason, "无门槛拦截")
    }

    func testLargeNearEdgeBoxDoesNotTriggerOldHeightWidthOrPeriodicBrakes() {
        var options = FollowTestOptions(); options.stopWhenNear = false
        let (executor, link) = setup(options), target = box(0.99, top: 0, width: 0.7)
        start(executor, target)
        for i in 1...30 {
            let t = Double(i) * 0.1
            observe(executor, [target], timestampS: t); tick(executor, t)
            XCTAssertEqual(frame(link), "c173,173\n")
        }
    }

    func testForwardArcsUseIndependentDirectionPwmWithoutOppositeWheelRotation() {
        for x in [0.35, 0.65] {
            let (executor, link) = setup(); start(executor, box(x: x))
            for i in 1...15 {
                let t = Double(i) * 0.1
                observe(executor, [box(x: x)], timestampS: t); tick(executor, t)
                XCTAssertGreaterThanOrEqual(link.lastLeft, 0); XCTAssertGreaterThanOrEqual(link.lastRight, 0)
                if x < 0.5 { XCTAssertLessThan(link.lastLeft, link.lastRight) }
                else { XCTAssertGreaterThan(link.lastLeft, link.lastRight) }
            }
            let outer = x < 0.5 ? link.lastRight : link.lastLeft
            let expected = (Double(pwm.drivePwm) + (Double(x < 0.5 ? pwm.leftTurnPwm : pwm.rightTurnPwm) - Double(pwm.drivePwm)) * abs(2 * (x - 0.5))) / 255
            XCTAssertEqual(outer, expected, accuracy: 1e-8)
        }
    }

    func testFiveSecondsAreOnlyPreparationAndDoNotCalibrateAnyDistance() {
        let (executor, link) = setup()
        executor.requestStart(nowS: 0)
        tick(executor, 4.9)
        XCTAssertFalse(executor.active); XCTAssertEqual(link.commandCount, 0)
        observe(executor, [box(0.8, top: 0.1)], timestampS: 5)
        tick(executor, 5)
        XCTAssertTrue(executor.active)
        XCTAssertEqual(frame(link), "c173,173\n")
    }

    func testNoTargetAtCountdownEndDoesNotArmForUnexpectedLaterStart() {
        let (executor, link) = setup()
        executor.requestStart(nowS: 0); tick(executor, 5)
        XCTAssertFalse(executor.active); XCTAssertNil(executor.pending)
        observe(executor, [box()], timestampS: 6); tick(executor, 6)
        XCTAssertEqual(link.commandCount, 0)
        XCTAssertTrue(executor.status.contains("跟随未启动"))
    }

    func testConfidenceGateIndependentlyFiltersSameRawDetection() {
        for enabled in [false, true] {
            var options = FollowTestOptions(); options.confidenceFilter = enabled
            let (executor, link) = setup(options)
            executor.observeDetections([PersonDetection(box: box(), confidence: 0.55, distanceM: 2)], timestampS: 0)
            executor.requestStart(nowS: 0, delayS: 0); tick(executor, 0)
            XCTAssertEqual(link.commandCount > 0, !enabled)
            XCTAssertEqual(executor.personCount, enabled ? 0 : 1)
        }
    }

    func testInitialLargestBoxAndSinglePersonGateCanBeTestedSeparately() {
        for enabled in [false, true] {
            var options = FollowTestOptions(); options.requireSinglePerson = enabled
            let (executor, link) = setup(options)
            observe(executor, [box(0.2, x: 0.35), box(0.5, x: 0.65)], timestampS: 0)
            executor.requestStart(nowS: 0, delayS: 0); tick(executor, 0)
            if enabled { XCTAssertEqual(frame(link), "c0,0\n") }
            else { XCTAssertGreaterThan(link.lastLeft, link.lastRight); XCTAssertGreaterThanOrEqual(link.lastRight, 0) }
        }
    }

    func testSinglePersonGateStopsAnAlreadyActiveRun() {
        var options = FollowTestOptions(); options.requireSinglePerson = true
        let (executor, link) = setup(options); start(executor, box())
        observe(executor, [box(), box(x: 0.75)], timestampS: 0.15)
        XCTAssertTrue(executor.active); XCTAssertEqual(frame(link), "c0,0\n")
        XCTAssertTrue(executor.status.contains("单人门槛"))
        observe(executor, [box()], timestampS: 0.3); tick(executor, 0.3)
        XCTAssertEqual(frame(link), "c173,173\n")
    }

    func testThreeFrameGateAloneRequiresThreeObservations() {
        var options = FollowTestOptions(); options.requireStableTarget = true
        let (executor, link) = setup(options)
        executor.requestStart(nowS: 0, delayS: 1)
        observe(executor, [box()], timestampS: 0.7)
        XCTAssertFalse(executor.hasFreshTarget(nowS: 0.7))
        observe(executor, [box()], timestampS: 0.85)
        XCTAssertFalse(executor.hasFreshTarget(nowS: 0.85))
        observe(executor, [box()], timestampS: 1); tick(executor, 1)
        XCTAssertTrue(executor.active); XCTAssertEqual(frame(link), "c173,173\n")
    }

    func testEdgeGateCanRejectTheSameBoxWithoutEnablingOtherConditions() {
        for enabled in [false, true] {
            var options = FollowTestOptions(); options.rejectEdgeBoxes = enabled; options.stopWhenNear = false
            let (executor, link) = setup(options); start(executor, box(0.6, top: 0.005))
            XCTAssertEqual(frame(link), enabled ? "c0,0\n" : "c173,173\n")
        }
    }

    func testJumpGateAloneStopsLargeScaleChangeWhileBaselineContinues() {
        for enabled in [false, true] {
            var options = FollowTestOptions(); options.rejectTargetJump = enabled
            let (executor, link) = setup(options); start(executor, box(0.2))
            observe(executor, [box(0.5)], timestampS: 0.15); tick(executor, 0.15)
            XCTAssertEqual(frame(link), enabled ? "c0,0\n" : "c173,173\n")
            XCTAssertTrue(executor.active)
        }
    }

    func testStrictTimeoutCanBeTestedIndependentlyFromBaselinePointSixSeconds() {
        for enabled in [false, true] {
            var options = FollowTestOptions(); options.strictDetectionTimeout = enabled
            let (executor, link) = setup(options); start(executor, box())
            tick(executor, 0.4)
            XCTAssertTrue(executor.active)
            XCTAssertEqual(frame(link), enabled ? "c0,0\n" : "c173,173\n")
            tick(executor, 0.601)
            XCTAssertTrue(executor.active); XCTAssertEqual(frame(link), "c0,0\n")
        }
    }

    func testNoDetectionZerosOutputAndFreshTargetAutomaticallyResumes() {
        let (executor, link) = setup(); start(executor, box())
        observe(executor, [], timestampS: 0.15)
        XCTAssertEqual(frame(link), "c0,0\n")
        tick(executor, 0.601); XCTAssertTrue(executor.active)
        let count = link.commandCount
        observe(executor, [box()], timestampS: 0.7); tick(executor, 0.7)
        XCTAssertGreaterThan(link.commandCount, count)
        XCTAssertEqual(frame(link), "c173,173\n")
    }

    func testDistanceHoldAutomaticallyResumesWithMeasuredHysteresis() {
        let (executor, link) = setup(); start(executor, box(top: 0.001))
        observe(executor, [box(top: 0.001)], timestampS: 0.15, distanceM: 0.99); tick(executor, 0.15)
        XCTAssertEqual(frame(link), "c0,0\n"); XCTAssertTrue(executor.active)
        observe(executor, [box(top: 0.001)], timestampS: 0.3, distanceM: 1.1); tick(executor, 0.3)
        XCTAssertEqual(frame(link), "c0,0\n")
        for t in [0.45, 0.6, 0.75] {
            observe(executor, [box(top: 0.001)], timestampS: t, distanceM: 1.21); tick(executor, t)
            XCTAssertEqual(frame(link), "c0,0\n")
        }
        observe(executor, [box(top: 0.001)], timestampS: 0.9, distanceM: 1.21); tick(executor, 0.9)
        XCTAssertEqual(frame(link), "c173,173\n")
    }

    func testNearDistanceAllowsOnlyStationaryCenteringThenResumesWhenFar() {
        var options = FollowTestOptions(); options.stopWhenNear = true
        for x in [0.25, 0.75] {
            let (executor, link) = setup(options); start(executor, box(0.3, x: x, top: 0.01), distanceM: 0.8)
            var sawTurn = false
            for i in 1...12 {
                let t = Double(i) * 0.05
                observe(executor, [box(0.3, x: x, top: 0.01)], timestampS: t, distanceM: 0.8); tick(executor, t)
                XCTAssertLessThanOrEqual(link.lastLeft * link.lastRight, 0)
                if link.lastLeft * link.lastRight < 0 { sawTurn = true }
            }
            XCTAssertTrue(sawTurn)
            for i in 13...36 {
                let t = Double(i) * 0.05
                observe(executor, [box(0.3, top: 0.01)], timestampS: t, distanceM: 0.8); tick(executor, t)
            }
            XCTAssertEqual(frame(link), "c0,0\n")
            observe(executor, [box(0.3, top: 0.1)], timestampS: 1.95, distanceM: 1.3); tick(executor, 1.95)
            XCTAssertEqual(frame(link), "c0,0\n")
            for t in [2.1, 2.25, 2.4] { observe(executor, [box(0.3, top: 0.1)], timestampS: t, distanceM: 1.3); tick(executor, t) }
            XCTAssertEqual(frame(link), "c173,173\n")
        }
    }

    func testNoHardWheelReversalWhenPersonCrossesImageCentre() {
        let (executor, link) = setup(); start(executor, box(x: 0.65))
        for i in 1...30 {
            let t = Double(i) * 0.05, x = i < 10 ? 0.65 : 0.35
            observe(executor, [box(x: x)], timestampS: t); tick(executor, t)
            XCTAssertGreaterThanOrEqual(link.lastLeft, 0); XCTAssertGreaterThanOrEqual(link.lastRight, 0)
        }
        XCTAssertLessThan(link.lastLeft, link.lastRight)
    }

    func testTemporaryCameraLimitPausesThenResumesWithoutAnotherStart() {
        let (executor, link) = setup(); start(executor, box())
        executor.tick(nowS: 0.1, trackingNormal: false, linkAvailable: true)
        XCTAssertTrue(executor.active); XCTAssertEqual(frame(link), "c0,0\n")
        for i in 0...5 {
            let t = 0.2 + Double(i) * 0.1
            observe(executor, [box()], timestampS: t); tick(executor, t)
            if i < 5 { XCTAssertEqual(frame(link), "c0,0\n") }
        }
        XCTAssertEqual(frame(link), "c173,173\n")
        executor.stop()
        observe(executor, [box()], timestampS: 0.8); tick(executor, 0.8)
        XCTAssertEqual(frame(link), "c0,0\n"); XCTAssertFalse(executor.active)
    }

    func testStopDistanceIsAdjustableAndDoesNotDependOnBodyHeightOrTop() {
        var options = FollowTestOptions(); options.stopDistanceM = 1.5
        for height in [0.1, 0.8] {
            let (executor, link) = setup(options); start(executor, box(height, top: 0.001), distanceM: 1.7)
            XCTAssertEqual(frame(link), "c173,173\n")
            observe(executor, [box(height, top: 0.001)], timestampS: 0.15, distanceM: 1.49); tick(executor, 0.15)
            XCTAssertEqual(frame(link), "c0,0\n")
        }
    }

    func testOptionalPulseGateAppliesToStationaryNearPersonTurns() {
        for enabled in [false, true] {
            var options = FollowTestOptions(); options.stopWhenNear = true; options.pulseTurns = enabled
            let (executor, link) = setup(options); start(executor, box(x: 0.25, top: 0.01), distanceM: 0.8)
            for i in 1...8 {
                let t = Double(i) * 0.1
                observe(executor, [box(x: 0.25, top: 0.01)], timestampS: t, distanceM: 0.8); tick(executor, t)
            }
            observe(executor, [box(x: 0.25, top: 0.01)], timestampS: 0.81, distanceM: 0.8); tick(executor, 0.81)
            if enabled { XCTAssertEqual(frame(link), "c0,0\n") }
            else { XCTAssertEqual(frame(link), "c-195,195\n") }
        }
    }

    func testOptionalReversalWaitSeparatesOppositeStationaryTurns() {
        var options = FollowTestOptions(); options.stopWhenNear = true; options.pauseBeforeReversal = true
        let (executor, link) = setup(options); start(executor, box(x: 0.25, top: 0.01), distanceM: 0.8)
        var lastLeftTime: Double?, firstRightTime: Double?
        for i in 1...120 {
            let t = Double(i) * 0.05, x = 0.25 + min(0.5, max(0, (t - 1) * 0.25))
            observe(executor, [box(x: x, top: 0.01)], timestampS: t, distanceM: 0.8); tick(executor, t)
            if link.lastLeft < 0 && link.lastRight > 0 { lastLeftTime = t }
            if link.lastLeft > 0 && link.lastRight < 0 && firstRightTime == nil { firstRightTime = t }
        }
        XCTAssertNotNil(lastLeftTime); XCTAssertNotNil(firstRightTime)
        if let left = lastLeftTime, let right = firstRightTime { XCTAssertGreaterThanOrEqual(right - left, 2) }
    }

    func testChangingOptionsOrPwmStopsAndNeverRestartsByItself() {
        let (executor, link) = setup(); start(executor, box())
        var options = FollowTestOptions(); options.stopWhenNear = true
        executor.applyOptions(options)
        XCTAssertFalse(executor.active); XCTAssertEqual(frame(link), "c0,0\n")
        start(executor, box(), at: 0.15)
        executor.applyPwm(NavigationPwmSettings(drivePwm: 160, leftTurnPwm: 180, rightTurnPwm: 140))
        XCTAssertFalse(executor.active); XCTAssertEqual(frame(link), "c0,0\n")
        start(executor, box(), at: 0.3)
        XCTAssertEqual(frame(link), "c160,160\n")
    }

    func testInvalidBoxConfidenceAndTimeNeverDriveEvenWithAllGatesOff() {
        for target in [box(.nan), box(0), box(0.2, width: 0), box(x: .infinity)] {
            let (executor, link) = setup(); start(executor, target)
            XCTAssertEqual(link.commandCount, 0)
        }
        let (executor, link) = setup()
        executor.observeDetections([PersonDetection(box: box(), confidence: .nan)], timestampS: 0)
        executor.requestStart(nowS: 0, delayS: 0); tick(executor, 0)
        XCTAssertEqual(link.commandCount, 0)
        start(executor, box(), at: 0.15)
        observe(executor, [box()], timestampS: .nan)
        XCTAssertFalse(executor.active); XCTAssertEqual(frame(link), "c0,0\n")
    }

    func testTrackingDisconnectBumperAndCancelledStartStillStopWithAllGatesOff() {
        for interruption in 1..<3 {
            let (executor, link) = setup(); start(executor, box())
            if interruption == 2 { link.telemetry.bumper = "front" }
            executor.tick(nowS: 0.1, trackingNormal: interruption != 0, linkAvailable: interruption != 1)
            XCTAssertFalse(executor.active); XCTAssertEqual(frame(link), "c0,0\n")
        }
        let (executor, link) = setup()
        executor.requestStart(nowS: 0); executor.stop()
        observe(executor, [box()], timestampS: 5); tick(executor, 5)
        XCTAssertEqual(link.commandCount, 0)
    }

    func testUnreliableSonarAndWheelRpmRemainOutsideTheControlLoop() {
        let (executor, link) = setup()
        link.telemetry.sonarCm = 1; link.telemetry.rpmLeft = 10000; link.telemetry.rpmRight = -10000
        start(executor, box()); XCTAssertEqual(frame(link), "c173,173\n")
    }

    func testFarClippedTopBoxFromDeviceReportNoLongerCausesFalseStop() {
        let link = MockRobotLink(); link.telemetry.connected = true
        let executor = FollowExecutor(link: link, pwm: NavigationPwmSettings(drivePwm: 135, leftTurnPwm: 172, rightTurnPwm: 172))
        start(executor, box(0.5252, top: 0.0021, width: 0.3449), distanceM: 2)
        XCTAssertTrue(executor.active)
        XCTAssertEqual(frame(link), "c135,135\n")
    }

    func testMissingOrInvalidRangeNeverReusesAnOlderFarReading() {
        for distance: Double? in [nil, .nan, -1, .infinity] {
            let (executor, link) = setup(); start(executor, box(), distanceM: 2)
            XCTAssertGreaterThan(link.lastLeft, 0)
            observe(executor, [box()], timestampS: 0.15, distanceM: distance); tick(executor, 0.15)
            XCTAssertEqual(frame(link), "c0,0\n")
            XCTAssertEqual(executor.gateReason, "距离未知，禁止前进")
            XCTAssertNil(executor.distanceM)
        }
    }

    func testRangeFollowsMatchedPersonRatherThanALargerDistractor() {
        let (executor, _) = setup(); start(executor, box(x: 0.35), distanceM: 2)
        executor.observeDetections([
            PersonDetection(box: box(x: 0.36), confidence: 1, distanceM: 1.8),
            PersonDetection(box: box(0.7, x: 0.8, width: 0.4), confidence: 1, distanceM: 0.5)
        ], timestampS: 0.15)
        XCTAssertEqual(executor.distanceM, 1.8)
        XCTAssertLessThan(executor.box!.centreX, 0.4)
    }

    func testVisibleTargetNearSideTriggersPivotButActualLossImmediatelyStops() {
        for x in [0.15, 0.85] {
            let (executor, link) = setup(); start(executor, box(x: x), distanceM: 2)
            observe(executor, [box(x: x)], timestampS: 0.1); tick(executor, 0.1)
            XCTAssertLessThan(link.lastLeft * link.lastRight, 0)
            XCTAssertEqual(link.lastLeft + link.lastRight, 0, accuracy: 1e-9)
            observe(executor, [], timestampS: 0.15); tick(executor, 0.15)
            XCTAssertEqual(frame(link), "c0,0\n")
            XCTAssertTrue(executor.active)
        }
    }

    func testOneFarReadingOrRangeJitterCannotResumeForwardMotion() {
        let (executor, link) = setup(); start(executor, box(), distanceM: 0.8)
        observe(executor, [box()], timestampS: 0.15, distanceM: 1.3)
        for t in [0.2, 0.4, 0.6] { tick(executor, t); XCTAssertEqual(frame(link), "c0,0\n") }
        observe(executor, [box()], timestampS: 0.65, distanceM: 1.1); tick(executor, 0.65)
        for t in [0.8, 0.95, 1.1] {
            observe(executor, [box()], timestampS: t, distanceM: 1.3); tick(executor, t)
            XCTAssertEqual(frame(link), "c0,0\n")
        }
        observe(executor, [box()], timestampS: 1.25, distanceM: 1.3); tick(executor, 1.25)
        XCTAssertEqual(frame(link), "c173,173\n")
    }

}
