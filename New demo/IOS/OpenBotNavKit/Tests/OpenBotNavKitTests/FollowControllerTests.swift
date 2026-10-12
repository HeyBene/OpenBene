import XCTest
@testable import OpenBotNavKit

/// Mirrors shared/navcore/tests/test_follow.py: the three implementations have to
/// agree on every branch of the follow controller.
final class FollowControllerTests: XCTestCase {

    private func box(
        centreX: Double = 0.5,
        centreY: Double = 0.5,
        width: Double = 0.2,
        height: Double = 0.2
    ) -> PersonBox {
        PersonBox(centreX: centreX, centreY: centreY, width: width, height: height)
    }

    func testNoDetectionStops() {
        let command = FollowController.followCommand(box: nil)
        XCTAssertEqual(command.left, 0.0)
        XCTAssertEqual(command.right, 0.0)
        XCTAssertTrue(command.action.contains("searching"))
    }

    func testLostTargetStops() {
        let command = FollowController.followCommand(box: nil, secondsSinceSeen: 3.0)
        XCTAssertEqual(command.left, 0.0)
        XCTAssertEqual(command.right, 0.0)
        XCTAssertTrue(command.action.contains("lost"))
    }

    func testObstacleStopsEvenWithATarget() {
        let command = FollowController.followCommand(box: box(), sonarCm: 30.0)
        XCTAssertEqual(command.left, 0.0)
        XCTAssertEqual(command.right, 0.0)
        XCTAssertTrue(command.action.contains("obstacle"))
    }

    func testTurnsTowardsTheTarget() {
        let right = FollowController.followCommand(box: box(centreX: 0.8, height: 0.6))
        XCTAssertLessThan(right.left, 0.0)
        XCTAssertGreaterThan(right.right, 0.0)
        XCTAssertTrue(right.action.contains("right"))

        let left = FollowController.followCommand(box: box(centreX: 0.2, height: 0.6))
        XCTAssertGreaterThan(left.left, 0.0)
        XCTAssertLessThan(left.right, 0.0)
        XCTAssertTrue(left.action.contains("left"))
    }

    func testHoldsDistanceInsideTheDeadband() {
        let command = FollowController.followCommand(box: box(height: 0.55))
        XCTAssertEqual(command.left, 0.0)
        XCTAssertEqual(command.right, 0.0)
        XCTAssertTrue(command.action.contains("holding"))
    }

    func testBacksOffWhenTooClose() {
        let command = FollowController.followCommand(box: box(width: 0.4, height: 0.95))
        XCTAssertEqual(command.left, 0.0)
        XCTAssertEqual(command.right, 0.0)
        XCTAssertTrue(command.action.contains("close"))
    }

    func testDrivesForwardWhenFar() {
        let command = FollowController.followCommand(box: box(width: 0.1, height: 0.2))
        XCTAssertGreaterThan(command.left, 0.0)
        XCTAssertGreaterThan(command.right, 0.0)
        XCTAssertTrue(command.action.contains("closing"))
    }

    func testSteersWhileClosingIn() {
        let command = FollowController.followCommand(box: box(centreX: 0.58, width: 0.1, height: 0.2))
        XCTAssertGreaterThan(command.right, command.left)
        XCTAssertGreaterThan(command.left, 0.0)
    }

    func testBoxFromPixelsNormalises() {
        let normalised = FollowController.boxFromPixels(
            leftPx: 480.0,
            topPx: 360.0,
            rightPx: 1440.0,
            bottomPx: 1080.0,
            frameWidth: 1920.0,
            frameHeight: 1440.0
        )
        XCTAssertEqual(normalised.centreX, 0.5, accuracy: 1e-6)
        XCTAssertEqual(normalised.centreY, 0.5, accuracy: 1e-6)
        XCTAssertEqual(normalised.width, 0.5, accuracy: 1e-6)
        XCTAssertEqual(normalised.height, 0.5, accuracy: 1e-6)
    }

    func testFacePresetHoldsWhereThePersonPresetWouldCloseIn() {
        // A face box is a fraction of a person box, so the Android preset has to
        // hold where the person preset would still drive forward.
        let face = box(width: 0.14, height: 0.16)
        XCTAssertEqual(FollowController.followCommand(box: face).action, "closing in")
        XCTAssertEqual(FollowController.followCommand(box: face, config: .faceBox).action, "holding distance")
    }

    func testDistanceHintGrowsWithBoxSize() {
        let near = FollowController.distanceHintM(height: 0.5)
        let far = FollowController.distanceHintM(height: 0.25)
        XCTAssertGreaterThan(far, near)
        XCTAssertEqual(FollowController.distanceHintM(height: 0.0), Double.infinity)
    }
}
