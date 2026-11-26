import XCTest
@testable import OpenBeneRobot

final class OpenBotBLETests: XCTestCase {
    func testServiceAndCharacteristicUUIDsMatchSDK() {
        XCTAssertEqual(OpenBotBLE.serviceUUID, "61653dc3-4021-4d1e-ba83-8b4eec61d613")
        XCTAssertEqual(OpenBotBLE.rxUUID, "06386c14-86ea-4d71-811c-48f97c58f8c9")
        XCTAssertEqual(OpenBotBLE.txUUID, "9bf1103b-834c-47cf-b149-c9e4bcf778a7")
    }

    func testDriveCommandMatchesSDKWireFormat() {
        XCTAssertEqual(OpenBotBLE.driveCommand(left: 120, right: -90), Data("c120,-90\n".utf8))
        XCTAssertEqual(OpenBotBLE.heartbeatCommand(intervalMs: 300), Data("h300\n".utf8))
        XCTAssertEqual(OpenBotBLE.featureCommand(), Data("f\n".utf8))
        XCTAssertEqual(OpenBotBLE.sensorStreamCommand("w", intervalMs: 500), Data("w500\n".utf8))
    }

    func testClampsDriveValues() {
        XCTAssertEqual(OpenBotBLE.clampPWM(900), 255)
        XCTAssertEqual(OpenBotBLE.clampPWM(-900), -255)
        XCTAssertEqual(OpenBotBLE.clampPWM(42), 42)
        XCTAssertEqual(OpenBotBLE.driveCommand(left: 900, right: -900), Data("c255,-255\n".utf8))
    }

    func testDetectsOpenBotNames() {
        XCTAssertTrue(OpenBotBLE.isOpenBotName("OpenBot RTR_520"))
        XCTAssertTrue(OpenBotBLE.isOpenBotName("my openbot"))
        XCTAssertFalse(OpenBotBLE.isOpenBotName("Headphones"))
        XCTAssertFalse(OpenBotBLE.isOpenBotName(nil))
    }

    func testParsesTelemetry() {
        XCTAssertEqual(OpenBotTelemetry.parse("v12.35"), .voltage(12.35))
        XCTAssertEqual(OpenBotTelemetry.parse("w12.5,-3.25"), .wheel(leftRPM: 12.5, rightRPM: -3.25))
        XCTAssertEqual(OpenBotTelemetry.parse("s88"), .sonar(distanceCm: 88))
        XCTAssertEqual(OpenBotTelemetry.parse("b2"), .bumper("2"))
        XCTAssertEqual(
            OpenBotTelemetry.parse("frtr520:s:wf:"),
            .features(robotType: "rtr520", capabilities: ["s", "wf"])
        )
        XCTAssertEqual(
            OpenBotTelemetry.parse("f:rtr520:s:"),
            .features(robotType: "rtr520", capabilities: ["s"])
        )
        XCTAssertEqual(OpenBotTelemetry.parse("?"), .unknown("?"))
    }
}

@MainActor
final class DriveMappingTests: XCTestCase {
    func testKeyboardLayoutMatchesSDKExample() {
        XCTAssertEqual(DriveMapping.command(for: "w"), WheelCommand(left: 120, right: 120, label: "前进"))
        XCTAssertEqual(DriveMapping.command(for: "s"), WheelCommand(left: -120, right: -120, label: "后退"))
        XCTAssertEqual(DriveMapping.command(for: "a"), WheelCommand(left: -90, right: 90, label: "左转"))
        XCTAssertEqual(DriveMapping.command(for: "d"), WheelCommand(left: 90, right: -90, label: "右转"))
        XCTAssertEqual(DriveMapping.command(for: "q"), WheelCommand(left: 66, right: 120, label: "左弧线"))
        XCTAssertEqual(DriveMapping.command(for: "e"), WheelCommand(left: 120, right: 66, label: "右弧线"))
        XCTAssertEqual(DriveMapping.command(for: "x"), .stop)
        XCTAssertEqual(DriveMapping.command(for: " "), .stop)
        XCTAssertNil(DriveMapping.command(for: "z"))
    }

    func testMappingIsCaseInsensitive() {
        XCTAssertEqual(DriveMapping.command(for: "W"), DriveMapping.command(for: "w"))
    }

    func testSliderScalesPWM() {
        let slow = DriveMapping.command(for: .forward, drivePWM: 26, turnPWM: 26, arcScale: 0.5)
        XCTAssertEqual(slow.left, 26)
        XCTAssertEqual(slow.right, 26)
        let big = DriveMapping.command(for: .forward, drivePWM: 999, turnPWM: 999, arcScale: 1)
        XCTAssertEqual(big, WheelCommand(left: 255, right: 255, label: "前进"))
    }
}
