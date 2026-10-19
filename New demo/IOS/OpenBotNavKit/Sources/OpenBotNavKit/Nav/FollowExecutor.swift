import Foundation

/// Image tracking with measured depth range; body size/box top are not range.
/// Camera/link failure, invalid input, lost target and manual stop still stop.
public final class FollowExecutor {
    public static let observationTtlS = 0.60
    private let link: RobotLink
    private var pwm: NavigationPwmSettings
    public private(set) var options = FollowTestOptions()
    public private(set) var active = false
    public private(set) var status = "等待人体；近人停车默认开启，请手动开始跟随。"
    public private(set) var lastCommand = FollowCommand(left: 0, right: 0, action: "stopped")
    public private(set) var box: PersonBox?
    public private(set) var distanceM: Double?
    public private(set) var personCount = 0
    public private(set) var pending: String?
    public private(set) var deadlineS: Double?
    public private(set) var targetState = "尚无检测结果"
    public private(set) var gateReason = "未启动"
    private var lastObservedTimeS: Double?
    private var lastSeenTimeS = -Double.infinity
    private var lastMatchedBox: PersonBox?
    private var stableCount = 0
    private var motionStartedS: Double?
    private var lastTurn = 0
    private var turnStoppedS: Double?
    private var reversalUntilS = -Double.infinity
    private var reversingTo = 0
    private var latestTimeS = 0.0
    private var nearHolding = false
    private var rangeClearSinceS: Double?
    private var rangeClearFrames = 0
    private var targetTracker = PersonTargetTracker()
    private var arcSteering = ObjectFollowSteering()
    private var trackingPausedSinceS: Double?
    private var trackingStableSinceS: Double?
    private var requiredFrames: Int { options.requireStableTarget ? 3 : 1 }
    private var ttlS: Double { options.strictDetectionTimeout ? 0.35 : Self.observationTtlS }

    public init(link: RobotLink, pwm: NavigationPwmSettings = .defaults) { self.link = link; self.pwm = pwm }

    public func applyPwm(_ value: NavigationPwmSettings) {
        stop(reason: "PWM已更新，请重新开始跟随。")
        pwm = value
    }

    public func applyOptions(_ value: FollowTestOptions) {
        clearTarget()
        guard value.valid else { status = "测试参数无效，已停车。"; return }
        options = value
        status = value.enabledNames.isEmpty ? "门槛全部关闭；手动开始后连续跟随，请先架空。" : "已启用：" + value.enabledNames.joined(separator: "、") + "；请手动开始。"
    }

    public func observe(_ boxes: [PersonBox], timestampS: Double) {
        observeCandidates(boxes.map { PersonDetection(box: $0, confidence: 1) }, timestampS: timestampS)
    }

    private func observeCandidates(_ candidates: [PersonDetection], timestampS: Double) {
        guard timestampS.isFinite else { stop(reason: "人体检测时间无效，已停车。"); return }
        if let previous = lastObservedTimeS, timestampS <= previous { return }
        if let previous = lastObservedTimeS, timestampS - previous > ttlS {
            stableCount = 0; lastMatchedBox = nil; rangeClearSinceS = nil; rangeClearFrames = 0
        }
        if let previous = lastObservedTimeS, timestampS - previous > 0.3 { rangeClearSinceS = nil; rangeClearFrames = 0 }
        latestTimeS = max(latestTimeS, timestampS)
        lastObservedTimeS = timestampS
        let boxes = candidates.map(\.box)
        distanceM = nil
        personCount = boxes.count
        guard !boxes.isEmpty else {
            targetState = "未检测到人体"; box = nil; stableCount = 0
            rangeClearSinceS = nil; rangeClearFrames = 0
            arcSteering.reset()
            zero(reason: "无目标")
            if active { status = "当前未看到目标，已零输出。" }
            return
        }
        if options.requireSinglePerson, boxes.count > 1 {
            rangeClearSinceS = nil; rangeClearFrames = 0
            targetState = "单人门槛：检测到多人"; box = nil; stableCount = 0
            zero(reason: "单人门槛")
            if active { status = "单人门槛触发，停车等待目标恢复。" }
            return
        }
        let validDetections = candidates.filter { Self.numericAndVisible($0.box) }
        let validBoxes = validDetections.map(\.box)
        guard let next = targetTracker.update(validBoxes, time: timestampS) else {
            targetState = validBoxes.isEmpty ? "检测框无效" : "等待匹配原目标"
            box = nil; stableCount = 0; arcSteering.reset()
            rangeClearSinceS = nil; rangeClearFrames = 0
            zero(reason: targetState); return
        }
        if options.rejectEdgeBoxes, !Self.awayFromEdges(next) {
            rangeClearSinceS = nil; rangeClearFrames = 0
            targetState = "四边门槛：检测框贴边"; box = nil; stableCount = 0
            zero(reason: "四边门槛")
            if active { status = "四边门槛触发，停车等待目标回到画面内。" }
            return
        }
        if options.rejectTargetJump, let previous = lastMatchedBox {
            let ratio = next.height / previous.height
            if hypot(next.centreX - previous.centreX, next.centreY - previous.centreY) > 0.20 || !(0.55...1.7).contains(ratio) {
                stableCount = 0
                rangeClearSinceS = nil; rangeClearFrames = 0
                lastMatchedBox = next; box = nil
                zero(reason: "目标跳变门槛")
                if active { status = "目标跳变门槛触发，停车等待新鲜目标。" }
                return
            }
        }
        lastMatchedBox = next; box = next; lastSeenTimeS = timestampS
        if let measured = validDetections.first(where: { $0.box == targetTracker.matchedBox })?.distanceM,
           measured.isFinite, (0.05...8).contains(measured) { distanceM = measured }
        if let distance = distanceM, distance > options.stopDistanceM + 0.2 {
            if rangeClearSinceS == nil { rangeClearSinceS = timestampS }
            rangeClearFrames += 1
        } else { rangeClearSinceS = nil; rangeClearFrames = 0 }
        stableCount = min(3, stableCount + 1)
        targetState = stableCount >= requiredFrames ? (boxes.count == 1 ? "已检测到目标" : "\(boxes.count)个框，按连续位置匹配目标") : "稳定帧门槛：\(stableCount)/3"
    }

