import XCTest
@testable import OpenBotNavKit

final class CaptureTrajectoryTests: XCTestCase {
    private func point(_ x: Double, _ y: Double = 0, yaw: Double = 0) -> Pose2D {
        Pose2D(x: x, y: y, yawRad: yaw)
    }

    func testStartsOnlyWhenCaptureStartIsRecorded() {
        var trace = CaptureTrajectory()
        XCTAssertFalse(trace.observe(pose: point(1), trackingNormal: true, timestampS: 1))
        XCTAssertTrue(trace.samples.isEmpty)
        XCTAssertTrue(trace.begin(pose: point(2, 3), timestampS: 10))
        XCTAssertEqual(trace.samples.count, 1)
        XCTAssertEqual(trace.samples[0].pose, point(2, 3))
        XCTAssertTrue(trace.samples[0].startsSegment)
        XCTAssertEqual(trace.distanceM, 0)
    }

    func testCurvedMotionIsRecordedWithoutWaypointClicks() {
        var trace = CaptureTrajectory()
        trace.begin(pose: point(0), timestampS: 0)
        XCTAssertTrue(trace.observe(pose: point(1), trackingNormal: true, timestampS: 0.1))
        XCTAssertTrue(trace.observe(pose: point(1, 1), trackingNormal: true, timestampS: 0.2))
        XCTAssertEqual(trace.samples.map { $0.pose }, [point(0), point(1), point(1, 1)])
        XCTAssertEqual(trace.distanceM, 2, accuracy: 1e-9)
        XCTAssertFalse(trace.samples[1].startsSegment)
    }

    func testOptionalRateAndMovementThresholdRemainAvailable() {
        var trace = CaptureTrajectory(sampleIntervalS: 0.1, minimumDistanceM: 0.04)
        trace.begin(pose: point(0), timestampS: 0)
        XCTAssertFalse(trace.observe(pose: point(0.01), trackingNormal: true, timestampS: 0.1))
        XCTAssertTrue(trace.observe(pose: point(0.05), trackingNormal: true, timestampS: 0.2))
        XCTAssertFalse(trace.observe(pose: point(0.10), trackingNormal: true, timestampS: 0.25))
        XCTAssertTrue(trace.observe(pose: point(0.10), trackingNormal: true, timestampS: 0.3))
        XCTAssertEqual(trace.samples.count, 3)
        XCTAssertEqual(trace.distanceM, 0.10, accuracy: 1e-9)
    }

    func testRotationAloneDoesNotAddTravelDistance() {
        var trace = CaptureTrajectory()
        trace.begin(pose: point(0), timestampS: 0)
        XCTAssertTrue(trace.observe(pose: point(0, yaw: .pi), trackingNormal: true, timestampS: 0.1))
        XCTAssertEqual(trace.samples.count, 2)
        XCTAssertEqual(trace.distanceM, 0)
    }

    func testTrackingLossPreservesTrailAndDoesNotBridgeMissingMotion() {
        var trace = CaptureTrajectory()
        trace.begin(pose: point(0), timestampS: 0)
        trace.observe(pose: point(1), trackingNormal: true, timestampS: 0.1)
        XCTAssertFalse(trace.observe(pose: nil, trackingNormal: false, timestampS: 0.2))
        XCTAssertEqual(trace.samples.count, 2)
        XCTAssertTrue(trace.observe(pose: point(10), trackingNormal: true, timestampS: 0.3))
        XCTAssertTrue(trace.samples.last!.startsSegment)
        XCTAssertEqual(trace.distanceM, 1, accuracy: 1e-9)
        trace.observe(pose: point(11), trackingNormal: true, timestampS: 0.4)
        XCTAssertFalse(trace.samples.last!.startsSegment)
        XCTAssertEqual(trace.distanceM, 2, accuracy: 1e-9)
    }

    func testStalledCameraAndUnavailableCallbackBreakContinuity() {
        var trace = CaptureTrajectory()
        trace.begin(pose: point(0), timestampS: 0)
        XCTAssertTrue(trace.observe(pose: point(2), trackingNormal: true, timestampS: 1))
        XCTAssertTrue(trace.samples.last!.startsSegment)
        XCTAssertEqual(trace.distanceM, 0)
        trace.breakSegment()
        XCTAssertTrue(trace.observe(pose: point(5), trackingNormal: true, timestampS: 1.1))
        XCTAssertTrue(trace.samples.last!.startsSegment)
        XCTAssertEqual(trace.distanceM, 0)
    }

    func testStationaryButFreshFramesDoNotCountAsCameraGap() {
        var trace = CaptureTrajectory(minimumDistanceM: 0.04)
        trace.begin(pose: point(0), timestampS: 0)
        for i in 1...20 {
            XCTAssertFalse(trace.observe(pose: point(0), trackingNormal: true, timestampS: Double(i) * 0.1))
        }
        XCTAssertTrue(trace.observe(pose: point(0.2), trackingNormal: true, timestampS: 2.1))
        XCTAssertFalse(trace.samples.last!.startsSegment)
        XCTAssertEqual(trace.distanceM, 0.2, accuracy: 1e-9)
    }

