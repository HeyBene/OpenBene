import Foundation

/// A printed anchor sheet lying on the floor.
///
/// `pose` is the pose of the sheet in the map frame and `pose.yawRad` is the map
/// direction of the marker image +y axis, that is the direction from the bottom
/// edge of the print to its top edge.
public struct Marker: Equatable {
    public let id: String
    public let kind: String
    public let payload: String
    public let arImage: String
    public let sizeM: Double
    public let pose: Pose2D
}

/// A graph node the router can start from or drive through.
public struct NavLocation: Equatable {
    public let id: String
    public let name: String
    public let pose: Pose2D
    public let markerId: String?
}

public struct Edge: Equatable {
    public let id: String
    public let fromId: String
    public let toId: String
    public let path: [Pose2D]
    public let bidirectional: Bool
    public let direction: String

    public func distanceM() -> Double {
        var total = 0.0
        for index in 0..<max(0, path.count - 1) {
            total += path[index].distanceTo(path[index + 1])
        }
        return total
    }

    /// The path oriented so that it starts at `startLocationId`.
    public func pathFrom(_ startLocationId: String) throws -> [Pose2D] {
        if startLocationId == fromId { return path }
        if startLocationId == toId { return path.reversed() }
        throw MapError.edgeDoesNotContainLocation(edge: id, location: startLocationId)
    }

    public func otherEnd(_ locationId: String) throws -> String {
        if locationId == fromId { return toId }
        if locationId == toId { return fromId }
        throw MapError.edgeDoesNotContainLocation(edge: id, location: locationId)
    }
}

public struct Room: Equatable {
    public let id: String
    public let name: String
    public let locationId: String
}

public enum MapError: Error, CustomStringConvertible {
    case unknownMarker(String)
    case unknownLocation(String)
    case unknownRoom(String)
    case edgeDoesNotContainLocation(edge: String, location: String)
    case invalidMap(String)

    public var description: String {
        switch self {
        case .unknownMarker(let id): return "unknown marker \(id)"
        case .unknownLocation(let id): return "unknown location \(id)"
        case .unknownRoom(let id): return "unknown room \(id)"
        case .edgeDoesNotContainLocation(let edge, let location):
            return "\(location) is not part of edge \(edge)"
        case .invalidMap(let reason): return "invalid map: \(reason)"
        }
    }
}

/// Parsed demo map: markers, locations, edges and rooms.
public final class MapData {
    public let mapId: String
    public let name: String
    public let markers: [Marker]
    public let locations: [NavLocation]
    public let edges: [Edge]
    public let rooms: [Room]

    private let markersById: [String: Marker]
    private let markersByPayload: [String: Marker]
    private let locationsById: [String: NavLocation]
    private let roomsById: [String: Room]
    private let adjacency: [String: [Edge]]

