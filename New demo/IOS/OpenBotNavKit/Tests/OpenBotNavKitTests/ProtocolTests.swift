import XCTest
@testable import OpenBotNavKit

final class ProtocolTests: XCTestCase {

    func testControlCommandUsesPwmFrames() {
        let frame = OpenBotProtocol.ctrlCommand(left: 0.35, right: -1.0)
        XCTAssertEqual(String(data: frame, encoding: .ascii), "c89,-255\n")
        XCTAssertEqual(OpenBotProtocol.speedToPwm(1.5), 255)
        XCTAssertEqual(OpenBotProtocol.speedToPwm(-2.0), -255)
    }

    func testStreamCommands() {
        XCTAssertEqual(String(data: OpenBotProtocol.heartbeatCommand(intervalMs: 500), encoding: .ascii), "h500\n")
        XCTAssertEqual(String(data: OpenBotProtocol.featureCommand(), encoding: .ascii), "f\n")
        XCTAssertEqual(String(data: OpenBotProtocol.sensorStreamCommand(header: "s", intervalMs: 250), encoding: .ascii), "s250\n")
    }

    func testTelemetryParsing() {
        let telemetry = Telemetry()
        XCTAssertEqual(OpenBotProtocol.apply("v12.3\n", to: telemetry, nowS: 1.0), .voltage(12.3))
        XCTAssertEqual(OpenBotProtocol.apply("w100.5,-20\n", to: telemetry, nowS: 1.0), .wheel(rpmLeft: 100.5, rpmRight: -20.0))
        XCTAssertEqual(OpenBotProtocol.apply("s34", to: telemetry, nowS: 1.0), .sonar(distanceCm: 34.0))
        XCTAssertEqual(OpenBotProtocol.apply("b1", to: telemetry, nowS: 1.0), .bumper(collisionId: "1"))
        XCTAssertEqual(telemetry.rpmLeft, 100.5)
        XCTAssertEqual(telemetry.rpmRight, -20.0)
        XCTAssertEqual(telemetry.sonarCm, 34.0)
        XCTAssertEqual(telemetry.bumper, "1")
        XCTAssertEqual(telemetry.voltage, 12.3)
        XCTAssertEqual(telemetry.updatedAtS, 1.0)
        XCTAssertEqual(OpenBotProtocol.parse("x9"), .unknown("x9"))
    }

    func testDeviceNameMatchingFollowsThePythonSdk() {
        XCTAssertTrue(OpenBotProtocol.isOpenBotName("OpenBot"))
        XCTAssertTrue(OpenBotProtocol.isOpenBotName("openbot-01"))
        XCTAssertTrue(OpenBotProtocol.isOpenBotName("RTR_520"))
        XCTAssertTrue(OpenBotProtocol.isOpenBotName("rtr 520 spare"))
        XCTAssertFalse(OpenBotProtocol.isOpenBotName("ESP32"))
        XCTAssertFalse(OpenBotProtocol.isOpenBotName(nil))
    }

    func testMockLinkRecordsCommands() {
        let link = MockRobotLink()
        link.drive(left: 0.5, right: -0.5)
        XCTAssertEqual(link.lastLeft, 0.5)
        XCTAssertEqual(link.lastRight, -0.5)
        link.stop()
        XCTAssertEqual(link.lastLeft, 0.0)
        XCTAssertEqual(link.lastRight, 0.0)
    }
}
