import Foundation

extension RecordedMap {
    public var hasCapturedRoute: Bool { version == 2 && trajectory != nil && routePlan != nil }
    public var executionStart: RecordedWaypoint { anchorStart ?? start }

    /// Raw capture history is deliberately absent from this display/drive path.
    public var executionPoints: [RecordedWaypoint] {
        guard let plan = routePlan, let samples = trajectory else { return [start] + waypoints }
        let manual = (anchorStart.map { [$0] } ?? []) + [start] + waypoints
        guard plan.legs.count == manual.count - 1,
              plan.legs.allSatisfy({ !$0.routeIndices.isEmpty && $0.routeIndices.allSatisfy(samples.indices.contains) })
        else { return [start] + waypoints }
        var result = [executionStart]
        for (legIndex, leg) in plan.legs.enumerated() {
            for (subIndex, index) in leg.routeIndices.dropFirst().dropLast().enumerated() {
                // Stable IDs allow the graph preview and AR view to share a route.
                let prefix = String(leg.fromID.uuidString.prefix(24))
                let id = UUID(uuidString: prefix + String(format: "%012x", index))!
                result.append(RecordedWaypoint(id: id, name: "子节点 \(legIndex + 1).\(subIndex + 1)",
                    pose: samples[index].pose, trajectoryIndex: index, isAutomatic: true))
            }
            result.append(manual[legIndex + 1])
        }
        return result
    }

    public var executionLegIndices: [Int] {
        guard let plan = routePlan else { return [] }
        return plan.legs.enumerated().flatMap { index, leg in
            Array(repeating: index, count: max(1, leg.routeIndices.count - 1))
        }
    }

    public static func planned(name: String, anchor: AnchorDefinition, start: RecordedWaypoint,
                               waypoints: [RecordedWaypoint], samples: [TrajectorySample],
                               anchorStart: RecordedWaypoint? = nil) throws -> RecordedMap {
        let points = (anchorStart.map { [$0] } ?? []) + [start] + waypoints
        guard !waypoints.isEmpty else { throw RecordingError.invalid("请至少采集一个节点。") }
        var legs: [PlannedTrajectoryLeg] = []
        for (from, to) in zip(points, points.dropFirst()) {
            guard let lower = from.trajectoryIndex, let upper = to.trajectoryIndex else {
                throw RecordingError.invalid("缺少节点对应的轨迹，请重新采集地图。")
            }
            legs.append(try TrajectoryRoutePlanner.plan(samples: samples, lower: lower, upper: upper,
                fromID: from.id, toID: to.id))
        }
        let map = RecordedMap(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            anchor: anchor, start: start, waypoints: waypoints, trajectory: samples,
            routePlan: CapturedRoutePlan(startsAtAnchor: anchorStart != nil, legs: legs), anchorStart: anchorStart)
        try map.validate()
        return map
    }

    func validateCapturedRoute() throws {
        func invalid() -> RecordingError { .invalid("轨迹或子节点路线无效，请重新采集地图。") }
        guard let samples = trajectory, !samples.isEmpty, samples.count <= 54_000,
              let plan = routePlan, plan.startsAtAnchor == (anchorStart != nil),
              samples[0].startsSegment,
              samples.allSatisfy({ TrajectoryCorridor.finite($0.pose) && $0.timestampS.isFinite }) else { throw invalid() }
        for (a, b) in zip(samples, samples.dropFirst()) {
            guard b.timestampS >= a.timestampS,
                  b.startsSegment || b.timestampS - a.timestampS <= 0.6 + 1e-9 else { throw invalid() }
        }
        if let anchorStart = anchorStart {
            guard anchorStart.trajectoryIndex == 0 else { throw invalid() }
        }
        let points = (anchorStart.map { [$0] } ?? []) + [start] + waypoints
        guard plan.legs.count == points.count - 1 else { throw invalid() }
        for (index, leg) in plan.legs.enumerated() {
            let from = points[index], to = points[index + 1]
            guard leg.fromID == from.id, leg.toID == to.id,
                  let lower = from.trajectoryIndex, let upper = to.trajectoryIndex,
                  lower >= 0, upper >= lower, upper < samples.count,
                  leg.lowerSampleIndex == lower, leg.upperSampleIndex == upper,
                  samples[lower].pose == from.pose, samples[upper].pose == to.pose,
                  leg.halfWidthM == 0.15, leg.controlMarginM == 0.04,
                  leg.simplificationErrorM.isFinite, (0...0.030001).contains(leg.simplificationErrorM),
                  !leg.centerlineIndices.isEmpty, leg.centerlineIndices.count <= TrajectoryRoutePlanner.maxCandidates,
                  leg.centerlineIndices.first == lower, leg.centerlineIndices.last == upper,
                  leg.routeIndices.first == lower, leg.routeIndices.last == upper,
                  Set(leg.routeIndices).count == leg.routeIndices.count,
                  Set(leg.routeIndices).isSubset(of: Set(leg.centerlineIndices)) else { throw invalid() }
            for indices in [leg.centerlineIndices, leg.routeIndices] {
                guard indices.allSatisfy({ (lower...upper).contains($0) }),
                      zip(indices, indices.dropFirst()).allSatisfy({ $0 < $1 }) else { throw invalid() }
            }
            if upper > lower {
                guard ((lower + 1)...upper).allSatisfy({ !samples[$0].startsSegment }) else {
                    throw RecordingError.invalid("人工节点之间存在定位中断，请重新采集。")
                }
            }
            // Certify the simplification bound against every archived sample.
            for (a, b) in zip(leg.centerlineIndices, leg.centerlineIndices.dropFirst()) {
                guard (a...b).allSatisfy({ TrajectoryCorridor.distance(samples[$0].pose,
                    to: samples[a].pose, samples[b].pose) <= leg.simplificationErrorM + 1e-9 }) else { throw invalid() }
            }
            let line = leg.centerline(in: samples)
            for (a, b) in zip(leg.routeIndices, leg.routeIndices.dropFirst()) {
                guard TrajectoryCorridor.containsSegment(from: samples[a].pose, to: samples[b].pose,
                    centerline: line, radius: leg.planningRadiusM) else { throw invalid() }
            }
        }
    }
}
