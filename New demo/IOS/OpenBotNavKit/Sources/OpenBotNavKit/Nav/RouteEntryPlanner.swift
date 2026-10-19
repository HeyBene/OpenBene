import Foundation

public struct RouteEntry {
    public let points: [RecordedWaypoint]
    public let legIndices: [Int]
}

/// Connect only to the first recorded leg. Every new edge must remain inside
/// that leg's existing corridor; no extra free floor area is assumed.
public enum RouteEntryPlanner {
    public static let maximumStartDistanceM = 0.75

    /// Reverse the saved prefix, retaining its corridor IDs and every corner.
    /// This changes travel order, never the BLE signs for forward driving.
    public static func traversal(map: RecordedMap, returningFrom nodeID: UUID? = nil) throws -> RouteEntry {
        let points = map.executionPoints, indices = map.executionLegIndices
        guard let nodeID = nodeID else { return RouteEntry(points: points, legIndices: indices) }
        guard map.hasCapturedRoute, map.anchorStart != nil,
              let end = points.firstIndex(where: { $0.id == nodeID && $0.isAutomatic != true }), end > 0,
              indices.count == points.count - 1 else {
            throw RecordingError.invalid("请选择已采集节点返程；地图必须包含锚点旁的支架出发位置。")
        }
        return RouteEntry(points: Array(points[...end].reversed()), legIndices: Array(indices.prefix(end).reversed()))
    }

    public static func canEnter(map: RecordedMap, from pose: Pose2D, returningFrom nodeID: UUID? = nil) -> Bool {
        guard let route = try? traversal(map: map, returningFrom: nodeID),
              let legIndex = route.legIndices.first,
              let plan = map.routePlan, plan.legs.indices.contains(legIndex) else { return false }
        guard TrajectoryCorridor.finite(pose), map.hasCapturedRoute,
              let start = route.points.first,
              pose.distanceTo(start.pose) <= maximumStartDistanceM,
              let samples = map.trajectory else { return false }
        let first = plan.legs[legIndex]
        return TrajectoryCorridor.contains(point: pose, centerline: first.centerline(in: samples), radius: first.planningRadiusM)
    }

    public static func plan(map: RecordedMap, from pose: Pose2D, returningFrom nodeID: UUID? = nil) throws -> RouteEntry {
        let route = try traversal(map: map, returningFrom: nodeID)
        guard canEnter(map: map, from: pose, returningFrom: nodeID),
              let legIndex = route.legIndices.first, let first = map.routePlan?.legs[legIndex],
              let samples = map.trajectory else {
            throw RecordingError.invalid(nodeID == nil ? "请将手机固定在支架上，将车放到原路线首段的带状范围内；无需对准图片中心。" : "请将车移到所选返程节点附近，并保持在返回上一节点的已采集带状范围内。")
        }
        let recordedLine = first.centerline(in: samples)
        let line = nodeID == nil ? recordedLine : Array(recordedLine.reversed()), count = line.count
        var links = Array(repeating: Int.max, count: count)
        var lengths = Array(repeating: Double.infinity, count: count)
        var previous = Array(repeating: -1, count: count)
        for end in 0..<count {
            if TrajectoryCorridor.containsSegment(from: pose, to: line[end], centerline: line, radius: first.planningRadiusM) {
                links[end] = 1; lengths[end] = pose.distanceTo(line[end])
            }
            for begin in 0..<end where links[begin] != Int.max {
                let n = links[begin] + 1, length = lengths[begin] + line[begin].distanceTo(line[end])
                if n > links[end] || (n == links[end] && length >= lengths[end]) { continue }
                if TrajectoryCorridor.containsSegment(from: line[begin], to: line[end],
                    centerline: Array(line[begin...end]), radius: first.planningRadiusM) {
                    links[end] = n; lengths[end] = length; previous[end] = begin
                }
            }
        }
        guard links[count - 1] != Int.max else {
            throw RecordingError.invalid("无法在已采集首段范围内接入路线，请将车移回原路线。")
        }
        var indices: [Int] = [], index = count - 1
        while index >= 0 { indices.append(index); index = previous[index] }
        indices.reverse()
        let firstTargetCount = route.legIndices.prefix(while: { $0 == legIndex }).count
        var points = [RecordedWaypoint(name: "本次出发位置", pose: pose)]
        for i in indices.dropLast() {
            points.append(RecordedWaypoint(name: "首段接入子节点", pose: line[i], isAutomatic: true))
        }
        let entryCount = points.count
        points.append(contentsOf: route.points.dropFirst(firstTargetCount))
        let legIndices = Array(repeating: legIndex, count: entryCount) + route.legIndices.dropFirst(firstTargetCount)
        return RouteEntry(points: points, legIndices: Array(legIndices))
    }
}
