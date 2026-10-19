import Foundation

/// A reference print, independent of any floor plan or preconfigured location.
public struct AnchorDefinition: Codable, Equatable, Identifiable {
    public let id: String
    public let imageName: String
    public let sizeM: Double
    public var payload: String { "openbene:" + id }
    public var title: String {
        let index = Self.templates.firstIndex { $0.id == id } ?? 0
        return "标记 \(index + 1)"
    }

    public init(id: String, imageName: String, sizeM: Double = 0.2) {
        self.id = id
        self.imageName = imageName
        self.sizeM = sizeM
    }

    public static let templates: [AnchorDefinition] = [
        "entrance", "junction", "room101", "room102"
    ].map { AnchorDefinition(id: "mk_" + $0, imageName: "openbene_mk_" + $0) }
}

public struct RecordedWaypoint: Codable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let pose: Pose2D
    public let trajectoryIndex: Int?
    public let isAutomatic: Bool?

    public init(id: UUID = UUID(), name: String, pose: Pose2D, trajectoryIndex: Int? = nil, isAutomatic: Bool = false) {
        self.id = id
        self.name = name
        self.pose = pose
        self.trajectoryIndex = trajectoryIndex
        self.isAutomatic = isAutomatic ? true : nil
    }
}

public enum RecordingError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        if case .invalid(let reason) = self { return reason }
        return nil
    }
}

/// Positions are measured from the centre of the recognised print. Its printed
/// arrow defines +x; the recorded camera heading is retained at every node.
public struct RecordedMap: Codable, Equatable, Identifiable {
    public let version: Int
    public let id: UUID
    public let name: String
    public let anchor: AnchorDefinition
    public let start: RecordedWaypoint
    public let waypoints: [RecordedWaypoint]
    public let trajectory: [TrajectorySample]?
    public let routePlan: CapturedRoutePlan?
    public let anchorStart: RecordedWaypoint?

    public init(id: UUID = UUID(), name: String, anchor: AnchorDefinition,
                start: RecordedWaypoint, waypoints: [RecordedWaypoint],
                trajectory: [TrajectorySample]? = nil, routePlan: CapturedRoutePlan? = nil,
                anchorStart: RecordedWaypoint? = nil) {
        version = trajectory == nil ? 1 : 2
        self.id = id
        self.name = name
        self.anchor = anchor
        self.start = start
        self.waypoints = waypoints
        self.trajectory = trajectory
        self.routePlan = routePlan
        self.anchorStart = anchorStart
    }

    public func validate() throws {
        guard version == 1 || version == 2 else { throw RecordingError.invalid("地图版本不受支持。") }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecordingError.invalid("请输入地图名称。")
        }
        guard AnchorDefinition.templates.contains(where: { $0.id == anchor.id && $0.imageName == anchor.imageName }),
              anchor.sizeM.isFinite, (0.05...1.0).contains(anchor.sizeM) else {
            throw RecordingError.invalid("定位标记或打印尺寸无效。")
        }
        guard !waypoints.isEmpty, waypoints.count <= 256 else {
            throw RecordingError.invalid("请采集 1 至 256 个节点。")
        }
        let points = (anchorStart.map { [$0] } ?? []) + [start] + waypoints
        guard Set(points.map { $0.id }).count == points.count,
              points.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                $0.pose.x.isFinite && $0.pose.y.isFinite && $0.pose.yawRad.isFinite && $0.isAutomatic != true }) else {
            throw RecordingError.invalid("节点名称、编号或位置朝向无效。")
        }
        if version == 2 { try validateCapturedRoute() }
        else if trajectory != nil || routePlan != nil || anchorStart != nil {
            throw RecordingError.invalid("旧地图不应包含未经校验的轨迹路线。")
        }
    }

    public var distanceM: Double {
        let points = executionPoints
        return zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.pose.distanceTo($1.1.pose) }
    }

    /// The original graph renderer/router can display the captured sequence.
    /// Only the start is anchored; intermediate nodes require no extra print.
    public func mapData() throws -> MapData {
        try validate()
        let points = executionPoints
        let locations = points.enumerated().map { index, point in
            NavLocation(id: point.id.uuidString, name: point.name, pose: point.pose,
                        markerId: index == 0 ? anchor.id : nil)
        }
        let edges = zip(points, points.dropFirst()).enumerated().map { index, pair in
            Edge(id: "segment_\(index)", fromId: pair.0.id.uuidString, toId: pair.1.id.uuidString,
                 path: [pair.0.pose, pair.1.pose], bidirectional: false, direction: "forward")
        }
        let last = waypoints.last!
        return MapData(mapId: id.uuidString, name: name,
            markers: [Marker(id: anchor.id, kind: "qr", payload: anchor.payload,
                             arImage: anchor.imageName, sizeM: anchor.sizeM, pose: Pose2D(x: 0, y: 0))],
            locations: locations, edges: edges,
            rooms: [Room(id: last.id.uuidString, name: last.name, locationId: last.id.uuidString)])
    }

    public func route() throws -> Route {
        let data = try mapData()
        // Replay the acquisition order directly; no graph search or reversal.
        let legs = data.edges.map { RouteLeg(edge: $0, fromId: $0.fromId, toId: $0.toId, path: $0.path) }
        return Route(startLocationId: executionStart.id.uuidString,
                     destinationLocationId: waypoints.last!.id.uuidString,
                     room: data.rooms[0], legs: legs,
                     polyline: executionPoints.map { $0.pose }, totalDistanceM: distanceM)
    }
}

public final class MapCapture {
    public let anchor: AnchorDefinition
    public private(set) var start: RecordedWaypoint?
    public private(set) var waypoints: [RecordedWaypoint] = []

    public init(anchor: AnchorDefinition) { self.anchor = anchor }

    public func recordStart(pose: Pose2D, trajectoryIndex: Int? = nil) throws {
        try checkPose(pose)
        guard waypoints.isEmpty else { throw RecordingError.invalid("先撤销已有节点，再重设起点。") }
        start = RecordedWaypoint(name: "起点", pose: pose, trajectoryIndex: trajectoryIndex)
    }

    public func addWaypoint(name: String, pose: Pose2D, trajectoryIndex: Int? = nil) throws {
        guard start != nil else { throw RecordingError.invalid("请先采集起点。") }
        try checkPose(pose)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, waypoints.count < 256 else { throw RecordingError.invalid("请输入节点名称，节点上限为 256 个。") }
        waypoints.append(RecordedWaypoint(name: trimmed, pose: pose, trajectoryIndex: trajectoryIndex))
    }

    public func undo() {
        if !waypoints.isEmpty { waypoints.removeLast() } else { start = nil }
    }

    public func finish(name: String) throws -> RecordedMap {
        guard let start = start else { throw RecordingError.invalid("请先采集起点。") }
        let map = RecordedMap(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                              anchor: anchor, start: start, waypoints: waypoints)
        try map.validate()
        return map
    }

    private func checkPose(_ pose: Pose2D) throws {
        guard pose.x.isFinite, pose.y.isFinite, pose.yawRad.isFinite else {
            throw RecordingError.invalid("位置不可用，请重新识别锚点。")
        }
    }
}