    public func observeDetections(_ detections: [PersonDetection], timestampS: Double) {
        let eligible = detections.filter {
            $0.confidence.isFinite && (0...1).contains($0.confidence) && (!options.confidenceFilter || $0.confidence >= 0.6)
        }
        observeCandidates(eligible, timestampS: timestampS)
    }

    public func clearTarget() {
        stop()
        box = nil; distanceM = nil; personCount = 0; stableCount = 0
        targetState = "尚无检测结果"
        lastMatchedBox = nil; lastObservedTimeS = nil; lastSeenTimeS = -Double.infinity
        targetTracker.reset()
    }

    public func hasFreshTarget(nowS: Double) -> Bool {
        stableCount >= requiredFrames && box != nil && nowS >= lastSeenTimeS && nowS - lastSeenTimeS <= ttlS
    }

    public func requestStart(nowS: Double, delayS: Double = 5) {
        stop(reason: "准备跟随；倒计时只留出走到相机前的时间，距离由深度测量。")
        guard nowS.isFinite, delayS.isFinite, delayS >= 0, pwm.valid else { return }
        pending = "start"; deadlineS = nowS + delayS
    }

    public func stop(reason: String = "跟随已停车；再次跟随需手动开始。") {
        active = false; pending = nil; deadlineS = nil
        motionStartedS = nil; lastTurn = 0; turnStoppedS = nil; reversalUntilS = -Double.infinity; reversingTo = 0
        nearHolding = false; rangeClearSinceS = nil; rangeClearFrames = 0
        trackingPausedSinceS = nil; trackingStableSinceS = nil
        arcSteering.reset()
        status = reason; zero(reason: reason)
    }

    public func pauseForTracking(nowS: Double, reason: String = "相机跟踪受限") {
        guard active, nowS.isFinite else {
            if pending != nil { stop(reason: "准备期间相机不可用，请重新开始。"); return }
            zero(reason: reason); return
        }
        if trackingPausedSinceS == nil { trackingPausedSinceS = nowS }
        trackingStableSinceS = nil
        zero(reason: "相机跟踪等待恢复")
        status = reason + "；已停车，等待同一会话恢复。"
    }

