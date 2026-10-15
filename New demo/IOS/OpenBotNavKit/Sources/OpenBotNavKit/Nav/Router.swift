import Foundation

public struct RouteLeg {
    public let edge: Edge
    public let fromId: String
    public let toId: String
    public let path: [Pose2D]

    public var distanceM: Double {
        var total = 0.0
        for index in 0..<max(0, path.count - 1) {
            total += path[index].distanceTo(path[index + 1])
        }
        return total
    }
}

public struct Route {
    public let startLocationId: String
    public let destinationLocationId: String
    public let room: Room
    public let legs: [RouteLeg]
    public let polyline: [Pose2D]
    public let totalDistanceM: Double

    public func locationSequence() -> [String] {
        [startLocationId] + legs.map { $0.toId }
    }
}

/// Dijkstra routing over the demo map graph, mirroring the Python router.
public final class Router {
    private let mapData: MapData

    public init(mapData: MapData) {
        self.mapData = mapData
    }

    public func routeToRoom(startLocationId: String, roomName: String) throws -> Route? {
        var best: Route?
        for room in mapData.roomsNamed(roomName) {
            guard let route = try routeToLocation(
                startLocationId: startLocationId,
                destinationLocationId: room.locationId,
                room: room
            ) else { continue }
            if best == nil || route.totalDistanceM < best!.totalDistanceM {
                best = route
            }
        }
        return best
    }

    public func routeToLocation(
        startLocationId: String,
        destinationLocationId: String,
        room: Room? = nil
    ) throws -> Route? {
        guard mapData.hasLocation(startLocationId) else { throw MapError.unknownLocation(startLocationId) }
        guard mapData.hasLocation(destinationLocationId) else { throw MapError.unknownLocation(destinationLocationId) }

        let resolvedRoom = try room ?? Room(
            id: destinationLocationId,
            name: mapData.location(destinationLocationId).name,
            locationId: destinationLocationId
        )

        if startLocationId == destinationLocationId {
            return Route(
                startLocationId: startLocationId,
                destinationLocationId: destinationLocationId,
                room: resolvedRoom,
                legs: [],
                polyline: [try mapData.location(startLocationId).pose],
                totalDistanceM: 0.0
            )
        }

        let (previous, distance) = dijkstra(startLocationId)
        guard distance[destinationLocationId] != nil else { return nil }

        var ordered: [String] = [destinationLocationId]
        var cursor = destinationLocationId
        while cursor != startLocationId {
            guard let parent = previous[cursor] else { return nil }
            ordered.insert(parent, at: 0)
            cursor = parent
        }

        var legs: [RouteLeg] = []
        for index in 0..<max(0, ordered.count - 1) {
            let fromId = ordered[index]
            let toId = ordered[index + 1]
            guard let edge = mapData.edgesFrom(fromId).first(where: { (try? $0.otherEnd(fromId)) == toId }) else {
                throw MapError.invalidMap("no edge between \(fromId) and \(toId)")
            }
            legs.append(RouteLeg(edge: edge, fromId: fromId, toId: toId, path: try edge.pathFrom(fromId)))
        }

        var polyline: [Pose2D] = []
        for leg in legs {
            var points = leg.path
            if let last = polyline.last, let first = points.first, last.distanceTo(first) < 1e-6 {
                points.removeFirst()
            }
            polyline.append(contentsOf: points)
        }

        var total = 0.0
        for index in 0..<max(0, polyline.count - 1) {
            total += polyline[index].distanceTo(polyline[index + 1])
        }

        return Route(
            startLocationId: startLocationId,
            destinationLocationId: destinationLocationId,
            room: resolvedRoom,
            legs: legs,
            polyline: polyline,
            totalDistanceM: total
        )
    }

    /// The demo graphs are tiny, so the minimum is found by scanning instead of
    /// keeping a heap.
    private func dijkstra(_ startLocationId: String) -> (previous: [String: String], distance: [String: Double]) {
        var distance: [String: Double] = [startLocationId: 0.0]
        var previous: [String: String] = [:]
        var settled = Set<String>()

        while true {
            var current: String?
            var best = Double.infinity
            for (node, value) in distance where !settled.contains(node) {
                if value < best {
                    best = value
                    current = node
                }
            }
            guard let node = current else { break }
            settled.insert(node)

            for edge in mapData.edgesFrom(node) {
                guard let neighbour = try? edge.otherEnd(node) else { continue }
                let candidate = best + edge.distanceM()
                if candidate < (distance[neighbour] ?? .infinity) {
                    distance[neighbour] = candidate
                    previous[neighbour] = node
                }
            }
        }
        return (previous, distance)
    }
}
