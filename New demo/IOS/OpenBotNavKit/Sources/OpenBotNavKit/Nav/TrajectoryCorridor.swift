import Foundation

/// Continuous segment containment in the union of radius-r capsules around a
/// polyline. Interval coverage tests the entire segment, not a set of probes.
public enum TrajectoryCorridor {
    private static let epsilon = 1e-9

    public static func distance(_ p: Pose2D, to a: Pose2D, _ b: Pose2D) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let length2 = dx * dx + dy * dy
        if length2 < 1e-20 { return p.distanceTo(a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length2))
        return hypot(p.x - a.x - t * dx, p.y - a.y - t * dy)
    }

    public static func contains(point: Pose2D, centerline: [Pose2D], radius: Double) -> Bool {
        guard finite(point), radius.isFinite, radius >= 0, !centerline.isEmpty else { return false }
        if centerline.count == 1 { return point.distanceTo(centerline[0]) <= radius + epsilon }
        return zip(centerline, centerline.dropFirst()).contains { distance(point, to: $0, $1) <= radius + epsilon }
    }

    public static func containsSegment(from p: Pose2D, to q: Pose2D,
                                       centerline: [Pose2D], radius: Double) -> Bool {
        guard finite(p), finite(q), radius.isFinite, radius > 0, !centerline.isEmpty else { return false }
        if p.distanceTo(q) < epsilon { return contains(point: p, centerline: centerline, radius: radius) }
        var intervals: [(Double, Double)] = []
        if centerline.count == 1 {
            if let value = circleInterval(p, q, centerline[0], radius) { intervals.append(value) }
        } else {
            for (a, b) in zip(centerline, centerline.dropFirst()) {
                // Cheap broad phase, particularly useful for long captured paths.
                if max(p.x, q.x) < min(a.x, b.x) - radius || min(p.x, q.x) > max(a.x, b.x) + radius ||
                   max(p.y, q.y) < min(a.y, b.y) - radius || min(p.y, q.y) > max(a.y, b.y) + radius { continue }
                if let interval = capsuleInterval(p, q, a, b, radius) { intervals.append(interval) }
            }
        }
        intervals.sort { $0.0 < $1.0 }
        var covered = 0.0
        for interval in intervals {
            if interval.0 > covered + epsilon { return false }
            covered = max(covered, interval.1)
            if covered >= 1 - epsilon { return true }
        }
        return false
    }

    private static func capsuleInterval(_ p: Pose2D, _ q: Pose2D, _ a: Pose2D,
                                         _ b: Pose2D, _ radius: Double) -> (Double, Double)? {
        let length = a.distanceTo(b)
        if length < epsilon { return circleInterval(p, q, a, radius) }
        let ux = (b.x - a.x) / length, uy = (b.y - a.y) / length
        let px = (p.x - a.x) * ux + (p.y - a.y) * uy
        let py = -(p.x - a.x) * uy + (p.y - a.y) * ux
        let vx = (q.x - p.x) * ux + (q.y - p.y) * uy
        let vy = -(q.x - p.x) * uy + (q.y - p.y) * ux
        var pieces: [(Double, Double)] = []
        if let x = slab(px, vx, 0, length), let y = slab(py, vy, -radius, radius) {
            let lo = max(x.0, y.0), hi = min(x.1, y.1)
            if lo <= hi { pieces.append((lo, hi)) }
        }
        if let x = circleInterval(p, q, a, radius) { pieces.append(x) }
        if let x = circleInterval(p, q, b, radius) { pieces.append(x) }
        // A capsule is convex, so its intersection with a line is one interval.
        guard let lo = pieces.map({ $0.0 }).min(), let hi = pieces.map({ $0.1 }).max() else { return nil }
        return (lo, hi)
    }

    private static func slab(_ p: Double, _ v: Double, _ lo: Double, _ hi: Double) -> (Double, Double)? {
        if abs(v) < 1e-14 { return p >= lo && p <= hi ? (0, 1) : nil }
        let a = (lo - p) / v, b = (hi - p) / v
        let lower = max(0, min(a, b)), upper = min(1, max(a, b))
        return lower <= upper ? (lower, upper) : nil
    }

    private static func circleInterval(_ p: Pose2D, _ q: Pose2D, _ center: Pose2D,
                                        _ radius: Double) -> (Double, Double)? {
        let dx = q.x - p.x, dy = q.y - p.y
        let ox = p.x - center.x, oy = p.y - center.y
        let aa = dx * dx + dy * dy
        if aa < 1e-20 { return hypot(ox, oy) <= radius ? (0, 1) : nil }
        let bb = ox * dx + oy * dy
        let cc = ox * ox + oy * oy - radius * radius
        let discriminant = bb * bb - aa * cc
        guard discriminant >= 0 else { return nil }
        let root = sqrt(discriminant)
        let lo = max(0, (-bb - root) / aa), hi = min(1, (-bb + root) / aa)
        return lo <= hi ? (lo, hi) : nil
    }

    static func finite(_ p: Pose2D) -> Bool { p.x.isFinite && p.y.isFinite && p.yawRad.isFinite }
}

