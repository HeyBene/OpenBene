import Foundation

public enum WaypointPhase: String {
    case idle, alignLine, driveLine, alignNode, waiting, arrived, interrupted, blocked
}

public struct WaypointConfig {
    public var startToleranceM = 0.30
    public var positionToleranceM = 0.30
    public var lineHeadingToleranceDeg = 3.0
    public var headingCorrectionDeg = 6.0
    public var nodeHeadingToleranceDeg = 5.0
    public var cruiseSpeed = 160.0 / 255.0
    public var leftTurnSpeed = 160.0 / 255.0
    public var rightTurnSpeed = 160.0 / 255.0
    public var stagePauseS = 2.0
    public var steerGain = 1.6
    public var sonarInstalled = false
    public var obstacleStopCm = 35.0
    public init() {}
}

/// Execute the recorded sequence with distinct rotation/translation phases.
/// AR supplies the live camera pose; wheel telemetry is not substituted for it.
public final class WaypointExecutor {
    public let map: RecordedMap
    public let config: WaypointConfig
    private let link: RobotLink
    private var pendingStage: (phase: WaypointPhase, resumeAtS: Double, reason: String)?
    public private(set) var phase: WaypointPhase = .idle
    public private(set) var waypointIndex = 0
    public private(set) var message = "先识别锚点，再把机器人放到采集起点。"
    public private(set) var distanceToTargetM = 0.0
    public private(set) var headingErrorDeg = 0.0
    public private(set) var distanceRemainingM = 0.0
    public var target: RecordedWaypoint? {
        map.waypoints.indices.contains(waypointIndex) ? map.waypoints[waypointIndex] : nil
    }
    public var active: Bool { [.alignLine, .driveLine, .alignNode, .waiting].contains(phase) }

    public init(map: RecordedMap, link: RobotLink, config: WaypointConfig = WaypointConfig()) {
        self.map = map
        self.link = link
        self.config = config
        distanceRemainingM = map.distanceM
    }

    public func start(at pose: Pose2D) throws {
        link.stop()
        pendingStage = nil
        try map.validate()
        guard pose.x.isFinite, pose.y.isFinite, pose.yawRad.isFinite,
              pose.distanceTo(map.start.pose) <= config.startToleranceM else {
            throw RecordingError.invalid("请将机器人移回采集起点（\(Int(config.startToleranceM * 100)) cm 范围内）后开始。")
        }
        waypointIndex = 0
        phase = .alignLine
        distanceRemainingM = map.distanceM
        message = "起点转向第一段航线。"
    }

    public func stop(reason: String = "已停止；重新执行需要回到起点。") {
        link.stop()
        pendingStage = nil
        phase = .interrupted
        message = reason
    }

    public func tick(pose: Pose2D?, trackingNormal: Bool, linkAvailable: Bool = true,
                     nowS: Double = ProcessInfo.processInfo.systemUptime) {
        guard active else { link.stop(); return }
        guard trackingNormal, let pose = pose,
              pose.x.isFinite, pose.y.isFinite, pose.yawRad.isFinite else {
            stop(reason: "定位跟踪暂不可用，已停车。等待跟踪恢复后回到起点重新开始。")
            return
        }
        guard linkAvailable else { stop(reason: "蓝牙连接中断，已停止执行。"); return }
        if link.telemetry.bumper != nil {
            stop(reason: "检测到碰撞，已停止执行。")
            return
        }
        if config.sonarInstalled, let sonar = link.telemetry.sonarCm, sonar <= config.obstacleStopCm {
            link.stop()
            phase = .blocked
            pendingStage = nil
            message = "前方有障碍，已停车。清理后回到起点重新开始。"
            return
        }
        if phase == .waiting, let pending = pendingStage {
            link.stop()
            guard nowS >= pending.resumeAtS else {
                message = String(format: "%@；停车等待 %.1f 秒。", pending.reason, pending.resumeAtS - nowS)
                return
            }
            pendingStage = nil
            phase = pending.phase
            // Fall through using this frame's pose and connection state;
            // never resume a command calculated before the pause.
        }
        guard let target = target else { finish(); return }
        distanceToTargetM = pose.distanceTo(target.pose)
        distanceRemainingM = distanceToTargetM
        let remaining = map.waypoints.dropFirst(waypointIndex)
        for pair in zip(remaining, remaining.dropFirst()) {
            distanceRemainingM += pair.0.pose.distanceTo(pair.1.pose)
        }

        switch phase {
        case .alignLine:
            if distanceToTargetM <= config.positionToleranceM {
                waitBefore(.alignNode, nowS: nowS, reason: "已在节点位置，准备调整朝向")
                return
            }
            let error = pose.headingErrorTo(target.pose)
            headingErrorDeg = error * 180 / .pi
            message = String(format: "转向 %@，航线方向误差 %.1f°", target.name, headingErrorDeg)
            if abs(headingErrorDeg) <= config.lineHeadingToleranceDeg {
                waitBefore(.driveLine, nowS: nowS, reason: "航线方向已对准，准备直行")
            } else { rotate(error) }
        case .driveLine:
            if distanceToTargetM <= config.positionToleranceM {
                waitBefore(.alignNode, nowS: nowS, reason: "已到达 \(target.name)，准备调整节点朝向")
                return
            }
            headingErrorDeg = pose.headingErrorTo(target.pose) * 180 / .pi
            if abs(headingErrorDeg) > config.headingCorrectionDeg {
                waitBefore(.alignLine, nowS: nowS, reason: "暂停直行，准备修正航线方向")
                return
            }
            // Keep the requested drive PWM through the arrival boundary;
            // reducing it near a node previously stalled the 520 chassis.
            let speed = config.cruiseSpeed
            let steer = min(1, max(-1, config.steerGain * headingErrorDeg * .pi / 180))
            link.drive(left: speed * (1 - steer), right: speed * (1 + steer))
            message = String(format: "直行至 %@，剩余 %.2f m", target.name, distanceToTargetM)
        case .alignNode:
            // Rotation can move an offset camera slightly; don't advance if the
            // robot has actually left the arrival region.
            if distanceToTargetM > config.positionToleranceM + 0.10 {
                waitBefore(.alignLine, nowS: nowS, reason: "位置超出到点范围，准备重新对准航线")
                return
            }
            let error = wrapRad(target.pose.yawRad - pose.yawRad)
            headingErrorDeg = error * 180 / .pi
            message = String(format: "%@ 朝向误差 %.1f°", target.name, headingErrorDeg)
            if abs(headingErrorDeg) <= config.nodeHeadingToleranceDeg {
                link.stop()
                if waypointIndex == map.waypoints.count - 1 { finish() }
                else {
                    waypointIndex += 1
                    waitBefore(.alignLine, nowS: nowS, reason: "节点朝向已调整，准备转向下一段航线")
                }
            } else { rotate(error) }
        default: link.stop()
        }
    }

    private func waitBefore(_ next: WaypointPhase, nowS: Double, reason: String) {
        link.stop()
        if config.stagePauseS <= 0 {
            phase = next
            pendingStage = nil
            return
        }
        phase = .waiting
        pendingStage = (next, nowS + config.stagePauseS, reason)
        message = String(format: "%@；停车等待 %.1f 秒。", reason, config.stagePauseS)
    }

    private func rotate(_ error: Double) {
        let speed = error >= 0 ? config.leftTurnSpeed : -config.rightTurnSpeed
        link.drive(left: -speed, right: speed)
    }

    private func finish() {
        link.stop()
        pendingStage = nil
        phase = .arrived
        distanceRemainingM = 0
        message = "航线完成，位置和最后节点朝向已到达。"
    }
}
