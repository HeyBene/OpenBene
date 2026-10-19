import Foundation

public enum SettledTurnAction: Equatable {
    case drive(left: Double, right: Double)
    case hold(String)
    case aligned
    case failed(String)
}

/// Keep the configured PWM needed to overcome friction, but shorten its duty
/// near the heading. A zero command separates pulses and precedes any reversal.
public struct SettledTurnController {
    private var startedAt: Double?
    private var progressAt = 0.0
    private var progressReferenceError = Double.infinity
    private var previousTime: Double?
    private var previousYaw: Double?
    private var totalRotation = 0.0
    private var rotationCheckpoint: Double?
    private var stableSince: Double?
    private var pulseUntil = -Double.infinity
    private var stoppedSince: Double?
    private var lastDirection = 0
    private var pulseDirection = 0
    private var moving = false
    public private(set) var poseJumpDetected = false
    public var commandExpiresAtS: Double? { moving ? pulseUntil : nil }
    public var diagnostics: [String: Double] {
        let time = previousTime ?? startedAt ?? 0
        return ["elapsedS": max(0, time - (startedAt ?? time)),
                "noProgressS": max(0, time - progressAt), "rotationDeg": totalRotation,
                "pulseRemainingS": moving ? max(0, pulseUntil - time) : 0]
    }
    public init() {}
    public mutating func reset() { self = SettledTurnController() }

    public mutating func update(errorRad: Double, yawRad: Double, nowS: Double,
                                toleranceDeg: Double, leftSpeed: Double, rightSpeed: Double,
                                reversalPauseS: Double = 2) -> SettledTurnAction {
        poseJumpDetected = false
        guard errorRad.isFinite, yawRad.isFinite, nowS.isFinite else { return .failed("转向位姿无效，已停车。") }
        let error = wrapRad(errorRad), magnitude = abs(error) * 180 / .pi
        if startedAt == nil { startedAt = nowS; progressAt = nowS }
        if let time = previousTime, nowS < time { return .failed("相机时间异常，已停车。") }
        if let yaw = previousYaw, let time = previousTime {
            let change = abs(wrapRad(yawRad - yaw)) * 180 / .pi
            if change > 60 && nowS - time < 0.3 {
                poseJumpDetected = true
                return .failed("朝向发生跳变，已停车；请检查手机固定姿态和相机跟踪。")
            }
        }
        previousTime = nowS; previousYaw = yawRad
        // Accumulating abs(frame-to-frame yaw) turns normal VIO noise into
        // hundreds of degrees. Count only net excursions of at least 3 degrees.
        if let checkpoint = rotationCheckpoint {
            let excursion = abs(wrapRad(yawRad - checkpoint)) * 180 / .pi
            if excursion >= 3 { totalRotation += excursion; rotationCheckpoint = yawRad }
        } else { rotationCheckpoint = yawRad }
        // After an overshoot or pose disturbance, improving from the current
        // error is progress even before beating the best error of the whole turn.
        if magnitude > progressReferenceError + 8 { progressReferenceError = magnitude }
        if magnitude < progressReferenceError - 1 { progressReferenceError = magnitude; progressAt = nowS }
        if nowS - (startedAt ?? nowS) > 45 {
            return .failed(String(format: "本次转向超过45秒，剩余%.1f°，已停车。", magnitude))
        }
        if totalRotation > 270 {
            return .failed(String(format: "本次有效累计转动超过270°，剩余%.1f°，已停车。", magnitude))
        }
        if magnitude <= toleranceDeg || (stableSince != nil && magnitude <= toleranceDeg + 2) {
            brake(at: nowS)
            if stableSince == nil { stableSince = nowS }
            if nowS - (stableSince ?? nowS) >= 0.35 { return .aligned }
            return .hold("方向已接近，停车确认稳定")
        }
        stableSince = nil
        if nowS - progressAt > 8 { return .failed(String(format: "转向8秒无有效进展，剩余%.1f°，已停车；请检查PWM和手机姿态。", magnitude)) }
        let direction = error >= 0 ? 1 : -1
        let speed = direction > 0 ? leftSpeed : rightSpeed
        guard speed > 0 else { return .failed("该方向转向PWM为0，已停车。") }
        if moving {
            if direction != pulseDirection || nowS >= pulseUntil {
                brake(at: nowS)
                return .hold("转向制动，等待车身稳定")
            }
            return .drive(left: -Double(direction) * speed, right: Double(direction) * speed)
        }
        if let stopped = stoppedSince {
            let pause = lastDirection != 0 && direction != lastDirection ? max(2, reversalPauseS) : 0.25
            if nowS - stopped < pause { return .hold(pause >= 2 ? "纠偏需要反向，停车等待2秒" : "转向制动，等待车身稳定") }
        }
        // Nonblocking pulses. Smaller errors receive shorter full-PWM pushes.
        let duration = magnitude > 45 ? 0.20 : (magnitude > 15 ? 0.10 : 0.04)
        pulseUntil = nowS + duration
        pulseDirection = direction; lastDirection = direction; moving = true; stoppedSince = nil
        return .drive(left: -Double(direction) * speed, right: Double(direction) * speed)
    }

    private mutating func brake(at time: Double) {
        if moving || stoppedSince == nil { stoppedSince = time }
        moving = false
    }
}
