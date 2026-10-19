import XCTest
@testable import OpenBotNavKit

final class PersonTargetTrackerTests: XCTestCase {
    private func box(_ x: Double, _ w: Double = 0.1, top: Double = 0.2) -> PersonBox {
        PersonBox(centreX: x, centreY: top + 0.2, width: w, height: 0.4)
    }
    func testLargerDistractorDoesNotReplaceThePreviouslyMatchedPerson() throws {
        var tracker = PersonTargetTracker()
        _ = tracker.update([box(0.3)], time: 0)
        let target = try XCTUnwrap(tracker.update([box(0.31), box(0.8, 0.4)], time: 0.15))
        XCTAssertLessThan(target.centreX, 0.32)
        XCTAssertNil(tracker.update([box(0.9, 0.1)], time: 0.3))
        XCTAssertEqual(tracker.update([box(0.9)], time: 0.8)?.centreX, 0.9)
    }
    func testHorizontalJitterIsSmoothedButTopStopSignalIsNotDelayed() throws {
        var tracker = PersonTargetTracker()
        _ = tracker.update([box(0.48)], time: 0)
        let target = try XCTUnwrap(tracker.update([box(0.52, top: 0.01)], time: 0.15))
        XCTAssertGreaterThan(target.centreX, 0.48); XCTAssertLessThan(target.centreX, 0.52)
        XCTAssertEqual(target.centreY - target.height / 2, 0.01, accuracy: 1e-9)
    }
    func testForwardSteeringNeverCommandsOppositeWheelDirectionsAndHasFiniteSlew() {
        var steering = ObjectFollowSteering()
        let pwm = NavigationPwmSettings(drivePwm: 160, leftTurnPwm: 190, rightTurnPwm: 175)
        var previous: FollowCommand?
        for i in 0..<200 {
            let command = steering.command(box: box(i % 2 == 0 ? 0.35 : 0.65), pwm: pwm, nowS: Double(i) / 20, holdForward: false)
            XCTAssertGreaterThanOrEqual(command.left, 0); XCTAssertGreaterThanOrEqual(command.right, 0)
            if let prior = previous {
                XCTAssertLessThan(abs(command.left - prior.left), 0.1)
                XCTAssertLessThan(abs(command.right - prior.right), 0.1)
            }
            previous = command
        }
    }
    func testNearCenteringNeverTranslatesAndBrakesBeforeChangingSign() {
        var steering = ObjectFollowSteering()
        let pwm = NavigationPwmSettings.defaults
        for i in 0..<40 {
            let command = steering.command(box: box(i < 20 ? 0.2 : 0.8), pwm: pwm, nowS: Double(i) / 20, holdForward: true)
            XCTAssertEqual(command.left + command.right, 0, accuracy: 1e-9)
        }
    }

    func testFollowingConvergesWithDelayedNoisyBoxesAndWheelInertia() {
        for initialYaw in [-20.0, 20] {
            let link = MockRobotLink(); link.telemetry.connected = true
            let executor = FollowExecutor(link: link, pwm: NavigationPwmSettings(drivePwm: 160, leftTurnPwm: 180, rightTurnPwm: 180))
            var pose = Pose2D.fromDeg(x: 0, y: 0, yawDeg: initialYaw)
            let person = Pose2D(x: 3, y: 0)
            func observation(_ pose: Pose2D, jitter: Double) -> PersonBox {
                let bearing = pose.headingErrorTo(person)
                let x = min(0.95, max(0.05, 0.5 - tan(bearing) / (2 * tan(Double.pi / 6)) + jitter))
                return PersonBox(centreX: x, centreY: 0.5, width: 0.1, height: 0.4)
            }
            executor.observeDetections([PersonDetection(box: observation(pose, jitter: 0), confidence: 1, distanceM: pose.distanceTo(person))], timestampS: 0)
            executor.requestStart(nowS: 0, delayS: 0)
            var left = 0.0, right = 0.0
            var pending: [(time: Double, box: PersonBox)] = []
            let dt = 1.0 / 60
            for step in 0..<480 {
                let time = Double(step) * dt
                if step % 9 == 0 { pending.append((time, observation(pose, jitter: step % 18 == 0 ? 0.005 : -0.005))) }
                while let first = pending.first, time - first.time >= 0.08 {
                    executor.observeDetections([PersonDetection(box: first.box, confidence: 1, distanceM: pose.distanceTo(person))], timestampS: first.time); pending.removeFirst()
                }
                executor.tick(nowS: time, trackingNormal: true, linkAvailable: true)
                XCTAssertGreaterThanOrEqual(link.lastLeft + link.lastRight, -1e-9)
                left += (link.lastLeft * 0.98 - left) * dt / 0.18
                right += (link.lastRight * 1.02 - right) * dt / 0.18
                let speed = (left + right) * 0.45 / 2
                pose = pose.translated(forwardM: speed * dt)
                pose.yawRad = wrapRad(pose.yawRad + (right - left) * 0.45 / 0.30 * dt)
                if pose.distanceTo(person) < 0.8 { break }
            }
            XCTAssertLessThan(pose.distanceTo(person), 1.8)
            XCTAssertLessThan(abs(pose.headingErrorTo(person)) * 180 / .pi, 8)
            XCTAssertTrue(executor.active)
        }
    }

