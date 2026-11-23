import Foundation

public enum WaypointPhase: String {
    case idle, alignLine, driveLine, alignNode, reversing, waiting, recovering, awaitingImage, verifyingImage, arrived, interrupted, blocked
}

public struct WaypointConfig {
    public var startToleranceM = 0.30
    /// Arrival radius around a recorded node. The corridor supplies the
    /// spatial guarantee, so this no longer needs to be a 3 cm stop.
    public var positionToleranceM = 0.30
    /// Passing a node along the leg by up to this much still counts as arrival.
    /// This is the normal outcome of a forward-only approach.
    public var arrivalOvershootM = 0.20
    /// Sideways slack around the recorded node.
    public var lateralToleranceM = 0.12
    /// Headings within this error are followed continuously by the arc drive.
    /// Only errors above this angle cost a stop and an in-place pivot.
    public var arcTurnMaxDeg = 45.0
    public var nodeHeadingToleranceDeg = 20.0
    public var cruiseSpeed = 160.0 / 255.0
    public var leftTurnSpeed = 160.0 / 255.0
    public var rightTurnSpeed = 160.0 / 255.0
    /// Settle time between actions. Enough for a 520 chassis to stop rocking,
    /// short enough that the route keeps moving.
    public var stagePauseS = 0.25
    public var steerGain = 1.9
    public var crossTrackGain = 0.9
    /// Keep both wheels driving forward during an arc. Larger heading errors
    /// use a stopped in-place turn instead of a near-pivot at full speed.
    public var maximumArcSteer = 0.70
    public var lookaheadM = 0.30
    public var reverseSpeedFraction = 0.55
    public var maxReverseM = 0.25
    public var reverseTimeoutS = 2.0
    /// If neither the heading nor the distance to the next node improves for
    /// this long, the chassis is stuck. Give it one more chance before ending.
    public var stallTimeoutS = 25.0
    public var sonarInstalled = false
    public var obstacleStopCm = 35.0
    public var requireReturnImage = false
    public init() {}
}