public struct PlannedTrajectoryLeg: Codable, Equatable {
    public let fromID: UUID
    public let toID: UUID
    public let lowerSampleIndex: Int
    public let upperSampleIndex: Int
    public let centerlineIndices: [Int]
    public let routeIndices: [Int]
    public let simplificationErrorM: Double
    public let halfWidthM: Double
    public let controlMarginM: Double

    public var planningRadiusM: Double { halfWidthM - controlMarginM - simplificationErrorM }
    public var trackingRadiusM: Double { halfWidthM - simplificationErrorM - 0.005 }
    public func centerline(in samples: [TrajectorySample]) -> [Pose2D] { centerlineIndices.map { samples[$0].pose } }
}

public struct CapturedRoutePlan: Codable, Equatable {
    public let startsAtAnchor: Bool
    public let legs: [PlannedTrajectoryLeg]
}

/// Minimum number of straight links on a chronological visibility DAG. The
/// candidate set is a conservatively simplified subset of measured positions.
public enum TrajectoryRoutePlanner {
    public static let halfWidthM = 0.15
    public static let controlMarginM = 0.04
    public static let maxCandidates = 512

    public static func plan(samples: [TrajectorySample], lower: Int, upper: Int,
                            fromID: UUID, toID: UUID) throws -> PlannedTrajectoryLeg {
        guard lower >= 0, upper < samples.count, lower <= upper else {
            throw RecordingError.invalid("节点与采集轨迹的对应关系缺失，请重新采集。")
        }
        guard (lower...upper).allSatisfy({ TrajectoryCorridor.finite(samples[$0].pose) && samples[$0].timestampS.isFinite }),
              (lower..<upper).allSatisfy({ !samples[$0 + 1].startsSegment &&
                  samples[$0 + 1].timestampS >= samples[$0].timestampS &&
                  samples[$0 + 1].timestampS - samples[$0].timestampS <= 0.6 + 1e-9 }) else {
            throw RecordingError.invalid("两个节点之间存在定位中断，不能把缺失轨迹补成直线。请重新采集这一段。")
        }
        var error = 0.005
        var indices = simplify(samples, lower: lower, upper: upper, error: error)
        while indices.count > maxCandidates && error < 0.029 {
            error += 0.005
            indices = simplify(samples, lower: lower, upper: upper, error: error)
        }
        guard indices.count <= maxCandidates else {
            throw RecordingError.invalid("这一段轨迹过长或变化过多，请增加人工节点分段采集。")
        }
        let centerline = indices.map { samples[$0].pose }
        let radius = halfWidthM - controlMarginM - error
        let count = indices.count
        var links = Array(repeating: Int.max, count: count)
        var lengths = Array(repeating: Double.infinity, count: count)
        var previous = Array(repeating: -1, count: count)
        links[0] = 0; lengths[0] = 0
        if count > 1 {
            for end in 1..<count {
                // A direct visible edge is already optimal for this prefix.
                for begin in 0..<end where links[begin] != Int.max {
                    let nextCount = links[begin] + 1
                    if nextCount > links[end] { continue }
                    let nextLength = lengths[begin] + centerline[begin].distanceTo(centerline[end])
                    if nextCount == links[end] && nextLength >= lengths[end] - 1e-9 { continue }
                    if TrajectoryCorridor.containsSegment(from: centerline[begin], to: centerline[end],
                        centerline: Array(centerline[begin...end]), radius: radius) {
                        links[end] = nextCount; lengths[end] = nextLength; previous[end] = begin
                        if nextCount == 1 { break }
                    }
                }
            }
        }
        guard links.last != Int.max else { throw RecordingError.invalid("无法在采集带状空间内生成连续路线。") }
        var route: [Int] = []
        var current = count - 1
        while current >= 0 {
            route.append(indices[current]); current = previous[current]
        }
        return PlannedTrajectoryLeg(fromID: fromID, toID: toID, lowerSampleIndex: lower, upperSampleIndex: upper,
            centerlineIndices: indices, routeIndices: Array(route.reversed()), simplificationErrorM: error,
            halfWidthM: halfWidthM, controlMarginM: controlMarginM)
    }

    static func simplify(_ samples: [TrajectorySample], lower: Int, upper: Int, error: Double) -> [Int] {
        if lower == upper { return [lower] }
        var kept: Set<Int> = [lower, upper]
        var stack = [(lower, upper)]
        while let (lo, hi) = stack.popLast() {
            if hi <= lo + 1 { continue }
            var farthest = -1, distance = error
            for index in (lo + 1)..<hi {
                let value = TrajectoryCorridor.distance(samples[index].pose, to: samples[lo].pose, samples[hi].pose)
                if value > distance { distance = value; farthest = index }
            }
            if farthest >= 0 {
                kept.insert(farthest); stack.append((lo, farthest)); stack.append((farthest, hi))
            }
        }
        return kept.sorted()
    }
}
