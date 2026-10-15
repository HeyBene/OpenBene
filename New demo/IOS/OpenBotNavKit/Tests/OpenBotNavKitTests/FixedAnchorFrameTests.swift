import XCTest
@testable import OpenBotNavKit

final class FixedAnchorFrameTests: XCTestCase {
    func testCameraContinuesAfterMarkerLeavesView() throws {
        var frame = FixedAnchorFrame()
        XCTAssertTrue(frame.alignOnce(markerInAr: TestSupport.arFromMap))
        let moved = Pose2D.fromDeg(x: 3, y: 2, yawDeg: 48)
        let pose = try XCTUnwrap(frame.pose(deviceInAr: TestSupport.arFromMap.compose(moved), trackingNormal: true))
        XCTAssertEqual(pose.x, moved.x, accuracy: 1e-8)
        XCTAssertEqual(pose.y, moved.y, accuracy: 1e-8)
        XCTAssertEqual(pose.yawRad, moved.yawRad, accuracy: 1e-8)
    }

    func testRepeatedImageDetectionNeverMovesMapFrame() {
        var frame = FixedAnchorFrame()
        frame.alignOnce(markerInAr: TestSupport.arFromMap)
        let original = frame.mapFromAr
        XCTAssertFalse(frame.alignOnce(markerInAr: .fromDeg(x: 20, y: -10, yawDeg: -90)))
        XCTAssertEqual(frame.mapFromAr, original)
    }

    func testLimitedTrackingHidesLivePoseButPreservesAlignment() {
        var frame = FixedAnchorFrame()
        XCTAssertNil(frame.pose(deviceInAr: TestSupport.arFromMap, trackingNormal: true))
        frame.alignOnce(markerInAr: TestSupport.arFromMap)
        let original = frame.mapFromAr
        XCTAssertNil(frame.pose(deviceInAr: TestSupport.arFromMap, trackingNormal: false))
        XCTAssertEqual(frame.mapFromAr, original)
        XCTAssertNotNil(frame.pose(deviceInAr: TestSupport.arFromMap, trackingNormal: true))
    }
}
