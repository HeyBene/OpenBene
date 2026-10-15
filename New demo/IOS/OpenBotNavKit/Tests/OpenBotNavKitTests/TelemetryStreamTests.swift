import XCTest
@testable import OpenBotNavKit

final class TelemetryStreamTests: XCTestCase {
    func testSplitNotificationWaitsForCompleteWheelFrame() {
        var stream = OpenBotTelemetryStream()
        let telemetry = Telemetry()
        stream.receive(Data("w12,".utf8), to: telemetry, nowS: 1, sonarInstalled: false)
        XCTAssertEqual(telemetry.rpmLeft, 0)
        stream.receive(Data("34\nv7.8\nf:wb:\n".utf8), to: telemetry, nowS: 2, sonarInstalled: false)
        XCTAssertEqual(telemetry.rpmLeft, 12)
        XCTAssertEqual(telemetry.rpmRight, 34)
        XCTAssertEqual(telemetry.voltage, 7.8)
        XCTAssertEqual(telemetry.features, ":wb:")
    }

    func testFloatingSonarIsIgnoredEvenIfFirmwareSendsIt() {
        var stream = OpenBotTelemetryStream()
        let telemetry = Telemetry()
        for value in 1...3 {
            stream.receive(Data("s\(value)\r\n".utf8), to: telemetry, nowS: 1, sonarInstalled: false)
            XCTAssertNil(telemetry.sonarCm)
        }
        stream.receive(Data("s20\n".utf8), to: telemetry, nowS: 2, sonarInstalled: true)
        XCTAssertEqual(telemetry.sonarCm, 20)
    }
}