/// Replays a recorded corridor. Goal: keep moving and absorb small positioning
/// errors instead of spending the run on pivots at each node. A genuine
/// overshoot gets a short reverse, then the route resumes from the live pose.
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
    private var previousRouteAlong: Double?
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
    private struct Backing {
        let targetIndex: Int
        let origin: Pose2D
        let maxLengthM: Double
        var pulsing: Bool
        var untilS: Double
        let startedS: Double
    }
    private var backing: Backing?
    private var reverseAttempts = 0
    private var reverseAttemptIndex = -1
    public private(set) var recoveryCount = 0
    public private(set) var imageCorrectionCount = 0
    public private(set) var turnDiagnostics: [String: Double] = [:]
    public private(set) var isReversing = false
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
    public var active: Bool {
        [.alignLine, .driveLine, .alignNode, .reversing, .waiting, .recovering, .awaitingImage, .verifyingImage].contains(phase)
    }

    public init(map: RecordedMap, link: RobotLink, config: WaypointConfig = WaypointConfig()) {
        self.map = map
        self.link = link
        var adjusted = config
        if map.hasCapturedRoute {
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
        if map.hasCapturedRoute { message = "识别锚点后保持手机固定，在首段航线带内开始，无需对准图片中心。" }
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
        backing = nil; isReversing = false
        reverseAttempts = 0; reverseAttemptIndex = -1
        terminalStartedS = nil; verificationStartedS = nil; scanIndex = 0
        returningFromNodeID = nodeID
        progressWaypointIndex = -1
        lastPositionProgressS = nil
        previousRouteAlong = nil
        cancelTurnStop()
        turn.reset(); lineBearing = nil
        if map.hasCapturedRoute, !TrajectoryCorridor.contains(
            point: pose, centerline: legCorridor() ?? [], radius: bandRadiusForLivePosition()) {
            throw RecordingError.invalid("当前位置离采集航线较远，请把整台车移到首段航线带内再开始。")
        }
        phase = .alignLine
        distanceRemainingM = zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.pose.distanceTo($1.1.pose) }
        message = nodeID == nil ? "已接入首段路线，准备转向。" : "沿原采集路线返程至锚点旁出发位置，准备转向。"
    }

    public func stop(reason: String = "已停止；重新执行需要回到起点。") {
        link.stop()
        pendingStage = nil
        recovery = nil
        backing = nil; isReversing = false
        verificationStartedS = nil
        cancelTurnStop()
        turn.reset(); lineBearing = nil
        phase = .interrupted
        message = reason
    }

    /// Pause the current target without restarting from the selected node.
    public func pauseForTracking(reason: String = "定位暂不可用", nowS: Double = ProcessInfo.processInfo.systemUptime) {
        guard active else { return }
        link.stop(); cancelTurnStop()
        guard map.hasCapturedRoute, nowS.isFinite else { stop(reason: reason); return }
        guard recovery == nil else { return }
        if recoveryTargetIndex != waypointIndex { recoveryTargetIndex = waypointIndex; recoveriesAtTarget = 0 }
        guard recoveriesAtTarget < 3 else { stop(reason: "当前节点已自动恢复3次，定位仍不稳定，已结束执行。"); return }
        recoveriesAtTarget += 1; recoveryCount += 1
        let next = phase == .waiting ? pendingStage?.phase ?? .alignLine : phase
        let resumed: WaypointPhase = [.awaitingImage, .verifyingImage].contains(next)
            ? .awaitingImage : (next == .alignNode ? .alignNode : .alignLine)
        recovery = Recovery(phase: resumed, startedS: nowS, reference: lastGoodPose)
        pendingStage = nil; turn.reset(); lineBearing = nil
        phase = .recovering
        message = reason + "；已停车，等待定位稳定后继续当前节点。"
    }

    public func beginReturnImageVerification(nowS: Double) {
        guard canVerifyReturnImage else { return }
        link.stop(); cancelTurnStop(); pendingStage = nil; turn.reset(); lineBearing = nil
        if terminalStartedS == nil { terminalStartedS = nowS }
        verificationStartedS = nowS
        phase = .verifyingImage
        message = "已看到定位图片，停车确认图像位姿0.5秒。"
    }

    /// Translation after image correction stays inside a 30 cm terminal area.
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
        if phase == .reversing {
            guard trackingNormal, let pose = pose, TrajectoryCorridor.finite(pose) else {
                pauseForTracking(reason: "定位跟踪暂不可用", nowS: nowS)
                return
            }
            reverse(pose: pose, nowS: nowS)
            return
        }
        guard trackingNormal, let pose = pose, TrajectoryCorridor.finite(pose) else {
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
                message = String(format: "%@；停车稳定 %.1f 秒。", pending.reason, max(0, pending.resumeAtS - nowS))
                return
            }
            pendingStage = nil
            phase = pending.phase
            if phase == .driveLine { lineBearing = legLookaheadBearing(pose: pose) }
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
        guard let target = target else { finish(); return }
        distanceToTargetM = pose.distanceTo(target.pose)
        if map.hasCapturedRoute {
            if progressWaypointIndex != waypointIndex {
                progressWaypointIndex = waypointIndex
                bestTargetDistanceM = distanceToTargetM
                lastPositionProgressS = nowS
                previousRouteAlong = nil
            }
            if distanceToTargetM < bestTargetDistanceM - 0.01 {
                bestTargetDistanceM = distanceToTargetM
                lastPositionProgressS = nowS
            }
            // The distance to the target can stay flat while the chassis
            // straddles a vertex. Forward motion along the recorded corridor
            // is the real progress signal, independent of heading noise.
            if progressWaypointIndex == waypointIndex, let along = routeAlong(pose: pose) {
                if let previous = previousRouteAlong, along > previous + 0.015 { lastPositionProgressS = nowS }
                previousRouteAlong = along
            }
            if [.alignLine, .driveLine, .reversing].contains(phase),
               let last = lastPositionProgressS, nowS - last > config.stallTimeoutS {
                // Give a stuck chassis one in-place nudge before ending. This
                // covers a wheel resting in a skid or a near-zero lookahead.
                if reverseAttempts < 2 {
                    reverseAttempts += 1
                    reverseAttemptIndex = waypointIndex
                    lineBearing = nil
                    waitBefore(.alignLine, nowS: nowS, reason: "短暂没有前进，准备微调方向")
                } else {
                    stop(reason: "定位显示长时间没有向节点前进，已停车；请检查支架偏心、过短节点段和底盘输出。")
                }
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
            if atTarget(pose: pose) {
                reachedTarget(nowS: nowS)
                return
            }
            if positionOvershot(pose: pose, nowS: nowS) { return }
            if lineBearing == nil { lineBearing = legLookaheadBearing(pose: pose) ?? pose.bearingTo(target.pose) }
            let error = map.hasCapturedRoute
                ? wrapRad((lineBearing ?? pose.bearingTo(target.pose)) - pose.yawRad)
                : pose.headingErrorTo(target.pose)
            headingErrorDeg = error * 180 / .pi
            message = String(format: "朝向 %@，方向误差 %.1f°", target.name, headingErrorDeg)
            if abs(headingErrorDeg) <= config.arcTurnMaxDeg {
                phase = .driveLine
            } else if map.hasCapturedRoute {
                if settledTurn(error: error, pose: pose, nowS: nowS, tolerance: config.arcTurnMaxDeg) {
                    phase = .driveLine
                }
            } else { rotate(error) }

        case .driveLine:
            if atTarget(pose: pose) {
                reachedTarget(nowS: nowS)
                return
            }
            if positionOvershot(pose: pose, nowS: nowS) { return }
            let bearingError = legLookaheadBearing(pose: pose).map { wrapRad($0 - pose.yawRad) }
                ?? pose.headingErrorTo(target.pose)
            headingErrorDeg = bearingError * 180 / .pi
            if abs(headingErrorDeg) > config.arcTurnMaxDeg {
                link.stop()
                lineBearing = nil
                phase = .alignLine
                turn.reset()
                message = "方向偏差较大，原地转向航线。"
                return
            }
            // Keep the configured PWM; steering comes from heading plus lateral
            // error, so small deviations do not interrupt the drive.
            let speed = config.cruiseSpeed
            let crossTrack = corridorOffset(pose: pose).map { min(0.15, max(-0.15, $0)) } ?? 0
            var steer = config.steerGain * bearingError
            // offset > 0 means the chassis is left of the leg. Slowing the
            // right wheel brings it back without stopping.
            steer -= config.crossTrackGain * crossTrack
            steer = min(config.maximumArcSteer, max(-config.maximumArcSteer, steer))
            link.drive(left: speed * (1 - steer), right: speed * (1 + steer))
            message = String(format: "沿航线前进至 %@，剩余 %.2f m", target.name, distanceToTargetM)

        case .alignNode:
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
                } else {
                    waypointIndex += 1
                    reverseAttempts = 0; reverseAttemptIndex = -1
                    progressWaypointIndex = -1
                    turn.reset(); lineBearing = nil
                    // The next leg starts from this node; keep driving rather
                    // than adding another pivot back towards the line just left.
                    phase = .driveLine
                    message = "节点朝向完成，继续下一段航线。"
                }
            }
        default: link.stop()
        }
    }

    private func reachedTarget(nowS: Double) {
        reverseAttempts = 0; reverseAttemptIndex = -1
        if target?.isAutomatic == true {
            waypointIndex += 1
            progressWaypointIndex = -1
            lineBearing = nil
            phase = .driveLine
            message = "已通过自动子节点，沿航线继续。"
        } else {
            waitBefore(.alignNode, nowS: nowS, reason: "已到节点")
        }
    }

    private func routeContains(pose: Pose2D) -> Bool {
        if terminalCorrection, isReturnTerminal { return pose.distanceTo(map.executionStart.pose) <= 0.30 }
        guard map.hasCapturedRoute else { return true }
        guard legIndices.indices.contains(waypointIndex), let target = target,
              let plan = map.routePlan else { return false }
        let index = legIndices[waypointIndex]
        guard corridors.indices.contains(index) else { return false }
        let radius = plan.legs[index].trackingRadiusM + 0.10
        return TrajectoryCorridor.containsSegment(from: pose, to: target.pose,
            centerline: corridors[index], radius: radius)
    }

    private func legCorridor() -> [Pose2D]? {
        guard map.hasCapturedRoute, legIndices.indices.contains(waypointIndex),
              corridors.indices.contains(legIndices[waypointIndex]) else { return nil }
        return corridors[legIndices[waypointIndex]]
    }

    private func bandRadiusForLivePosition() -> Double {
        guard legIndices.indices.contains(waypointIndex),
              let plan = map.routePlan, plan.legs.indices.contains(legIndices[waypointIndex]) else { return 0.15 }
        return plan.legs[legIndices[waypointIndex]].trackingRadiusM + 0.10
    }

    /// Signed perpendicular offset from the recorded leg, positive to the left.
    private func corridorOffset(pose: Pose2D) -> Double? {
        guard let line = legCorridor(), line.count >= 2 else { return nil }
        var best = (distance: Double.infinity, offset: 0.0)
        for (a, b) in zip(line, line.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y, length2 = dx * dx + dy * dy
            guard length2 > 1e-12 else { continue }
            let t = max(0, min(1, ((pose.x - a.x) * dx + (pose.y - a.y) * dy) / length2))
            let qx = a.x + t * dx, qy = a.y + t * dy
            let distance = hypot(pose.x - qx, pose.y - qy)
            if distance < best.distance {
                best = (distance, (-(pose.x - qx) * dy + (pose.y - qy) * dx) / sqrt(length2))
            }
        }
        return best.distance.isFinite ? best.offset : nil
    }

    /// Aim a short distance along the recorded corridor. Following a nearby
    /// point avoids the long pivot towards the far endpoint of a leg.
    private func legLookaheadBearing(pose: Pose2D) -> Double? {
        guard let line = legCorridor(), line.count >= 2 else { return nil }
        var best = (distance: Double.infinity, index: 0, t: 0.0)
        for index in 0..<(line.count - 1) {
            let a = line[index], b = line[index + 1]
            let dx = b.x - a.x, dy = b.y - a.y, length2 = dx * dx + dy * dy
            guard length2 > 1e-12 else { continue }
            let t = max(0, min(1, ((pose.x - a.x) * dx + (pose.y - a.y) * dy) / length2))
            let distance = hypot(pose.x - (a.x + t * dx), pose.y - (a.y + t * dy))
            if distance < best.distance { best = (distance, index, t) }
        }
        guard best.distance.isFinite else { return nil }
        let a = line[best.index], b = line[best.index + 1]
        var point = Pose2D(x: a.x + (b.x - a.x) * best.t,
                           y: a.y + (b.y - a.y) * best.t, yawRad: b.yawRad)
        var budget = config.lookaheadM - (1 - best.t) * a.distanceTo(b)
        var index = best.index
        while budget > 0, index + 1 < line.count - 1 {
            index += 1
            let start = line[index], end = line[index + 1]
            let length = start.distanceTo(end)
            if length < 1e-9 { continue }
            if budget <= length {
                let t = budget / length
                point = Pose2D(x: start.x + (end.x - start.x) * t,
                               y: start.y + (end.y - start.y) * t, yawRad: end.yawRad)
                budget = 0
                break
            }
            point = end; budget -= length
        }
        if point.distanceTo(pose) < 0.05, let target = target { point = target.pose }
        return pose.bearingTo(point)
    }

    /// Direction of the corridor at the current node. Using the end of a whole
    /// leg would be wrong for automatic vertices in the middle of that leg.
    private func routeAlong(pose: Pose2D) -> Double? {
        guard let line = legCorridor(), line.count >= 2 else { return nil }
        var traveled = 0.0
        var best = (distance: Double.infinity, along: 0.0)
        for (a, b) in zip(line, line.dropFirst()) {
            let dx = b.x - a.x, dy = b.y - a.y, length2 = dx * dx + dy * dy
            guard length2 > 1e-12 else { continue }
            let length = sqrt(length2)
            let t = max(0, min(1, ((pose.x - a.x) * dx + (pose.y - a.y) * dy) / length2))
            let distance = hypot(pose.x - (a.x + t * dx), pose.y - (a.y + t * dy))
            if distance < best.distance { best = (distance, traveled + t * length) }
            traveled += length
        }
        guard best.distance.isFinite else { return nil }
        return best.along
    }

    private func arrivalDirection() -> (x: Double, y: Double)? {
        guard let target = target, let line = legCorridor(), line.count >= 2 else { return nil }
        let end = line[line.count - 1], previous = line[line.count - 2]
        let dx = end.x - previous.x, dy = end.y - previous.y
        let length = hypot(dx, dy)
        guard length > 1e-9 else { return nil }
        return (dx / length, dy / length)
    }

    /// Position relative to the local arrival direction at the node.
    private func arrivalMetrics(_ pose: Pose2D) -> (along: Double, lateral: Double)? {
        guard let target = target, let ux = arrivalDirection()?.x,
              let uy = arrivalDirection()?.y else { return nil }
        let rx = pose.x - target.pose.x, ry = pose.y - target.pose.y
        return (rx * ux + ry * uy, abs(-rx * uy + ry * ux))
    }

    /// A node is accepted with a generous radius. Just past it still counts;
    /// only a real overshoot triggers the short reverse.
    private func atTarget(pose: Pose2D) -> Bool {
        guard map.hasCapturedRoute, let metrics = arrivalMetrics(pose) else {
            return distanceToTargetM <= config.positionToleranceM
        }
        return metrics.lateral <= config.lateralToleranceM
            && distanceToTargetM <= config.positionToleranceM
    }

    private func positionOvershot(pose: Pose2D, nowS: Double) -> Bool {
        guard map.hasCapturedRoute, let metrics = arrivalMetrics(pose) else { return false }
        // Automatic vertices are waymarks along one recorded leg. Once passed,
        // the next leg resumes from the live pose; stopping there would create
        // a new pivot in the middle of a straight run.
        if target?.isAutomatic == true, metrics.along > config.arrivalOvershootM {
            waypointIndex += 1
            progressWaypointIndex = -1
            lineBearing = nil
            phase = .driveLine
            message = "已通过自动子节点，沿航线继续。"
            return true
        }
        guard metrics.along > config.arrivalOvershootM else { return false }
        guard beginReverseIfNeeded(pose: pose, nowS: nowS) else {
            stop(reason: "冲过节点后两次微调仍未回到范围，已停车；请将车移回原路线。")
            return true
        }
        return true
    }

    private func beginReverseIfNeeded(pose: Pose2D, nowS: Double) -> Bool {
        if reverseAttemptIndex != waypointIndex { reverseAttemptIndex = waypointIndex; reverseAttempts = 0 }
        guard reverseAttempts < 2, backing == nil else { return false }
        reverseAttempts += 1
        backing = Backing(targetIndex: waypointIndex, origin: pose, maxLengthM: config.maxReverseM,
                          pulsing: true, untilS: nowS + 0.30, startedS: nowS)
        isReversing = true
        lineBearing = nil
        phase = .reversing
        message = "冲过节点，向后短暂微调。"
        return true
    }

    /// Short reverse pulses keep the camera from a long oscillation. Stop as
    /// soon as the live position is close to the node again.
    private func reverse(pose: Pose2D, nowS: Double) {
        guard var back = backing else { phase = .alignLine; isReversing = false; return }
        turn.reset(); cancelTurnStop()
        let moved = back.origin.distanceTo(pose)
        let remaining = target.map { pose.distanceTo($0.pose) } ?? .infinity
        let close = remaining <= 0.12
        let timedOut = nowS - back.startedS >= config.reverseTimeoutS
        let reachedLimit = moved >= back.maxLengthM
        if back.targetIndex != waypointIndex || close {
            backing = nil; isReversing = false; link.stop()
            lineBearing = nil
            waitBefore(.alignLine, nowS: nowS,
                       reason: close ? "已退回节点附近，重新对准航线" : "后退微调结束，重新对准航线")
            return
        }
        if timedOut || reachedLimit {
            backing = nil; isReversing = false; link.stop(); lineBearing = nil
            stop(reason: "后退微调未能回到目标附近，已停车；请将车移回原路线。")
            return
        }
        if back.pulsing {
            if nowS < back.untilS {
                let speed = -config.cruiseSpeed * min(1, max(0.2, config.reverseSpeedFraction))
                link.drive(left: speed, right: speed)
                message = String(format: "向后微调，已退 %.0f cm。", moved * 100)
                backing = back
                return
            }
            back.pulsing = false
            back.untilS = nowS + 0.15
            backing = back; link.stop()
            message = "向后微调，短暂制动。"
            return
        }
        if nowS < back.untilS { link.stop(); backing = back; return }
        back.pulsing = true
        back.untilS = nowS + 0.30
        backing = back
        message = "继续向后微调。"
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
        if let reference = pending.reference,
           pose.distanceTo(reference) > 0.30 || abs(wrapDeg(pose.yawDeg - reference.yawDeg)) > 45 {
            pending.stableSinceS = nil; pending.stableReference = nil; pending.frames = 0
            recovery = pending
            message = "恢复位姿与停车前不连续，保持停车等待；不会自动重置地图。"; return
        }
        if let previous = pending.stableReference, let time = pending.previousTimeS,
           pose.distanceTo(previous) > 0.03 || abs(wrapDeg(pose.yawDeg - previous.yawDeg)) > 3
            || nowS - time > 0.2 || nowS <= time {
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
    /// tracking watchdog. A generation check rejects stale timers.
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
        message = String(format: "%@；停车稳定 %.1f 秒。", reason, config.stagePauseS)
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