    public func tick(nowS: Double, trackingNormal: Bool, linkAvailable: Bool) {
        guard active || pending != nil else { return }
        guard nowS.isFinite, linkAvailable, link.telemetry.bumper == nil else {
            stop(reason: link.telemetry.bumper != nil ? "检测到碰撞，已停车。" : "相机跟踪或蓝牙不可用，已停车；请恢复后手动开始。")
            return
        }
        latestTimeS = max(latestTimeS, nowS)
        if !trackingNormal {
            pauseForTracking(nowS: nowS)
            if let start = trackingPausedSinceS, nowS - start > 15 { stop(reason: "相机15秒未恢复，已结束跟随；请手动开始。") }
            return
        }
        if let start = trackingPausedSinceS {
            guard nowS - start <= 15 else { stop(reason: "相机15秒未恢复，已结束跟随。"); return }
            if trackingStableSinceS == nil { trackingStableSinceS = nowS }
            guard nowS - (trackingStableSinceS ?? nowS) >= 0.5 - 1e-9 else {
                zero(reason: "相机恢复确认"); status = "相机已恢复，停车确认0.5秒。"; return
            }
            trackingPausedSinceS = nil; trackingStableSinceS = nil
        }
        if let deadline = deadlineS {
            zero(reason: "准备倒计时")
            if nowS < deadline { status = "准备跟随：\(Int(ceil(deadline - nowS)))秒；不设定距离。"; return }
            pending = nil; deadlineS = nil
            guard hasFreshTarget(nowS: nowS) else {
                stop(reason: "跟随未启动：\(targetState)或检测已过期。"); return
            }
            active = true; motionStartedS = nowS
        }
        guard active else { return }
        guard nowS >= lastSeenTimeS, nowS - lastSeenTimeS <= ttlS else {
            arcSteering.reset()
            zero(reason: "等待新鲜目标")
            status = String(format: "超过%.2f秒无有效目标，停车等待；目标重新可见后继续。", ttlS); return
        }
        guard let target = box, stableCount >= requiredFrames else {
            zero(reason: "目标缺失或稳定帧门槛"); status = "目标暂不可用，停车等待。"; return
        }
        if options.stopWhenNear {
            if distanceM == nil || (distanceM ?? 0) <= options.stopDistanceM {
                nearHolding = true; rangeClearSinceS = nil; rangeClearFrames = 0
            } else if nearHolding, rangeClearFrames >= 3, let since = rangeClearSinceS,
                      lastSeenTimeS - since >= 0.4 - 1e-9 { nearHolding = false }
        } else { nearHolding = false }
        let command = arcSteering.command(box: target, pwm: pwm, nowS: nowS, holdForward: nearHolding,
            velocityX: targetTracker.horizontalVelocityX, observedCentreX: targetTracker.matchedBox?.centreX)
        let turn = command.left * command.right < 0 ? (command.right > 0 ? 1 : -1) : 0
        if options.pauseBeforeReversal {
            if reversingTo != 0 {
                if nowS < reversalUntilS { zero(reason: "反向等待"); status = "反向门槛：停车等待2秒。"; return }
                lastTurn = reversingTo; reversingTo = 0
            }
            if turn != 0, lastTurn != 0, turn != lastTurn {
                reversingTo = turn
                reversalUntilS = max(nowS, (turnStoppedS ?? nowS) + 2)
                zero(reason: "反向等待"); status = "反向门槛：停车等待2秒。"; return
            }
        }
        if turn != 0 { lastTurn = turn }
        let elapsed = nowS - (motionStartedS ?? nowS)
        if options.pulseTurns, turn != 0, elapsed.truncatingRemainder(dividingBy: 0.35) >= 0.10 {
            zero(reason: "转向脉冲制动"); status = "转向脉冲门槛：正在制动。"; return
        }
        lastCommand = command; turnStoppedS = nil
        gateReason = nearHolding ? (distanceM == nil ? "距离未知，禁止前进" : "近人停车，禁止前进") : "无门槛拦截"
        link.drive(left: command.left, right: command.right)
        if nearHolding {
            status = distanceM == nil ? "人体已识别，距离测量暂不可用；停车等待深度数据，可原地对准。"
                : String(format: "距人约%.2fm，保持停车；远于%.2fm并稳定后继续。", distanceM ?? 0, options.stopDistanceM + 0.2)
        } else if command.action == "corner pivot" || command.action == "corner braking" {
            status = "急转弯：先停止前进，原地转向保持目标在画面内。"
        } else {
            status = command.left < command.right ? "向左弧线跟随" : (command.left > command.right ? "向右弧线跟随" : "连续前进跟随")
        }
    }

    private func zero(reason: String) {
        if lastCommand.left * lastCommand.right < 0 && turnStoppedS == nil { turnStoppedS = latestTimeS }
        gateReason = reason
        lastCommand = FollowCommand(left: 0, right: 0, action: "stopped"); link.stop()
    }

    private static func numericAndVisible(_ box: PersonBox) -> Bool {
        [box.centreX, box.centreY, box.width, box.height].allSatisfy { $0.isFinite } &&
        box.width > 0 && box.height > 0 && box.width <= 1 && box.height <= 1 &&
        (0...1).contains(box.centreX) && (0...1).contains(box.centreY)
    }

    private static func awayFromEdges(_ box: PersonBox) -> Bool {
        box.centreX - box.width / 2 > 0.015 && box.centreX + box.width / 2 < 0.985 &&
        box.centreY - box.height / 2 > 0.015 && box.centreY + box.height / 2 < 0.985
    }
}
