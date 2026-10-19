import XCTest
@testable import OpenBotNavKit

final class TrajectoryRouteTests: XCTestCase {
    private func p(_ x: Double, _ y: Double = 0, _ yaw: Double = 0) -> Pose2D {
        Pose2D(x: x, y: y, yawRad: yaw)
    }
    private func samples(_ points: [Pose2D]) -> [TrajectorySample] {
        points.enumerated().map { TrajectorySample(pose: $1, timestampS: Double($0) / 30, startsSegment: $0 == 0) }
    }
    private func map(_ points: [Pose2D], manual: [Int]? = nil, includeAnchor: Bool = false) throws -> RecordedMap {
        let trace = samples(points)
        let startIndex = includeAnchor ? 1 : 0
        let start = RecordedWaypoint(name: "起点", pose: points[startIndex], trajectoryIndex: startIndex)
        let nodes = (manual ?? [points.count - 1]).map {
            RecordedWaypoint(name: "节点\($0)", pose: points[$0], trajectoryIndex: $0)
        }
        let anchor = includeAnchor ? RecordedWaypoint(name: "锚点处", pose: points[0], trajectoryIndex: 0) : nil
        return try RecordedMap.planned(name: "转角", anchor: AnchorDefinition.templates[0], start: start,
            waypoints: nodes, samples: trace, anchorStart: anchor)
    }

    func testStraightDenseCaptureNeedsNoAutomaticNodes() throws {
        let points = (0...9000).map { p(Double($0) / 9000 * 20) }
        let route = try map(points)
        XCTAssertEqual(route.executionPoints.count, 2)
        XCTAssertEqual(route.trajectory?.count, points.count)
        XCTAssertEqual(route.distanceM, 20, accuracy: 1e-9)
    }

    func testCornerCannotBeCutByEndpointChord() throws {
        let points = [p(0), p(2), p(2, 2, .pi)]
        let route = try map(points)
        XCTAssertEqual(route.executionPoints.map { $0.pose }, points)
        XCTAssertEqual(route.executionPoints[1].isAutomatic, true)
        XCTAssertFalse(TrajectoryCorridor.containsSegment(from: points[0], to: points[2], centerline: points, radius: 0.15))
        XCTAssertEqual(route.distanceM, 4, accuracy: 1e-9)
        XCTAssertEqual(try route.route().polyline, points)
    }

    func testWholeSegmentCheckFindsNarrowGapBetweenValidEnds() {
        // Only a 0.2 mm uncovered interval at the middle of this line.
        let line = [p(0), p(0, 1), p(0.3002, 1), p(0.3002)]
        XCTAssertTrue(TrajectoryCorridor.contains(point: line[0], centerline: line, radius: 0.15))
        XCTAssertTrue(TrajectoryCorridor.contains(point: line[3], centerline: line, radius: 0.15))
        XCTAssertFalse(TrajectoryCorridor.containsSegment(from: line[0], to: line[3], centerline: line, radius: 0.15))
        XCTAssertTrue(TrajectoryCorridor.containsSegment(from: p(0), to: p(0.3),
            centerline: [p(0), p(0, 1), p(0.3, 1), p(0.3)], radius: 0.15))
    }

    func testCapsuleRoundCapsAndSideBoundary() {
        let line = [p(0), p(2)]
        XCTAssertTrue(TrajectoryCorridor.containsSegment(from: p(-0.15), to: p(2.15), centerline: line, radius: 0.15))
        XCTAssertTrue(TrajectoryCorridor.containsSegment(from: p(0, 0.15), to: p(2, 0.15), centerline: line, radius: 0.15))
        XCTAssertFalse(TrajectoryCorridor.containsSegment(from: p(0, 0.15001), to: p(2, 0.15001), centerline: line, radius: 0.15))
        XCTAssertTrue(TrajectoryCorridor.containsSegment(from: p(0), to: p(0), centerline: [p(0)], radius: 0.15))
        XCTAssertFalse(TrajectoryCorridor.containsSegment(from: p(.nan), to: p(0), centerline: line, radius: 0.15))
    }

