import Foundation
import XCTest
@testable import OpenBotNavKit

enum RecordedTestSupport {
    static func map(startYaw: Double = -130) -> RecordedMap {
        RecordedMap(name: "我的航线", anchor: AnchorDefinition.templates[0],
            start: RecordedWaypoint(name: "起点", pose: .fromDeg(x: 0, y: 0, yawDeg: startYaw)),
            waypoints: [
                RecordedWaypoint(name: "第一个节点", pose: .fromDeg(x: 2, y: 0, yawDeg: 180)),
                RecordedWaypoint(name: "最后节点", pose: .fromDeg(x: 2, y: 2, yawDeg: -45))
            ])
    }
}

final class RecordedMapTests: XCTestCase {
    func testCaptureRequiresStartAndRetainsNodeOrderAndHeadings() throws {
        let capture = MapCapture(anchor: AnchorDefinition.templates[0])
        XCTAssertThrowsError(try capture.addWaypoint(name: "节点", pose: Pose2D(x: 1, y: 0)))
        try capture.recordStart(pose: .fromDeg(x: -0.5, y: 0.2, yawDeg: 75))
        try capture.addWaypoint(name: "  节点甲  ", pose: .fromDeg(x: 1, y: 0.2, yawDeg: -170))
        try capture.addWaypoint(name: "节点乙", pose: .fromDeg(x: 1, y: 2, yawDeg: 25))
        let map = try capture.finish(name: "  测试地图  ")
        XCTAssertEqual(map.name, "测试地图")
        XCTAssertEqual(map.start.pose.yawDeg, 75, accuracy: 1e-9)
        XCTAssertEqual(map.waypoints.map { $0.name }, ["节点甲", "节点乙"])
        XCTAssertEqual(map.waypoints[0].pose.yawDeg, -170, accuracy: 1e-9)
        XCTAssertEqual(map.waypoints[1].pose.yawDeg, 25, accuracy: 1e-9)
        XCTAssertThrowsError(try capture.recordStart(pose: Pose2D(x: 3, y: 3)))
    }

    func testUndoReturnsToStartAndEmptyCaptureCannotBeSaved() throws {
        let capture = MapCapture(anchor: AnchorDefinition.templates[0])
        XCTAssertThrowsError(try capture.finish(name: "地图"))
        try capture.recordStart(pose: Pose2D(x: 0, y: 0))
        XCTAssertThrowsError(try capture.finish(name: "地图"))
        try capture.addWaypoint(name: "节点", pose: Pose2D(x: 1, y: 1))
        capture.undo()
        XCTAssertTrue(capture.waypoints.isEmpty)
        XCTAssertNotNil(capture.start)
        capture.undo()
        XCTAssertNil(capture.start)
    }

    func testCapturedRouteContainsEveryNodeWithoutPredefinedRooms() throws {
        let map = RecordedTestSupport.map()
        let graph = try map.mapData()
        let route = try map.route()
        XCTAssertEqual(graph.markers.count, 1)
        XCTAssertEqual(graph.markers[0].pose, Pose2D(x: 0, y: 0))
        XCTAssertEqual(graph.locations.map { $0.pose }, ([map.start] + map.waypoints).map { $0.pose })
        XCTAssertEqual(route.locationSequence(), ([map.start] + map.waypoints).map { $0.id.uuidString })
        XCTAssertEqual(route.legs.count, 2)
        XCTAssertEqual(route.totalDistanceM, 4, accuracy: 1e-9)
        XCTAssertEqual(graph.roomNames(), ["最后节点"])
        XCTAssertTrue(graph.locations.dropFirst().allSatisfy { $0.markerId == nil })
    }

    func testCaptureRejectsInvalidPoseAndEmptyName() throws {
        let capture = MapCapture(anchor: AnchorDefinition.templates[0])
        XCTAssertThrowsError(try capture.recordStart(pose: Pose2D(x: .nan, y: 0)))
        try capture.recordStart(pose: Pose2D(x: 0, y: 0))
        XCTAssertThrowsError(try capture.addWaypoint(name: " ", pose: Pose2D(x: 1, y: 0)))
        XCTAssertThrowsError(try capture.addWaypoint(name: "节点", pose: Pose2D(x: 1, y: 0, yawRad: .infinity)))
    }
}

final class RecordedMapStoreTests: XCTestCase {
    private var directory: URL!
    private var store: RecordedMapStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = RecordedMapStore(directory: directory)
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func testStartsEmptyWithoutInstallingAPresetMap() throws {
        XCTAssertTrue(try store.loadAll().isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    func testRestartAndExportPreserveEveryPose() throws {
        let map = RecordedTestSupport.map()
        try store.save(map)
        let file = try store.fileURL(for: map)
        XCTAssertEqual(try JSONDecoder().decode(RecordedMap.self, from: Data(contentsOf: file)), map)
        let restarted = RecordedMapStore(directory: directory)
        XCTAssertEqual(try restarted.loadAll(), [map])
        XCTAssertThrowsError(try restarted.save(map))
    }

    func testImportCreatesIndependentCopyAndDeletePersists() throws {
        let map = RecordedTestSupport.map()
        try store.save(map)
        let copied = try store.importCopy(from: store.fileURL(for: map))
        XCTAssertNotEqual(copied.id, map.id)
        XCTAssertEqual(copied.waypoints, map.waypoints)
        try store.delete(map)
        XCTAssertEqual(try RecordedMapStore(directory: directory).loadAll(), [copied])
    }

    func testBrokenFileIsPreservedAndGoodMapStillLoads() throws {
        let map = RecordedTestSupport.map()
        try store.save(map)
        let file = directory.appendingPathComponent("broken.json")
        let broken = Data("{bad json}".utf8)
        try broken.write(to: file)
        XCTAssertEqual(try store.loadAll(), [map])
        XCTAssertEqual(store.warnings.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), broken)
    }

    func testUnsupportedVersionCannotBeImported() throws {
        _ = try store.loadAll()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(RecordedTestSupport.map())) as? [String: Any])
        json["version"] = 999
        let file = directory.appendingPathComponent("future.json")
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        XCTAssertThrowsError(try store.importCopy(from: file))
        XCTAssertTrue(try store.loadAll().isEmpty)
    }
}
