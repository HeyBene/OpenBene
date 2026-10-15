import XCTest
@testable import OpenBotNavKit

/// Episode tests: the simulated OpenBot drives the demo floor while the
/// estimator is fed AR observations exactly the way the AR view controller
/// feeds them. Mirrors the Python harness in shared/navcore.
final class ExecutorTests: XCTestCase {

    func testWheelTelemetryNeverMovesRouteEstimator() throws {
        let harness = try Harness(room: "Room 101", startPose: Pose2D(x: 0, y: 0))
        let marker = try harness.map.marker("mk_entrance")
        try harness.estimator.align(TestSupport.observation(marker: marker, truePose: harness.link.truePose))
        harness.executor.noteMarker(marker.id)
        let original = harness.estimator.pose
        harness.link.telemetry.rpmLeft = 100000
        harness.link.telemetry.rpmRight = -100000
        for time in 0...20 { harness.executor.tick(nowS: Double(time), dtS: 1) }
        XCTAssertEqual(harness.estimator.pose, original)
        XCTAssertEqual(harness.estimator.odometryUpdates, 0)
    }

    private final class Harness {
        let map: MapData
        let link: SimulatedRobotLink
        let estimator: PoseEstimator
        let executor: RouteExecutor
        var timeS = 0.0
        let dtS = 0.05

        init(room: String, startPose: Pose2D) throws {
            map = TestSupport.demoMap()
            link = SimulatedRobotLink(pose: startPose)
            estimator = PoseEstimator(mapData: map)
            executor = RouteExecutor(mapData: map, estimator: estimator, link: link)
            let route = try XCTUnwrap(
                try Router(mapData: map).routeToRoom(startLocationId: "loc_entrance", roomName: room)
            )
            try executor.start(route)
        }

        /// One control step: move the robot, feed it the marker fix it could
        /// really see, then run the executor for one tick.
        func step(noise: (position: Double, yawDeg: Double) = (0.0, 0.0)) -> ExecutorStatus {
            link.tick(dtS: dtS)
            let truePose = link.truePose
            // Continuous camera poses, rather than wheel telemetry, provide
            // motion after the initial image observation.
            estimator.updateFromAr(TestSupport.arFromMap.compose(truePose), timestampS: timeS)
            for marker in map.markers {
                let distance = truePose.distanceTo(marker.pose)
                let heading = abs(truePose.headingErrorTo(marker.pose))
                if distance < 1.2 && heading < 40.0 * Double.pi / 180.0 {
                    if let expected = executor.expectedMarkerId, expected != marker.id { continue }
                    _ = try? estimator.align(TestSupport.observation(marker: marker, truePose: truePose, noise: noise))
                    executor.noteMarker(marker.id)
                    break
                }
            }
            let status = executor.tick(nowS: timeS, dtS: dtS)
            timeS += dtS
            return status
        }

        func run(until seconds: Double, noise: (position: Double, yawDeg: Double) = (0.0, 0.0)) -> ExecutorStatus {
            var status = executor.status()
            while timeS < seconds {
                status = step(noise: noise)
                if status.state == .arrived || status.state == .failed { break }
            }
            return status
        }
    }

    func testDrivesFromTheEntranceToRoom101() throws {
        let harness = try Harness(room: "Room 101", startPose: Pose2D(x: 0, y: 0, yawRad: 0))
        let status = harness.run(until: 240.0)

        XCTAssertEqual(status.state, .arrived, "state was \(status.state.rawValue): \(status.message)")
        let destination = try harness.map.location("loc_room101").pose
        XCTAssertLessThan(harness.link.truePose.distanceTo(destination), 0.5)
        XCTAssertGreaterThanOrEqual(status.usedMarkers.count, 2)
    }

    func testDrivesThroughTheJunctionToRoom102() throws {
        let harness = try Harness(room: "Room 102", startPose: Pose2D(x: 0, y: 0, yawRad: 0))
        let status = harness.run(until: 240.0)

        XCTAssertEqual(status.state, .arrived, "state was \(status.state.rawValue): \(status.message)")
        let destination = try harness.map.location("loc_room102").pose
        XCTAssertLessThan(harness.link.truePose.distanceTo(destination), 0.5)
    }

    func testNoisyFixesStillArrive() throws {
        let harness = try Harness(room: "Room 101", startPose: Pose2D.fromDeg(x: 0.2, y: 0.1, yawDeg: 5.0))
        let status = harness.run(until: 300.0, noise: (position: 0.03, yawDeg: 4.0))

        XCTAssertEqual(status.state, .arrived, "state was \(status.state.rawValue): \(status.message)")
    }

    func testSonarStopsAndResumes() throws {
        let harness = try Harness(room: "Room 102", startPose: Pose2D(x: 0, y: 0, yawRad: 0))
        harness.link.obstacleX = 2.0

        var sawBlocked = false
        while harness.timeS < 240.0 {
            let status = harness.step()
            if status.state == .blocked {
                sawBlocked = true
                break
            }
        }
        XCTAssertTrue(sawBlocked, "the sonar should have stopped the robot")

        harness.link.obstacleX = nil
        let status = harness.run(until: 400.0)
        XCTAssertEqual(status.state, .arrived, "state was \(status.state.rawValue): \(status.message)")
    }

    func testExecutorWithoutAlignmentScansInsteadOfDriving() throws {
        let map = TestSupport.demoMap()
        let link = SimulatedRobotLink(pose: Pose2D(x: 0, y: 0, yawRad: 0))
        let estimator = PoseEstimator(mapData: map)
        let executor = RouteExecutor(mapData: map, estimator: estimator, link: link)
        let route = try XCTUnwrap(try Router(mapData: map).routeToRoom(startLocationId: "loc_entrance", roomName: "Room 101"))
        try executor.start(route)

        var elapsed = 0.0
        var status = executor.status()
        while elapsed < 3.0 {
            link.tick(dtS: 0.05)
            status = executor.tick(nowS: elapsed, dtS: 0.05)
            elapsed += 0.05
        }
        XCTAssertEqual(status.state, .needAnchor)
        XCTAssertEqual(status.expectedMarkerId, "mk_entrance")
        XCTAssertTrue(link.truePose.distanceTo(Pose2D(x: 0, y: 0, yawRad: 0)) < 0.05, "scanning rotates in place")
    }
}
