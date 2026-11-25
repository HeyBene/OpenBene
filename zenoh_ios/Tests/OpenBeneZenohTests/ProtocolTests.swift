import XCTest
@testable import OpenBeneZenoh

final class ProtocolTests: XCTestCase {
    func testRobotIDMatchesAndroidSanitizer() {
        XCTAssertEqual(OpenBeneProtocol.sanitizeRobotID(" rtr 520 "), "rtr_520")
        XCTAssertEqual(OpenBeneProtocol.sanitizeRobotID("open/bene#1"), "open_bene_1")
        XCTAssertEqual(OpenBeneProtocol.sanitizeRobotID("   "), "robot")
    }

    func testKeysMatchAndroidContract() {
        XCTAssertEqual(OpenBeneProtocol.key(.frame, robotID: "rtr520"), "openbene/rtr520/frame")
        XCTAssertEqual(OpenBeneProtocol.keyPrefix(robotID: "a b"), "openbene/a_b")

        let parsed = OpenBeneProtocol.parseKey("openbene/rtr520/video")
        XCTAssertEqual(parsed?.robotID, "rtr520")
        XCTAssertEqual(parsed?.topic, .video)
        XCTAssertNil(OpenBeneProtocol.parseKey("openbene/rtr520/other"))
        XCTAssertNil(OpenBeneProtocol.parseKey("openbene/rtr520"))
    }

    func testEndpointNormalization() {
        XCTAssertEqual(OpenBeneProtocol.normalizeEndpoint("192.168.1.20:7447"), "tcp/192.168.1.20:7447")
        XCTAssertEqual(OpenBeneProtocol.normalizeEndpoint(" tcp/10.0.0.2:7447 "), "tcp/10.0.0.2:7447")
        XCTAssertEqual(OpenBeneProtocol.normalizeEndpoint("ws://10.0.0.2:8000/x"), "ws://10.0.0.2:8000/x")
        XCTAssertNil(OpenBeneProtocol.normalizeEndpoint("   "))
    }

    func testConfigDefaults() {
        let config = ZenohTransportConfig(robotID: "rtr 520", endpoint: "10.1.2.3:7447", sessionID: "s1")
        XCTAssertEqual(config.robotID, "rtr_520")
        XCTAssertEqual(config.endpoint, "tcp/10.1.2.3:7447")
        XCTAssertEqual(config.frameKey, "openbene/rtr_520/frame")
        XCTAssertEqual(config.commandKey, "openbene/rtr_520/cmd")
        XCTAssertFalse(config.publishLegacyVideo)
    }
}
