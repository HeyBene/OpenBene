import XCTest
@testable import OpenBeneZenoh

final class MessageTests: XCTestCase {
    func testParsesDriveCommandFromAndroidJSON() throws {
        let json = """
        {"version":1,"cmd":"drive","val":[0.4,-0.25],"seq":42,"sent_at":1700000000000,"ttl_ms":250}
        """.data(using: .utf8)!
        XCTAssertEqual(
            RobotCommand.parse(json),
            .drive(left: 0.4, right: -0.25, sequence: 42, sentAtMs: 1_700_000_000_000, ttlMs: 250)
        )
    }

    func testClampsDriveValues() {
        let json = #"{"cmd":"drive","val":[9,-9],"seq":1}"#.data(using: .utf8)!
        XCTAssertEqual(RobotCommand.parse(json), .drive(left: 1, right: -1, sequence: 1, sentAtMs: 0, ttlMs: 0))
    }

    func testParsesStopCommand() {
        let json = #"{"cmd":"stop","seq":7,"sent_at":5}"#.data(using: .utf8)!
        XCTAssertEqual(RobotCommand.parse(json), .stop(sequence: 7, sentAtMs: 5))
    }

    func testRejectsMalformedCommands() {
        XCTAssertEqual(RobotCommand.parse(Data("not json".utf8)), .unknown(reason: "invalid json"))
        XCTAssertEqual(
            RobotCommand.parse(#"{"cmd":"drive","val":[0.1]}"#.data(using: .utf8)!),
            .unknown(reason: "drive command is missing val[2]")
        )
        XCTAssertEqual(
            RobotCommand.parse(#"{"cmd":"turn"}"#.data(using: .utf8)!),
            .unknown(reason: "unsupported cmd: turn")
        )
    }

    func testStatusDocumentShape() throws {
        let data = StatusMessage(robotID: "rtr520", connected: true, timestampMs: 99).jsonData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, 1)
        XCTAssertEqual(object["robot_id"] as? String, "rtr520")
        XCTAssertEqual(object["connected"] as? Bool, true)
        XCTAssertEqual(object["state"] as? String, "online")
        XCTAssertEqual(object["timestamp"] as? Int, 99)
    }

    func testTelemetryNullsSonar() throws {
        let data = TelemetryMessage(voltage: 12.3, leftRPM: 1, rightRPM: 2, sonarCm: nil, timestampMs: 7).jsonData()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertTrue(object["sonar_cm"] is NSNull)
        XCTAssertEqual(object["type"] as? String, "telemetry")
    }
}