    func testMinimumLinksMatchesExhaustiveSearchOnCandidates() throws {
        let points = [p(0), p(0.6, 0.04), p(1, 0), p(1.05, 0.6), p(1, 1), p(1.6, 1.04), p(2, 1)]
        let trace = samples(points)
        let leg = try TrajectoryRoutePlanner.plan(samples: trace, lower: 0, upper: trace.count - 1, fromID: UUID(), toID: UUID())
        let candidates = leg.centerlineIndices
        var best = Int.max
        for mask in 0..<(1 << (candidates.count - 2)) {
            let selected = [candidates[0]] + candidates.dropFirst().dropLast().enumerated().compactMap { bit, value in
                mask & (1 << bit) != 0 ? value : nil
            } + [candidates.last!]
            let visible = zip(selected, selected.dropFirst()).allSatisfy { a, b in
                let subline = candidates.filter { $0 >= a && $0 <= b }.map { points[$0] }
                return TrajectoryCorridor.containsSegment(from: points[a], to: points[b], centerline: subline, radius: leg.planningRadiusM)
            }
            if visible { best = min(best, selected.count) }
        }
        XCTAssertEqual(leg.routeIndices.count, best)
    }

    func testEveryPlannedChordStaysInsideOriginalThirtyCentimeterBand() throws {
        let points = (0...600).map { i -> Pose2D in
            let t = Double(i) / 60
            return p(t, sin(t) * 1.2 + sin(t * 7) * 0.003)
        }
        let route = try map(points)
        XCTAssertGreaterThan(route.executionPoints.count, 2)
        for (a, b) in zip(route.executionPoints, route.executionPoints.dropFirst()) {
            XCTAssertTrue(TrajectoryCorridor.containsSegment(from: a.pose, to: b.pose, centerline: points, radius: 0.15))
        }
    }

    func testManualNodesAndHeadingsAreNeverSkipped() throws {
        let points = [p(0), p(1, 0, .pi), p(2), p(2, 1, -.pi / 2)]
        let route = try map(points, manual: [1, 3])
        XCTAssertEqual(route.executionPoints.filter { $0.isAutomatic != true }.map { $0.pose }, [points[0], points[1], points[3]])
        XCTAssertEqual(route.routePlan?.legs.count, 2)
        XCTAssertEqual(route.executionPoints[1].pose.yawRad, .pi)
        XCTAssertEqual(route.executionLegIndices.count, route.executionPoints.count - 1)
    }

    func testAnchorToStartIsCapturedAndPlannedToo() throws {
        let route = try map([p(0.02), p(0.8), p(0.8, 1)], includeAnchor: true)
        XCTAssertTrue(route.routePlan!.startsAtAnchor)
        XCTAssertEqual(route.executionStart.pose, p(0.02))
        XCTAssertEqual(route.executionPoints.count, 3)
        XCTAssertEqual(try route.route().startLocationId, route.anchorStart?.id.uuidString)
    }

    func testSamePositionManualNodesStillRetainOrientationStep() throws {
        let route = try map([p(0), p(0, 0, .pi), p(1)], manual: [1, 2])
        XCTAssertEqual(route.executionPoints.count, 3)
        XCTAssertEqual(route.executionPoints[1].pose.yawRad, .pi)
        try route.validate()
    }

    func testTrackingGapMustNotBeInventedIntoAChord() throws {
        let trace = [TrajectorySample(pose: p(0), timestampS: 0, startsSegment: true),
                     TrajectorySample(pose: p(1), timestampS: 1, startsSegment: true)]
        XCTAssertThrowsError(try TrajectoryRoutePlanner.plan(samples: trace, lower: 0, upper: 1, fromID: UUID(), toID: UUID()))
    }