    public init(
        mapId: String,
        name: String,
        markers: [Marker],
        locations: [NavLocation],
        edges: [Edge],
        rooms: [Room]
    ) {
        self.mapId = mapId
        self.name = name
        self.markers = markers
        self.locations = locations
        self.edges = edges
        self.rooms = rooms
        self.markersById = Dictionary(uniqueKeysWithValues: markers.map { ($0.id, $0) })
        self.markersByPayload = Dictionary(uniqueKeysWithValues: markers.map { ($0.payload, $0) })
        self.locationsById = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
        self.roomsById = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })

        var adjacency: [String: [Edge]] = [:]
        for location in locations { adjacency[location.id] = [] }
        for edge in edges {
            adjacency[edge.fromId, default: []].append(edge)
            if edge.bidirectional {
                adjacency[edge.toId, default: []].append(edge)
            }
        }
        self.adjacency = adjacency
    }

    public static func load(path: String) throws -> MapData {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return try parse(text)
    }

    public static func parse(_ json: String) throws -> MapData {
        guard let data = json.data(using: .utf8) else { throw MapError.invalidMap("not utf8") }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MapError.invalidMap("root is not an object")
        }

        let markers = (root["markers"] as? [[String: Any]] ?? []).compactMap { item -> Marker? in
            guard let id = item["id"] as? String, let poseRaw = item["pose"] as? [String: Any] else { return nil }
            return Marker(
                id: id,
                kind: item["kind"] as? String ?? "qr",
                payload: item["payload"] as? String ?? "openbene:" + id,
                arImage: item["ar_image"] as? String ?? id,
                sizeM: double(item["size_m"]) ?? 0.2,
                pose: pose(from: poseRaw)
            )
        }

        let locations = (root["locations"] as? [[String: Any]] ?? []).compactMap { item -> NavLocation? in
            guard let id = item["id"] as? String, let poseRaw = item["pose"] as? [String: Any] else { return nil }
            let markerId = item["marker_id"] as? String
            return NavLocation(
                id: id,
                name: item["name"] as? String ?? id,
                pose: pose(from: poseRaw),
                markerId: (markerId?.isEmpty ?? true) ? nil : markerId
            )
        }

        var edges: [Edge] = []
        for item in root["edges"] as? [[String: Any]] ?? [] {
            guard let id = item["id"] as? String,
                  let from = item["from"] as? String,
                  let to = item["to"] as? String,
                  let pathRaw = item["path"] as? [[String: Any]]
            else { continue }
            let path = pathRaw.map { pose(from: $0) }
            if path.count < 2 {
                throw MapError.invalidMap("edge \(id) needs two path points")
            }
            edges.append(
                Edge(
                    id: id,
                    fromId: from,
                    toId: to,
                    path: path,
                    bidirectional: bool(item["bidirectional"]) ?? true,
                    direction: item["direction"] as? String ?? "forward"
                )
            )
        }

        let rooms = (root["rooms"] as? [[String: Any]] ?? []).compactMap { item -> Room? in
            guard let id = item["id"] as? String,
                  let name = item["name"] as? String,
                  let locationId = item["location_id"] as? String
            else { return nil }
            return Room(id: id, name: name, locationId: locationId)
        }

        return MapData(
            mapId: root["map_id"] as? String ?? "map",
            name: root["name"] as? String ?? "map",
            markers: markers,
            locations: locations,
            edges: edges,
            rooms: rooms
        )
    }

    public func marker(_ markerId: String) throws -> Marker {
        guard let marker = markersById[markerId] else { throw MapError.unknownMarker(markerId) }
        return marker
    }

    public func markerForPayload(_ payload: String) -> Marker? {
        markersByPayload[payload.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    public func location(_ locationId: String) throws -> NavLocation {
        guard let location = locationsById[locationId] else { throw MapError.unknownLocation(locationId) }
        return location
    }

    public func room(_ roomId: String) throws -> Room {
        guard let room = roomsById[roomId] else { throw MapError.unknownRoom(roomId) }
        return room
    }

    public func roomsNamed(_ name: String) -> [Room] {
        rooms.filter { $0.name.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespaces)) == .orderedSame }
    }

    public func roomNames() -> [String] {
        Array(Set(rooms.map { $0.name })).sorted()
    }

    public func edgesFrom(_ locationId: String) -> [Edge] {
        adjacency[locationId] ?? []
    }

    public func hasLocation(_ locationId: String) -> Bool {
        locationsById[locationId] != nil
    }

    public func nearestLocation(to pose: Pose2D) -> NavLocation? {
        locations.min { $0.pose.distanceTo(pose) < $1.pose.distanceTo(pose) }
    }

    private static func pose(from raw: [String: Any]) -> Pose2D {
        Pose2D.fromDeg(
            x: double(raw["x"]) ?? 0.0,
            y: double(raw["y"]) ?? 0.0,
            yawDeg: double(raw["yaw_deg"]) ?? 0.0
        )
    }

    /// JSONSerialization hands numbers back as NSNumber, which bridges to any
    /// numeric Swift type, so go through NSNumber instead of casting blindly.
    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private static func bool(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        if let flag = value as? Bool { return flag }
        return nil
    }
}