    func testNinetyDegreeWalkingTurnKeepsPersonVisibleWithLatencyAndInertia() {
        for side in [-1.0, 1] {
            let link = MockRobotLink(); link.telemetry.connected = true
            let executor = FollowExecutor(link: link, pwm: NavigationPwmSettings(drivePwm: 135, leftTurnPwm: 172, rightTurnPwm: 172))
            var robot = Pose2D(x: 0, y: 0), left = 0.0, right = 0.0
            var pending: [(time: Double, detections: [PersonDetection])] = []
            var sawPivot = false, missed = 0
            let dt = 1.0 / 60, halfFov = 19.0 * Double.pi / 180
            func observePerson(_ person: Pose2D, time: Double) -> [PersonDetection] {
                let angle = robot.headingErrorTo(person), distance = robot.distanceTo(person)
                guard abs(angle) < .pi / 2 else { return [] }
                let cx = 0.5 - tan(angle) / (2 * tan(halfFov))
                let width = min(0.7, 0.4 / (2 * max(0.2, distance) * tan(halfFov)))
                let lo = max(0, cx - width / 2), hi = min(1, cx + width / 2)
                guard hi - lo > 0.04 else { return [] }
                return [PersonDetection(box: PersonBox(centreX: (lo + hi) / 2, centreY: 0.3, width: hi - lo, height: 0.6),
                    confidence: 1, distanceM: distance)]
            }
            executor.observeDetections(observePerson(Pose2D(x: 1.2, y: 0), time: 0), timestampS: 0)
            executor.requestStart(nowS: 0, delayS: 0)
            for i in 0..<600 {
                let time = Double(i) * dt
                // A real right angle, not an interpolated curved person path.
                let person = Pose2D(x: 1.2 + min(0.7, time) * 0.6, y: side * max(0, time - 0.7) * 0.6)
                if i % 4 == 0 {
                    let detections = observePerson(person, time: time)
                    if detections.isEmpty { missed += 1 }
                    pending.append((time, detections))
                }
                while let first = pending.first, time - first.time >= 0.08 {
                    executor.observeDetections(first.detections, timestampS: first.time); pending.removeFirst()
                }
                executor.tick(nowS: time, trackingNormal: true, linkAvailable: true)
                if link.lastLeft * link.lastRight < 0 { sawPivot = true }
                XCTAssertGreaterThanOrEqual(link.lastLeft + link.lastRight, -1e-9)
                left += (link.lastLeft - left) * dt / 0.18
                right += (link.lastRight - right) * dt / 0.18
                robot = robot.translated(forwardM: (left + right) * 0.45 / 2 * dt)
                robot.yawRad = wrapRad(robot.yawRad + (right - left) * 0.45 / 0.30 * dt)
            }
            XCTAssertTrue(sawPivot)
            XCTAssertEqual(missed, 0, "A synthetic detector cannot keep reporting an offscreen person.")
            XCTAssertTrue(executor.active)
        }
    }
}