    func testArchiveAndPlanSurviveSaveReloadAndIndependentCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecordedMapStore(directory: directory)
        let route = try map([p(0), p(1), p(1, 1)], includeAnchor: true)
        try store.save(route)
        let reopened = try RecordedMapStore(directory: directory).loadAll()
        XCTAssertEqual(reopened, [route])
        let copy = try store.importCopy(from: store.fileURL(for: route))
        XCTAssertNotEqual(copy.id, route.id)
        XCTAssertEqual(copy.trajectory, route.trajectory)
        XCTAssertEqual(copy.routePlan, route.routePlan)
        XCTAssertEqual(copy.executionPoints, route.executionPoints)
    }

    func testInvalidSavedPlanCannotSneakThroughValidation() throws {
        let route = try map([p(0), p(2), p(2, 2)])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(route)) as? [String: Any])
        var plan = object["routePlan"] as! [String: Any]
        var legs = plan["legs"] as! [[String: Any]]
        legs[0]["routeIndices"] = [0, 2] // crosses the corner
        plan["legs"] = legs; object["routePlan"] = plan
        let corrupted = try JSONDecoder().decode(RecordedMap.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try corrupted.validate())
        legs[0]["centerlineIndices"] = [0, 999999]
        plan["legs"] = legs; object["routePlan"] = plan
        let outOfRange = try JSONDecoder().decode(RecordedMap.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try outOfRange.validate())
    }

    func testAutomaticCornerWaitsTwoSecondsAndDoesNotRestoreCaptureYaw() throws {
        let route = try map([p(0), p(2, 0, .pi), p(2, 2, -.pi / 2)])
        let robot = MockRobotLink()
        let executor = WaypointExecutor(map: route, link: robot)
        XCTAssertEqual(executor.config.positionToleranceM, 0.03)
        try executor.start(at: p(0))
        executor.tick(pose: p(0), trackingNormal: true, nowS: 0)
        executor.tick(pose: p(0), trackingNormal: true, nowS: 0.4)
        executor.tick(pose: p(0), trackingNormal: true, nowS: 2.4)
        XCTAssertGreaterThan(robot.lastLeft, 0)
        executor.tick(pose: p(1.8), trackingNormal: true, nowS: 3)
        XCTAssertEqual(executor.waypointIndex, 0) // old .30 m tolerance would cut early
        executor.tick(pose: p(2), trackingNormal: true, nowS: 4)
        XCTAssertEqual(executor.waypointIndex, 1)
        XCTAssertEqual(executor.phase, .waiting)
        executor.tick(pose: p(2), trackingNormal: true, nowS: 5.99)
        XCTAssertEqual(robot.lastLeft, 0)
        executor.tick(pose: p(2), trackingNormal: true, nowS: 6)
        XCTAssertEqual(executor.phase, .alignLine)
        XCTAssertGreaterThan(robot.lastRight, 0) // next segment is +y, not saved yaw pi
        XCTAssertLessThan(robot.lastLeft, 0)
        executor.tick(pose: p(2, 0, .pi / 2), trackingNormal: true, nowS: 7)
        executor.tick(pose: p(2, 0, .pi / 2), trackingNormal: true, nowS: 7.4)
        executor.tick(pose: p(2, 0, .pi / 2), trackingNormal: true, nowS: 9.4)
        XCTAssertGreaterThan(robot.lastLeft, 0)
    }

    func testDeviationStopsBeforeSendingAnotherMotorCommand() throws {
        let route = try map([p(0), p(2), p(2, 2)])
        let robot = MockRobotLink()
        let executor = WaypointExecutor(map: route, link: robot)
        try executor.start(at: p(0))
        executor.tick(pose: p(0), trackingNormal: true, nowS: 0)
        executor.tick(pose: p(0), trackingNormal: true, nowS: 0.4)
        executor.tick(pose: p(0.5), trackingNormal: true, nowS: 2.4)
        XCTAssertGreaterThan(robot.lastLeft, 0)
        executor.tick(pose: p(0.5, 0.16), trackingNormal: true, nowS: 3)
        XCTAssertEqual(executor.phase, .interrupted)
        XCTAssertEqual(robot.lastLeft, 0)
        XCTAssertEqual(robot.lastRight, 0)
    }

    func testSimulatedCornerRouteCompletesInsideRecordedBand() throws {
        let route = try map([p(0), p(2, 0, .pi), p(2, 2, -.pi / 2)])
        let robot = SimulatedRobotLink(pose: p(0))
        let executor = WaypointExecutor(map: route, link: robot)
        try executor.start(at: robot.truePose)
        for step in 0..<12000 {
            robot.tick(dtS: 1.0 / 60)
            executor.tick(pose: robot.truePose, trackingNormal: true, nowS: Double(step) / 60)
            XCTAssertTrue(TrajectoryCorridor.contains(point: robot.truePose,
                centerline: [p(0), p(2), p(2, 2)], radius: 0.15))
            if !executor.active { break }
        }
        XCTAssertEqual(executor.phase, .arrived, executor.message)
        XCTAssertLessThanOrEqual(robot.truePose.distanceTo(p(2, 2)), 0.03)
        XCTAssertLessThanOrEqual(abs(wrapDeg(robot.truePose.yawDeg + 90)), 5)
    }
    func testLargeThirtyHzMapCanBeSavedAndLoadedBeyondOldTwoMBLimit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let points = (0...18000).map { p(Double($0) / 18000 * 20) }
        let route = try map(points)
        let store = RecordedMapStore(directory: directory)
        try store.save(route)
        let file = try store.fileURL(for: route)
        let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize!
        XCTAssertGreaterThan(bytes, 2 * 1024 * 1024)
        XCTAssertEqual(try store.read(from: file), route)
    }

}
