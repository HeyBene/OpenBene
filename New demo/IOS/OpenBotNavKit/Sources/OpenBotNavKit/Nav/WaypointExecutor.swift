import Foundation

public enum WaypointPhase: String {
    case idle, alignLine, driveLine, alignNode, waiting, recovering, awaitingImage, verifyingImage, arrived, interrupted, blocked
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
    public var requireReturnImage = false
    public init() {}
}

/// Execute the recorded sequence with distinct rotation/translation phases.
/// AR supplies the live camera pose; wheel telemetry is not substituted for it.
public final class WaypointExecutor {
    public let map: RecordedMap
    public let config: WaypointConfig
    public private(set) var points: [RecordedWaypoint]
    public private(set) var returningFromNodeID: UUID?
    private var targets: [RecordedWaypoint]
    private var legIndices: [Int]
    private let corridors: [[Pose2D]]
    private let link: RobotLink
    private var turn = SettledTurnController()
    private var lineBearing: Double?
    private var turnStopWork: DispatchWorkItem?
    private var turnStopDeadline: Double?
    private var expiredTurnDeadline: Double?
    private var turnStopGeneration = 0
    private var progressWaypointIndex = -1
    private var bestTargetDistanceM = Double.infinity
    private var lastPositionProgressS: Double?
    private var pendingStage: (phase: WaypointPhase, resumeAtS: Double, reason: String)?
    private struct Recovery {
        let phase: WaypointPhase
        let startedS: Double
        let reference: Pose2D?
        var stableSinceS: Double?
        var previousPose: Pose2D?
        var stableReference: Pose2D?
        var previousTimeS: Double?
        var frames = 0
    }
    private var recovery: Recovery?
    private var lastGoodPose: Pose2D?
    private var recoveryTargetIndex = -1
    private var recoveriesAtTarget = 0
    public private(set) var recoveryCount = 0
    public private(set) var imageCorrectionCount = 0
    public private(set) var turnDiagnostics: [String: Double] = [:]
    private var terminalCorrection = false
    private var terminalStartedS: Double?
    private var verificationStartedS: Double?
    private var scanIndex = 0
    public var isReturnTerminal: Bool { returningFromNodeID != nil && target?.id == map.executionStart.id }
    public var canVerifyReturnImage: Bool {
        config.requireReturnImage && active && isReturnTerminal && phase != .recovering && phase != .verifyingImage
            && (imageCorrectionCount == 0 || phase == .awaitingImage)
    }
    public private(set) var phase: WaypointPhase = .idle
    public private(set) var waypointIndex = 0
    public private(set) var message = "先识别锚点，再把机器人放到采集起点。"
    public private(set) var distanceToTargetM = 0.0
    public private(set) var headingErrorDeg = 0.0
    public private(set) var distanceRemainingM = 0.0
    public var target: RecordedWaypoint? {
        targets.indices.contains(waypointIndex) ? targets[waypointIndex] : nil
    }
    public var active: Bool { [.alignLine, .driveLine, .alignNode, .waiting, .recovering, .awaitingImage, .verifyingImage].contains(phase) }

    public init(map: RecordedMap, link: RobotLink, config: WaypointConfig = WaypointConfig()) {
        self.map = map
        self.link = link
        var adjusted = config
        if map.hasCapturedRoute {
            adjusted.positionToleranceM = 0.03
            adjusted.startToleranceM = RouteEntryPlanner.maximumStartDistanceM
        }
        self.config = adjusted
        points = map.executionPoints
        targets = Array(map.executionPoints.dropFirst())
        legIndices = map.executionLegIndices
        if let samples = map.trajectory, let plan = map.routePlan,
           plan.legs.allSatisfy({ $0.centerlineIndices.allSatisfy(samples.indices.contains) }) {
            corridors = plan.legs.map { $0.centerline(in: samples) }
        } else { corridors = [] }
        distanceRemainingM = map.distanceM
        if map.hasCapturedRoute { message = "识别锚点后保持手机固定，在原路线首段内开始，无需对准图片中心。" }
    }

    deinit { turnStopWork?.cancel() }

