import XCTest
@testable import OpenBotNavKit

final class PwmSettingsTests: XCTestCase {
    func testSavedSettingsReloadAndLeaveNavigationPausesIntact() throws {
        let suite = "PwmSettingsTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NavigationPwmStore(defaults: defaults)
        XCTAssertEqual(store.load(), .defaults)
        let settings = NavigationPwmSettings(drivePwm: 173, leftTurnPwm: 195, rightTurnPwm: 137)
        try store.save(settings)
        let reloaded = NavigationPwmStore(defaults: defaults).load()
        XCTAssertEqual(reloaded, settings)
        let config = reloaded.waypointConfig()
        XCTAssertEqual(OpenBotProtocol.speedToPwm(config.cruiseSpeed), 173)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(config.leftTurnSpeed), 195)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(config.rightTurnSpeed), 137)
        XCTAssertEqual(config.stagePauseS, 2)
        XCTAssertFalse(config.sonarInstalled)
    }

    func testCorruptOrOutOfRangeSavedValuesFallBackWithoutDriving() throws {
        let suite = "PwmSettingsTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = NavigationPwmStore(defaults: defaults)
        for data in [Data("broken".utf8), Data("{\"drivePwm\":999,\"turnPwm\":160}".utf8),
                     Data("{\"drivePwm\":160,\"leftTurnPwm\":190,\"rightTurnPwm\":256}".utf8),
                     Data("{\"drivePwm\":160,\"leftTurnPwm\":190}".utf8)] {
            defaults.set(data, forKey: "navigation.pwm.v1")
            XCTAssertEqual(store.load(), .defaults)
        }
        var invalid = NavigationPwmSettings()
        invalid.leftTurnPwm = -1
        XCTAssertThrowsError(try store.save(invalid))
    }

    func testCustomSettingsReachTheNavigationWireFrames() throws {
        let settings = NavigationPwmSettings(drivePwm: 173, leftTurnPwm: 195, rightTurnPwm: 137)
        let map = RecordedTestSupport.map()
        let link = MockRobotLink()
        let executor = WaypointExecutor(map: map, link: link, config: settings.waypointConfig())
        let aligned = Pose2D(x: map.start.pose.x, y: map.start.pose.y,
            yawRad: atan2(map.waypoints[0].pose.y - map.start.pose.y, map.waypoints[0].pose.x - map.start.pose.x))
        try executor.start(at: aligned)
        executor.tick(pose: aligned, trackingNormal: true, nowS: 0)
        executor.tick(pose: aligned, trackingNormal: true, nowS: 1.999)
        XCTAssertEqual(link.lastLeft, 0)
        executor.tick(pose: aligned, trackingNormal: true, nowS: 2)
        XCTAssertEqual(OpenBotProtocol.ctrlCommand(left: link.lastLeft, right: link.lastRight), Data("c173,173\n".utf8))
        executor.tick(pose: Pose2D(x: aligned.x, y: aligned.y, yawRad: aligned.yawRad - .pi / 2),
                      trackingNormal: true, nowS: 3)
        XCTAssertEqual(link.lastLeft, 0)
        executor.tick(pose: Pose2D(x: aligned.x, y: aligned.y, yawRad: aligned.yawRad - .pi / 2),
                      trackingNormal: true, nowS: 5)
        XCTAssertEqual(OpenBotProtocol.ctrlCommand(left: link.lastLeft, right: link.lastRight), Data("c-195,195\n".utf8))
        executor.tick(pose: Pose2D(x: aligned.x, y: aligned.y, yawRad: aligned.yawRad + .pi / 2),
                      trackingNormal: true, nowS: 5.1)
        XCTAssertEqual(OpenBotProtocol.ctrlCommand(left: link.lastLeft, right: link.lastRight), Data("c137,-137\n".utf8))
    }

    func testEachBenchDirectionUsesItsOwnPwmAndStopsAtOneSecond() {
        let settings = NavigationPwmSettings(drivePwm: 173, leftTurnPwm: 195, rightTurnPwm: 137)
        for (action, frame) in [(PwmTestAction.forward, "c173,173"), (.turnLeft, "c-195,195"), (.turnRight, "c137,-137")] {
            let link = MockRobotLink()
            link.telemetry.connected = true
            let tester = PwmPulseTester(link: link)
            XCTAssertTrue(tester.start(action, settings: settings, nowS: 10))
            XCTAssertEqual(tester.lastFrame, frame)
            tester.tick(nowS: 10.999)
            XCTAssertTrue(tester.active)
            XCTAssertEqual(tester.lastFrame, frame)
            tester.tick(nowS: 11)
            XCTAssertFalse(tester.active)
            XCTAssertEqual(link.lastLeft, 0)
            XCTAssertEqual(link.lastRight, 0)
            XCTAssertEqual(tester.lastFrame, "c0,0")
            let commands = link.commandCount
            tester.tick(nowS: 20)
            XCTAssertEqual(link.commandCount, commands)
        }
    }

    func testManualStopDisconnectAndCollisionPreventBenchRestart() {
        for interruption in 0..<3 {
            let link = MockRobotLink()
            link.telemetry.connected = true
            let tester = PwmPulseTester(link: link)
            XCTAssertTrue(tester.start(.forward, settings: .defaults, nowS: 0))
            if interruption == 0 { tester.stop() }
            if interruption == 1 { link.telemetry.connected = false }
            if interruption == 2 { link.telemetry.bumper = "front" }
            tester.tick(nowS: 0.5)
            XCTAssertFalse(tester.active)
            XCTAssertEqual(link.lastLeft, 0)
            link.telemetry.connected = true
            link.telemetry.bumper = nil
            let commands = link.commandCount
            tester.tick(nowS: 0.75)
            XCTAssertEqual(link.commandCount, commands)
        }
    }

    func testOpeningOrDisconnectedBenchDoesNotMove() {
        let link = MockRobotLink()
        let tester = PwmPulseTester(link: link)
        tester.tick(nowS: 0)
        XCTAssertEqual(link.commandCount, 0)
        XCTAssertFalse(tester.start(.forward, settings: .defaults, nowS: 0))
        XCTAssertEqual(link.commandCount, 0)
        XCTAssertEqual(NavigationPwmSettings(drivePwm: -50, leftTurnPwm: 999, rightTurnPwm: -1),
                       NavigationPwmSettings(drivePwm: 0, leftTurnPwm: 255, rightTurnPwm: 0))
    }

    func testLegacyTurningPwmMigratesToBothDirectionsWithoutLosingSavedValues() throws {
        let suite = "PwmSettingsTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("{\"drivePwm\":173,\"turnPwm\":195}".utf8), forKey: "navigation.pwm.v1")
        let store = NavigationPwmStore(defaults: defaults)
        var migrated = store.load()
        XCTAssertEqual(migrated, NavigationPwmSettings(drivePwm: 173, leftTurnPwm: 195, rightTurnPwm: 195))
        migrated.rightTurnPwm = 137
        try store.save(migrated)
        XCTAssertEqual(NavigationPwmStore(defaults: defaults).load(), migrated)
        let saved = try XCTUnwrap(defaults.data(forKey: "navigation.pwm.v1"))
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Int])
        XCTAssertEqual(fields["leftTurnPwm"], 195)
        XCTAssertEqual(fields["rightTurnPwm"], 137)
        XCTAssertNil(fields["turnPwm"])
    }

    func testArrivalHeadingUsesItsOwnLeftOrRightSetting() throws {
        let settings = NavigationPwmSettings(drivePwm: 173, leftTurnPwm: 195, rightTurnPwm: 137)
        for (yaw, frame) in [(90.0, "c-195,195\n"), (-90.0, "c137,-137\n")] {
            let start = Pose2D(x: 0, y: 0)
            let arrived = Pose2D(x: 1, y: 0)
            let map = RecordedMap(name: "终点转向", anchor: AnchorDefinition.templates[0],
                start: RecordedWaypoint(name: "起点", pose: start), waypoints: [
                    RecordedWaypoint(name: "终点", pose: .fromDeg(x: 1, y: 0, yawDeg: yaw))
                ])
            let link = MockRobotLink()
            let executor = WaypointExecutor(map: map, link: link, config: settings.waypointConfig())
            try executor.start(at: start)
            executor.tick(pose: start, trackingNormal: true, nowS: 0)
            executor.tick(pose: start, trackingNormal: true, nowS: 2)
            executor.tick(pose: arrived, trackingNormal: true, nowS: 3)
            executor.tick(pose: arrived, trackingNormal: true, nowS: 5)
            XCTAssertEqual(executor.phase, .alignNode)
            XCTAssertEqual(OpenBotProtocol.ctrlCommand(left: link.lastLeft, right: link.lastRight), Data(frame.utf8))
        }
    }
}
