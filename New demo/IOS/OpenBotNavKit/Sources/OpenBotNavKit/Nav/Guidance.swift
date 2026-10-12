import Foundation

public enum StepKind: String {
    case forward
    case turnLeft
    case turnRight
    case turnBack
    case arrive
}

public struct GuidanceStep {
    public let kind: StepKind
    public let distanceM: Double
    public let atLocationId: String?
    public let atLocationName: String?
    public let message: String
}

/// Turn-by-turn instructions derived from the route geometry.
public final class GuidanceBuilder {
    private let mapData: MapData
    private let turnThresholdDeg: Double

    public init(mapData: MapData, turnThresholdDeg: Double = 25.0) {
        self.mapData = mapData
        self.turnThresholdDeg = turnThresholdDeg
    }

    public func build(_ route: Route) -> [GuidanceStep] {
        let polyline = route.polyline
        guard polyline.count >= 2 else {
            let destination = try? mapData.location(route.destinationLocationId)
            return [
                GuidanceStep(
                    kind: .arrive,
                    distanceM: 0.0,
                    atLocationId: destination?.id,
                    atLocationName: destination?.name,
                    message: "Already at " + route.room.name
                ),
            ]
        }

        var steps: [GuidanceStep] = []
        var pendingDistance = 0.0
        var heading: Double?

        for index in 0..<(polyline.count - 1) {
            let start = polyline[index]
            let end = polyline[index + 1]
            let segmentHeading = start.bearingTo(end)
            let segmentLength = start.distanceTo(end)

            if let previousHeading = heading {
                let turn = wrapDeg((segmentHeading - previousHeading) * 180.0 / Double.pi)
                if abs(turn) >= turnThresholdDeg {
                    let kind = turnKind(turn)
                    let location = closestLocation(start)
                    steps.append(
                        GuidanceStep(
                            kind: kind,
                            distanceM: pendingDistance,
                            atLocationId: location?.id,
                            atLocationName: location?.name,
                            message: turnMessage(kind: kind, locationName: location?.name, distanceM: pendingDistance)
                        )
                    )
                    pendingDistance = 0.0
                }
            }
            pendingDistance += segmentLength
            heading = segmentHeading
        }

        let destination = try? mapData.location(route.destinationLocationId)
        steps.append(
            GuidanceStep(
                kind: .arrive,
                distanceM: pendingDistance,
                atLocationId: destination?.id,
                atLocationName: destination?.name,
                message: String(format: "Forward %.1f m, then arrive at %@", pendingDistance, route.room.name)
            )
        )
        return steps
    }

    private func turnKind(_ turnDeg: Double) -> StepKind {
        if abs(turnDeg) >= 150.0 { return .turnBack }
        return turnDeg > 0 ? .turnLeft : .turnRight
    }

    private func turnMessage(kind: StepKind, locationName: String?, distanceM: Double) -> String {
        let where_ = locationName.map { " at " + $0 } ?? ""
        switch kind {
        case .turnLeft:
            return String(format: "Forward %.1f m, then turn left%@", distanceM, where_)
        case .turnRight:
            return String(format: "Forward %.1f m, then turn right%@", distanceM, where_)
        case .turnBack:
            return String(format: "Forward %.1f m, then turn back%@", distanceM, where_)
        case .forward:
            return String(format: "Forward %.1f m", distanceM)
        case .arrive:
            return "Arrive"
        }
    }

    private func closestLocation(_ pose: Pose2D) -> NavLocation? {
        guard let nearest = mapData.nearestLocation(to: pose) else { return nil }
        return nearest.pose.distanceTo(pose) > 1.5 ? nil : nearest
    }
}