    public func start(at pose: Pose2D, returningFrom nodeID: UUID? = nil) throws {
        link.stop()
        pendingStage = nil
        try map.validate()
        phase = .idle
        guard TrajectoryCorridor.finite(pose) else { throw RecordingError.invalid("当前位姿不可用。") }
        if map.hasCapturedRoute {
            let entry = try RouteEntryPlanner.plan(map: map, from: pose, returningFrom: nodeID)
            points = entry.points
            targets = Array(points.dropFirst())
            legIndices = entry.legIndices
        } else {
            guard nodeID == nil else { throw RecordingError.invalid("旧地图没有采集轨迹，不能沿轨迹返程。") }
            guard pose.distanceTo(map.executionStart.pose) <= config.startToleranceM else {
                throw RecordingError.invalid("请将机器人移回路线起点后开始。")
            }
        }
        waypointIndex = 0
        recovery = nil; lastGoodPose = pose; recoveryCount = 0
        recoveryTargetIndex = -1; recoveriesAtTarget = 0
        imageCorrectionCount = 0; terminalCorrection = false
        turnDiagnostics = [:]
        terminalStartedS = nil; verificationStartedS = nil; scanIndex = 0
        returningFromNodeID = nodeID
        progressWaypointIndex = -1
        lastPositionProgressS = nil
        cancelTurnStop()
        turn.reset(); lineBearing = nil
        guard routeContains(pose: pose) else { throw RecordingError.invalid("当前位置到下一子节点的直线超出采集带状空间，请回到原路线首段。") }
        phase = .alignLine
        distanceRemainingM = zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.pose.distanceTo($1.1.pose) }
        message = nodeID == nil ? "从当前位置接入首段路线，准备转向。" : "沿原采集路线返程至锚点旁出发位置，准备转向。"
    }

    public func stop(reason: String = "已停止；重新执行需要回到起点。") {
        link.stop()
        pendingStage = nil
        recovery = nil
        verificationStartedS = nil
        cancelTurnStop()
        turn.reset(); lineBearing = nil
        phase = .interrupted
        message = reason
    }

    /// Pause the current target without restarting from the selected route node.
    /// Only temporary loss in an unchanged AR world may use this path.
    public func pauseForTracking(reason: String = "定位暂不可用", nowS: Double = ProcessInfo.processInfo.systemUptime) {
        guard active else { return }
        link.stop(); cancelTurnStop()
        guard map.hasCapturedRoute, nowS.isFinite else { stop(reason: reason); return }
        guard recovery == nil else { return }
        if recoveryTargetIndex != waypointIndex { recoveryTargetIndex = waypointIndex; recoveriesAtTarget = 0 }
        guard recoveriesAtTarget < 3 else { stop(reason: "当前节点已自动恢复3次，定位仍不稳定，已结束执行。"); return }
        recoveriesAtTarget += 1; recoveryCount += 1
        let next = phase == .waiting ? pendingStage?.phase ?? .alignLine : phase
        let resumed: WaypointPhase = [.awaitingImage, .verifyingImage].contains(next) ? .awaitingImage : (next == .alignNode ? .alignNode : .alignLine)
        recovery = Recovery(phase: resumed, startedS: nowS, reference: lastGoodPose)
        pendingStage = nil; turn.reset(); lineBearing = nil
        phase = .recovering
        message = reason + "；已停车，等待定位稳定后继续当前节点。"
    }

    /// First sight during a final turn stops motion. The app must then collect
    /// new stationary image observations, rather than applying that moving frame.
    public func beginReturnImageVerification(nowS: Double) {
        guard canVerifyReturnImage else { return }
        link.stop(); cancelTurnStop(); pendingStage = nil; turn.reset(); lineBearing = nil
        if terminalStartedS == nil { terminalStartedS = nowS }
        verificationStartedS = nowS
        phase = .verifyingImage
        message = "已看到定位图片，停车确认图像位姿0.5秒。"
    }

    /// The corrected pose is measured in the saved image frame. Translation is
    /// bounded to a 30cm terminal area, separate from normal corridor replay.
    public func acceptReturnImagePose(_ pose: Pose2D, nowS: Double) {
        guard phase == .verifyingImage, isReturnTerminal, TrajectoryCorridor.finite(pose), let target = target else { return }
        link.stop(); cancelTurnStop()
        distanceToTargetM = pose.distanceTo(target.pose)
        headingErrorDeg = wrapDeg(target.pose.yawDeg - pose.yawDeg)
        imageCorrectionCount += 1
        verificationStartedS = nil
        if distanceToTargetM <= 0.05 && abs(headingErrorDeg) <= config.nodeHeadingToleranceDeg {
            finish(); message = "返程完成，图片已复核出发位姿。"; return
        }
        guard distanceToTargetM <= 0.30 else {
            stop(reason: String(format: "图片已校准，距原出发位姿%.2fm，超出30cm末端微调范围，已停车。", distanceToTargetM)); return
        }
        guard imageCorrectionCount <= 3 else {
            stop(reason: String(format: "已微调3次，残差%.2fm / %.1f°，已停车；请检查支架及场地。", distanceToTargetM, headingErrorDeg)); return
        }
        terminalCorrection = true; lastGoodPose = pose
        scanIndex = 0
        progressWaypointIndex = -1; lastPositionProgressS = nowS
        waitBefore(distanceToTargetM <= config.positionToleranceM ? .alignNode : .alignLine,
                   nowS: nowS, reason: "图片已校准，准备微调回采集出发位姿")
    }

    public func tick(pose: Pose2D?, trackingNormal: Bool, linkAvailable: Bool = true,
                     nowS: Double = ProcessInfo.processInfo.systemUptime) {
        guard active else { link.stop(); return }
        guard nowS.isFinite else { stop(reason: "导航时间无效，已停车。"); return }
        guard linkAvailable else { stop(reason: "蓝牙连接中断，已停止执行。"); return }
        if link.telemetry.bumper != nil { stop(reason: "检测到碰撞，已停止执行。"); return }
        if phase == .recovering {
            recover(pose: pose, trackingNormal: trackingNormal, nowS: nowS)
            return
        }
        guard trackingNormal, let pose = pose,
              pose.x.isFinite, pose.y.isFinite, pose.yawRad.isFinite else {
            pauseForTracking(reason: "定位跟踪暂不可用", nowS: nowS)
            return
        }
        defer { if phase != .recovering { lastGoodPose = pose } }
        if let began = terminalStartedS, nowS - began > 90 {
            stop(reason: "末端图片归位超过90秒，已停车。"); return
        }
        if phase == .verifyingImage {
            link.stop()
            if nowS - (verificationStartedS ?? nowS) > 5 {
                verificationStartedS = nil; phase = .awaitingImage; turn.reset()
                message = "图片观测未稳定，继续小角度寻找完整图片。"
            }
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
        if phase == .awaitingImage {
            if terminalStartedS == nil { terminalStartedS = nowS }
            guard scanIndex < 3 else { stop(reason: "未能稳定识别定位图片，已停车；请检查完整图片是否在镜头内。"); return }
            let offsets = [-25.0, 25, 0]
            let desired = map.executionStart.pose.yawRad + offsets[scanIndex] * .pi / 180
            let error = wrapRad(desired - pose.yawRad)
            headingErrorDeg = error * 180 / .pi
            message = "锚点附近小角度转向寻找图片。"
            if settledTurn(error: error, pose: pose, nowS: nowS, tolerance: config.nodeHeadingToleranceDeg) {
                scanIndex += 1
                waitBefore(.awaitingImage, nowS: nowS, reason: "停车等待图片识别")
            }
            return
        }
        // Rotating an offset camera is not a straight driving segment. Validate
        // the live connecting line before any translation, after turn/wait.
        if phase == .driveLine && !routeContains(pose: pose) {
            stop(reason: "当前位置到下一节点的直线超出采集带状范围，已停车；请将整台车移回原路线后开始。")
            return
        }
        guard let target = target else { finish(); return }
        distanceToTargetM = pose.distanceTo(target.pose)
        if map.hasCapturedRoute {
            if progressWaypointIndex != waypointIndex {
                progressWaypointIndex = waypointIndex
                bestTargetDistanceM = distanceToTargetM
                lastPositionProgressS = nowS
            }
            if distanceToTargetM < bestTargetDistanceM - 0.01 {
                bestTargetDistanceM = distanceToTargetM
                lastPositionProgressS = nowS
            }
            if phase != .alignNode, let last = lastPositionProgressS, nowS - last > 30 {
                stop(reason: "30秒未向目标节点前进，已停车；请检查支架偏心、过短节点段和底盘输出。")
                return
            }
        }
        distanceRemainingM = distanceToTargetM
        let remaining = targets.dropFirst(waypointIndex)
        for pair in zip(remaining, remaining.dropFirst()) {
            distanceRemainingM += pair.0.pose.distanceTo(pair.1.pose)
        }

        switch phase {
        case .alignLine:
            if distanceToTargetM <= config.positionToleranceM {
                reachedTarget(nowS: nowS)
                return
            }
            if lineBearing == nil { lineBearing = pose.bearingTo(target.pose) }
            let error = map.hasCapturedRoute ? wrapRad((lineBearing ?? pose.bearingTo(target.pose)) - pose.yawRad) : pose.headingErrorTo(target.pose)
            headingErrorDeg = error * 180 / .pi
            message = String(format: "转向 %@，航线方向误差 %.1f°", target.name, headingErrorDeg)
            if map.hasCapturedRoute {
                if settledTurn(error: error, pose: pose, nowS: nowS, tolerance: config.lineHeadingToleranceDeg) {
                    waitBefore(.driveLine, nowS: nowS, reason: "航线方向已稳定，准备直行")
                }
            } else if abs(headingErrorDeg) <= config.lineHeadingToleranceDeg {
                waitBefore(.driveLine, nowS: nowS, reason: "航线方向已对准，准备直行")
            } else { rotate(error) }
        case .driveLine:
            if distanceToTargetM <= config.positionToleranceM {
                reachedTarget(nowS: nowS)
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
            // V2 arrival is confirmed before the two-second stop and rotation.
            // An in-place chassis turn moves an offset camera; this stage only
            // tests heading. Recheck the live corridor before later translation.
            if !map.hasCapturedRoute && distanceToTargetM > config.positionToleranceM + 0.10 {
                waitBefore(.alignLine, nowS: nowS, reason: "位置超出到点范围，准备重新对准航线")
                return
            }
            let error = wrapRad(target.pose.yawRad - pose.yawRad)
            headingErrorDeg = error * 180 / .pi
            message = String(format: "%@ 朝向误差 %.1f°", target.name, headingErrorDeg)
            let aligned: Bool
            if map.hasCapturedRoute {
                aligned = settledTurn(error: error, pose: pose, nowS: nowS, tolerance: config.nodeHeadingToleranceDeg)
            } else {
                aligned = abs(headingErrorDeg) <= config.nodeHeadingToleranceDeg
                if !aligned { rotate(error) }
            }
            if aligned {
                link.stop()
                if waypointIndex == targets.count - 1 {
                    if config.requireReturnImage && isReturnTerminal {
                        if terminalStartedS == nil { terminalStartedS = nowS }
                        waitBefore(.awaitingImage, nowS: nowS, reason: "已到锚点附近，继续识别图片复核实际位姿")
                    } else { finish() }
                }
                else {
                    waypointIndex += 1
                    waitBefore(.alignLine, nowS: nowS, reason: "节点朝向已调整，准备转向下一段航线")
                }
            }
        default: link.stop()
        }
    }

    /// Automatic vertices restore no captured phone yaw. Only manual nodes do.
    private func reachedTarget(nowS: Double) {
        if target?.isAutomatic == true {
            waypointIndex += 1
            waitBefore(.alignLine, nowS: nowS, reason: "已到达自动子节点，准备转向下一段")
        } else {
            waitBefore(.alignNode, nowS: nowS, reason: "已到达人工节点，准备调整记录朝向")
        }
    }

    private func routeContains(pose: Pose2D) -> Bool {
        if terminalCorrection, isReturnTerminal { return pose.distanceTo(map.executionStart.pose) <= 0.30 }
        guard map.hasCapturedRoute else { return true }
        guard legIndices.indices.contains(waypointIndex), let target = target,
              let plan = map.routePlan else { return false }
        let index = legIndices[waypointIndex]
        guard corridors.indices.contains(index) else { return false }
        let radius = plan.legs[index].trackingRadiusM
        return TrajectoryCorridor.containsSegment(from: pose, to: target.pose,
            centerline: corridors[index], radius: radius)
    }

    private func settledTurn(error: Double, pose: Pose2D, nowS: Double, tolerance: Double) -> Bool {
        let action = turn.update(errorRad: error, yawRad: pose.yawRad, nowS: nowS,
            toleranceDeg: tolerance, leftSpeed: config.leftTurnSpeed, rightSpeed: config.rightTurnSpeed,
            reversalPauseS: config.stagePauseS)
        turnDiagnostics = turn.diagnostics
        switch action {
        case .drive(let left, let right):
            guard let deadline = turn.commandExpiresAtS, expiredTurnDeadline != deadline else { link.stop(); return false }
            link.drive(left: left, right: right)
            scheduleTurnStop(deadline: deadline, nowS: nowS)
        case .hold(let reason): cancelTurnStop(); link.stop(); message += "；" + reason
        case .aligned: cancelTurnStop(); link.stop(); return true
        case .failed(let reason):
            if turn.poseJumpDetected { pauseForTracking(reason: reason, nowS: nowS) }
            else { stop(reason: reason) }
        }
        return false
    }

    private func recover(pose: Pose2D?, trackingNormal: Bool, nowS: Double) {
        link.stop()
        guard var pending = recovery else { stop(reason: "恢复状态无效，已停车。"); return }
        guard nowS >= pending.startedS, nowS - pending.startedS <= 15 else {
            stop(reason: "定位15秒未稳定恢复，已结束执行；请检查环境后手动开始。"); return
        }
        guard trackingNormal, let pose = pose, TrajectoryCorridor.finite(pose) else {
            pending.stableSinceS = nil; pending.previousPose = nil; pending.stableReference = nil; pending.frames = 0
            recovery = pending
            message = "定位暂不可用，停车等待自动恢复。"; return
        }
        // A reset/relocalization into a different world is not a temporary
        // tracking interruption. Wait for continuity, never snap the route.
        if let reference = pending.reference,
           pose.distanceTo(reference) > 0.30 || abs(wrapDeg(pose.yawDeg - reference.yawDeg)) > 45 {
            pending.stableSinceS = nil; pending.stableReference = nil; pending.frames = 0
            recovery = pending
            message = "恢复位姿与停车前不连续，保持停车等待；不会自动重置地图。"; return
        }
        if let previous = pending.stableReference, let time = pending.previousTimeS,
           pose.distanceTo(previous) > 0.03 || abs(wrapDeg(pose.yawDeg - previous.yawDeg)) > 3 || nowS - time > 0.2 || nowS <= time {
            pending.stableSinceS = nil; pending.stableReference = nil; pending.frames = 0
        }
        if pending.stableSinceS == nil { pending.stableSinceS = nowS; pending.stableReference = pose }
        pending.frames += 1; pending.previousPose = pose; pending.previousTimeS = nowS
        recovery = pending
        guard pending.frames >= 6, nowS - (pending.stableSinceS ?? nowS) >= 0.5 - 1e-9 else {
            message = "定位恢复中，停车确认位姿稳定0.5秒。"; return
        }
        recovery = nil; lastGoodPose = pose
        if let last = lastPositionProgressS { lastPositionProgressS = last + nowS - pending.startedS }
        waitBefore(pending.phase, nowS: nowS, reason: "定位已恢复，从最新位姿重新对准当前节点")
    }

    /// A missing AR frame must not extend a short turn pulse to the 0.6s
    /// tracking watchdog. Generation checks keep stale timers from stopping a
    /// later stage or a restarted route.
    private func scheduleTurnStop(deadline: Double, nowS: Double) {
        guard turnStopDeadline != deadline else { return }
        cancelTurnStop()
        turnStopDeadline = deadline
        let generation = turnStopGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.turnStopGeneration == generation else { return }
            self.expiredTurnDeadline = deadline
            self.link.stop()
        }
        turnStopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - nowS), execute: work)
    }

    private func cancelTurnStop() {
        turnStopWork?.cancel(); turnStopWork = nil
        turnStopDeadline = nil; expiredTurnDeadline = nil
        turnStopGeneration += 1
    }

    private func waitBefore(_ next: WaypointPhase, nowS: Double, reason: String) {
        link.stop()
        cancelTurnStop()
        turn.reset(); lineBearing = nil
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
        cancelTurnStop()
        link.stop()
        pendingStage = nil
        phase = .arrived
        distanceRemainingM = 0
        message = returningFromNodeID == nil ? "航线完成，位置和最后节点朝向已到达。" : "返程完成，已按 VIO 到达原出发位置与朝向；未执行图片重识别校正。"
    }
}
