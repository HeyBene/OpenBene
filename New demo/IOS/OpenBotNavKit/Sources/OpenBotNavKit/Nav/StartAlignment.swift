import Foundation

/// Where the chassis must sit before a route starts, expressed in centimetres.
/// The pose comes from the same anchor recognition used by the route executor.
public struct StartPlacementAdvice: Equatable {
    public let distanceM: Double
    /// Positive means the chassis must move forward along its recorded heading.
    public let forwardM: Double
    /// Positive means the chassis must move to its left.
    public let leftM: Double
    public let headingErrorDeg: Double
    public let canEnter: Bool

    public init(distanceM: Double, forwardM: Double, leftM: Double,
                headingErrorDeg: Double, canEnter: Bool) {
        self.distanceM = distanceM
        self.forwardM = forwardM
        self.leftM = leftM
        self.headingErrorDeg = headingErrorDeg
        self.canEnter = canEnter
    }

    public var adjustmentText: String {
        var parts: [String] = []
        let forward = Int((abs(forwardM) * 100).rounded())
        let left = Int((abs(leftM) * 100).rounded())
        if forwardM >= 0.03 { parts.append("向前 \(forward) cm") }
        else if forwardM <= -0.03 { parts.append("向后 \(forward) cm") }
        if leftM >= 0.03 { parts.append("向左 \(left) cm") }
        else if leftM <= -0.03 { parts.append("向右 \(left) cm") }
        if abs(headingErrorDeg) >= 5 {
            let direction = headingErrorDeg > 0 ? "向左" : "向右"
            parts.append(String(format: "车头%@转 %.0f°", direction, abs(headingErrorDeg)))
        }
        return parts.isEmpty ? "位置与朝向已在容差内" : parts.joined(separator: "、")
    }

    public var setupText: String {
        var parts: [String] = []
        if forwardM >= 0.03 { parts.append(String(format: "向前%.0f cm", forwardM * 100)) }
        else if forwardM <= -0.03 { parts.append(String(format: "向后%.0f cm", -forwardM * 100)) }
        if leftM >= 0.03 { parts.append(String(format: "向左%.0f cm", leftM * 100)) }
        else if leftM <= -0.03 { parts.append(String(format: "向右%.0f cm", -leftM * 100)) }
        if parts.isEmpty { return canEnter ? "已在起点容差内，可直接开始。" : "已在附近，请确认朝向。" }
        return "调整：" + parts.joined(separator: "、") + (canEnter ? "；可直接开始。" : "，使橙色航线带覆盖车身后开始。")
    }

    public var summary: String {
        String(format: "距起点 %.2f m；%@。", distanceM, setupText)
    }
}

public enum StartAlignment {
    public static func advice(map: RecordedMap, from pose: Pose2D,
                              returningFrom nodeID: UUID? = nil) -> StartPlacementAdvice? {
        guard TrajectoryCorridor.finite(pose) else { return nil }
        let target: RecordedWaypoint
        if let nodeID = nodeID, let node = map.executionPoints.first(where: { $0.id == nodeID }) {
            target = node
        } else {
            target = map.executionStart
        }
        let dx = target.pose.x - pose.x, dy = target.pose.y - pose.y
        // Express the correction in the recorded phone heading. The camera is
        // mounted on the chassis, so this matches forward/back and left/right
        // as seen from behind the robot without inventing a screen projection.
        let cosYaw = cos(pose.yawRad), sinYaw = sin(pose.yawRad)
        let forward = dx * cosYaw + dy * sinYaw
        let left = -dx * sinYaw + dy * cosYaw
        let heading = wrapDeg(target.pose.yawDeg - pose.yawDeg)
        return StartPlacementAdvice(distanceM: hypot(dx, dy), forwardM: forward, leftM: left,
            headingErrorDeg: heading,
            canEnter: map.hasCapturedRoute
                ? RouteEntryPlanner.canEnter(map: map, from: pose, returningFrom: nodeID)
                : hypot(dx, dy) <= 0.30)
    }
}
