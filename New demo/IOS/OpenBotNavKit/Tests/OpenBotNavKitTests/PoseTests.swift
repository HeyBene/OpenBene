import XCTest
@testable import OpenBotNavKit

final class PoseTests: XCTestCase {

    func testAngleWrappingPreservesHeadingAcrossFullTurns() {
        for heading in [-90.0, 0.0, 90.0, 180.0] {
            for turns in -3...3 {
                let degrees = heading + Double(turns) * 360.0
                XCTAssertEqual(wrapDeg(degrees), heading, accuracy: 1e-9)
                XCTAssertEqual(wrapRad(degrees * Double.pi / 180.0), heading * Double.pi / 180.0, accuracy: 1e-9)
            }
        }
    }

    func testNegativeHalfTurnUsesThePositiveBoundary() {
        XCTAssertEqual(wrapDeg(-180.0), 180.0, accuracy: 1e-9)
        XCTAssertEqual(wrapRad(-Double.pi), Double.pi, accuracy: 1e-9)
    }

    func testPoseComposeMatchesHandCalculation() {
        let first = Pose2D.fromDeg(x: 1.0, y: 2.0, yawDeg: 90.0)
        let second = Pose2D.fromDeg(x: 3.0, y: 0.0, yawDeg: 0.0)
        let composed = first.compose(second)
        XCTAssertEqual(composed.x, 1.0, accuracy: 1e-9)
        XCTAssertEqual(composed.y, 5.0, accuracy: 1e-9)
        XCTAssertEqual(wrapDeg(composed.yawDeg), 90.0, accuracy: 1e-9)

        let roundTrip = composed.compose(second.inverse())
        XCTAssertEqual(roundTrip.x, first.x, accuracy: 1e-9)
        XCTAssertEqual(roundTrip.y, first.y, accuracy: 1e-9)
    }

    func testAlignmentIsIndependentOfTheArFrame() throws {
        let map = TestSupport.demoMap()
        let estimator = PoseEstimator(mapData: map)
        let truePose = Pose2D.fromDeg(x: 1.4, y: -0.6, yawDeg: 12.0)
        let marker = try map.marker("mk_entrance")
        try estimator.align(TestSupport.observation(marker: marker, truePose: truePose))

        let recovered = try XCTUnwrap(estimator.pose)
        XCTAssertEqual(recovered.distanceTo(truePose), 0.0, accuracy: 1e-6)
        XCTAssertEqual(wrapDeg(recovered.yawDeg - truePose.yawDeg), 0.0, accuracy: 1e-6)
        XCTAssertTrue(estimator.aligned)
        XCTAssertEqual(estimator.lastMarkerId, "mk_entrance")
    }

    func testOdometryIntegratesWheelSpeeds() throws {
        let map = TestSupport.demoMap()
        let estimator = PoseEstimator(mapData: map)
        let marker = try map.marker("mk_entrance")
        try estimator.align(TestSupport.observation(marker: marker, truePose: Pose2D(x: 0, y: 0, yawRad: 0)))

        // 100 rpm on both wheels is 0.34 m/s with the demo wheel radius.
        estimator.integrateOdometry(rpmLeft: 100.0, rpmRight: 100.0, dtS: 1.0)
        let forward = try XCTUnwrap(estimator.pose)
        XCTAssertEqual(forward.x, 0.34, accuracy: 0.02)
        XCTAssertEqual(estimator.driftM, 0.34, accuracy: 0.02)

        // A differential command rotates in place, counter-clockwise for +v_right.
        let before = try XCTUnwrap(estimator.pose)
        estimator.integrateOdometry(rpmLeft: -100.0, rpmRight: 100.0, dtS: 0.5)
        let turned = try XCTUnwrap(estimator.pose)
        XCTAssertGreaterThan(turned.yawRad - before.yawRad, 0.0)
        XCTAssertEqual(turned.distanceTo(before), 0.0, accuracy: 1e-9)
    }

    func testArUpdateClearsDrift() throws {
        let map = TestSupport.demoMap()
        let estimator = PoseEstimator(mapData: map)
        let marker = try map.marker("mk_junction")
        let truePose = Pose2D.fromDeg(x: 5.2, y: 0.3, yawDeg: -5.0)
        try estimator.align(TestSupport.observation(marker: marker, truePose: truePose))
        estimator.integrateOdometry(rpmLeft: 100.0, rpmRight: 100.0, dtS: 2.0)
        XCTAssertGreaterThan(estimator.driftM, 0.5)

        estimator.updateFromAr(TestSupport.arFromMap.compose(truePose))
        XCTAssertEqual(estimator.driftM, 0.0, accuracy: 1e-9)
        let recovered = try XCTUnwrap(estimator.pose)
        XCTAssertEqual(recovered.distanceTo(truePose), 0.0, accuracy: 1e-6)
    }
}