    func testDuplicatesAreIgnoredAndBackwardsTimeBreaksTrail() {
        var trace = CaptureTrajectory()
        trace.begin(pose: point(0), timestampS: 1)
        XCTAssertFalse(trace.observe(pose: point(20), trackingNormal: true, timestampS: 1))
        XCTAssertFalse(trace.observe(pose: point(10), trackingNormal: true, timestampS: 0.9))
        XCTAssertTrue(trace.observe(pose: point(2), trackingNormal: true, timestampS: 1.1))
        XCTAssertTrue(trace.samples.last!.startsSegment)
        XCTAssertEqual(trace.distanceM, 0)
    }

    func testInvalidSamplesCannotCorruptGeometryOrDistance() {
        var trace = CaptureTrajectory()
        XCTAssertFalse(trace.begin(pose: point(.nan), timestampS: 0))
        XCTAssertFalse(trace.started)
        trace.begin(pose: point(0), timestampS: 0)
        XCTAssertFalse(trace.observe(pose: point(.infinity), trackingNormal: true, timestampS: 0.1))
        XCTAssertFalse(trace.observe(pose: point(1), trackingNormal: true, timestampS: .nan))
        XCTAssertTrue(trace.observe(pose: point(2), trackingNormal: true, timestampS: 0.2))
        XCTAssertTrue(trace.samples.last!.startsSegment)
        XCTAssertEqual(trace.distanceM, 0)
        XCTAssertTrue(trace.distanceM.isFinite)
    }

    func testBoundedHistoryRetainsCumulativeObservedDistance() {
        var trace = CaptureTrajectory(maxSamples: 8)
        trace.begin(pose: point(0), timestampS: 0)
        for i in 1...100 {
            trace.observe(pose: point(Double(i)), trackingNormal: true, timestampS: Double(i) * 0.1)
            XCTAssertLessThanOrEqual(trace.samples.count, 8)
        }
        XCTAssertGreaterThan(trace.prunedSampleCount, 0)
        XCTAssertEqual(trace.samples.last?.pose, point(100))
        XCTAssertEqual(trace.recordedSamples.count, 101)
        XCTAssertEqual(trace.recordedSamples.first?.pose, point(0))
        XCTAssertEqual(trace.distanceM, 100, accuracy: 1e-9)
    }

    func testResetAndNewStartCannotJoinDifferentCaptures() {
        var trace = CaptureTrajectory()
        trace.begin(pose: point(0), timestampS: 1)
        trace.observe(pose: point(1), trackingNormal: true, timestampS: 1.1)
        trace.reset()
        XCTAssertFalse(trace.started)
        XCTAssertTrue(trace.samples.isEmpty)
        XCTAssertEqual(trace.distanceM, 0)
        trace.begin(pose: point(20), timestampS: 2)
        XCTAssertEqual(trace.samples.count, 1)
        XCTAssertTrue(trace.samples[0].startsSegment)
        XCTAssertEqual(trace.distanceM, 0)
    }
    func testDefaultCapturesThirtyHzIncludingStationaryHeading() {
        var trace = CaptureTrajectory()
        trace.begin(pose: point(0), timestampS: 0)
        for frame in 1...600 {
            trace.observe(pose: point(0, yaw: Double(frame) / 600), trackingNormal: true,
                          timestampS: Double(frame) / 60)
        }
        XCTAssertEqual(trace.recordedSamples.count, 301)
        XCTAssertEqual(trace.distanceM, 0)
        XCTAssertEqual(trace.recordedSamples.last?.pose.yawRad, 1)
    }

    func testCameraJitterDoesNotReduceRateToTwentyHz() {
        var trace = CaptureTrajectory()
        trace.begin(pose: point(0), timestampS: 0)
        for frame in 1...600 {
            let jitter = frame % 2 == 0 ? -0.001 : 0.001
            trace.observe(pose: point(Double(frame) / 600), trackingNormal: true,
                          timestampS: Double(frame) / 60 + jitter)
        }
        XCTAssertTrue((299...301).contains(trace.recordedSamples.count))
    }

    func testWaypointPinUsesLatestFilteredFrameAndExactPose() throws {
        var trace = CaptureTrajectory()
        trace.begin(pose: point(0), timestampS: 0)
        XCTAssertFalse(trace.observe(pose: point(0.02), trackingNormal: true, timestampS: 1.0 / 60))
        let index = try trace.pin(pose: point(0.02), timestampS: 1.0 / 60)
        XCTAssertEqual(index, 1)
        XCTAssertEqual(trace.recordedSamples[index].pose, point(0.02))
        XCTAssertEqual(try trace.pin(pose: point(0.02), timestampS: 1.0 / 60), index)
    }

    func testArchiveLimitIsExplicitAndNeverPrunesSavedBeginning() {
        var trace = CaptureTrajectory()
        trace.begin(pose: point(0), timestampS: 0)
        for i in 1...54001 {
            trace.observe(pose: point(Double(i) / 30), trackingNormal: true, timestampS: Double(i) / 30)
        }
        XCTAssertTrue(trace.capacityReached)
        XCTAssertEqual(trace.recordedSamples.count, 54000)
        XCTAssertEqual(trace.recordedSamples.first?.pose, point(0))
        XCTAssertLessThanOrEqual(trace.samples.count, 5000)
        XCTAssertThrowsError(try trace.pin(pose: point(2000), timestampS: 2000))
    }

}
