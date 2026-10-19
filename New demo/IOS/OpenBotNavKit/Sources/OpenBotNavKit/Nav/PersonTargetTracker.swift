import Foundation

/// Geometric association and temporal smoothing, not biometric identity.
/// An unmatched detection never immediately replaces the tracked person.
public struct PersonTargetTracker {
    private var previous: PersonBox?
    private var filtered: PersonBox?
    private var lastTime = -Double.infinity
    public private(set) var matchedBox: PersonBox?
    public private(set) var horizontalVelocityX = 0.0
    public init() {}
    public mutating func reset() { self = PersonTargetTracker() }

    public mutating func update(_ boxes: [PersonBox], time: Double) -> PersonBox? {
        if time - lastTime > 0.6 { reset() }
        matchedBox = nil
        let selected: PersonBox?
        if let old = previous {
            selected = boxes.filter { Self.iou(old, $0) > 0.05 || hypot(old.centreX - $0.centreX, old.centreY - $0.centreY) < 0.30 }
                .max { Self.score(old, $0) < Self.score(old, $1) }
        } else {
            selected = boxes.max { $0.width * $0.height < $1.width * $1.height }
        }
        guard let next = selected else { return nil }
        if let old = previous, time > lastTime {
            let dt = time - lastTime
            let velocity = min(2, max(-2, (next.centreX - old.centreX) / dt))
            horizontalVelocityX += (1 - exp(-dt / 0.12)) * (velocity - horizontalVelocityX)
        }
        let alpha = min(1, max(0.05, 1 - exp(-(time - lastTime) / 0.10)))
        let result: PersonBox
        if let old = filtered {
            result = PersonBox(centreX: old.centreX + alpha * (next.centreX - old.centreX),
                centreY: next.centreY, width: next.width, height: next.height)
        } else { result = next }
        previous = next; matchedBox = next; filtered = result; lastTime = time
        return result
    }

    private static func score(_ a: PersonBox, _ b: PersonBox) -> Double {
        2 * iou(a, b) - hypot(a.centreX - b.centreX, a.centreY - b.centreY)
    }
    private static func iou(_ a: PersonBox, _ b: PersonBox) -> Double {
        let w = max(0, min(a.centreX + a.width / 2, b.centreX + b.width / 2) - max(a.centreX - a.width / 2, b.centreX - b.width / 2))
        let h = max(0, min(a.centreY + a.height / 2, b.centreY + b.height / 2) - max(a.centreY - a.height / 2, b.centreY - b.height / 2))
        let area = w * h
        return area / max(1e-9, a.width * a.height + b.width * b.height - area)
    }
}

/// OpenBot-style forward differential steering. Slew limiting prevents a
/// noisy detection from commanding alternate full-power opposite pivots.
public struct ObjectFollowSteering {
    private var steer = 0.0
    private var lastTime: Double?
    private var cornerDirection = 0
    private var cornerMoving = false
    private var cornerPulseUntil = -Double.infinity
    private var cornerBrakeUntil = -Double.infinity
    public init() {}
    public mutating func reset() { self = ObjectFollowSteering() }

    public mutating func command(box: PersonBox, pwm: NavigationPwmSettings, nowS: Double, holdForward: Bool,
                                velocityX: Double = 0, observedCentreX: Double? = nil) -> FollowCommand {
        let error = box.centreX - 0.5
        let velocity = velocityX.isFinite ? min(2, max(-2, velocityX)) : 0
        let desired = abs(error) <= 0.04 && abs(velocity) < 0.1 ? 0 : min(1, max(-1, (error + velocity * 0.10) * 2))
        let dt = min(0.1, max(0, nowS - (lastTime ?? (nowS - 0.05))))
        steer += min(2 * dt, max(-2 * dt, desired - steer)); lastTime = nowS
        if holdForward {
            cornerDirection = 0; cornerMoving = false; cornerBrakeUntil = -Double.infinity
            guard steer * desired > 0 else { return FollowCommand(left: 0, right: 0, action: "centering reversal brake") }
            guard abs(steer) > 0.12 else { return FollowCommand(left: 0, right: 0, action: "holding") }
            let speed = Double(steer > 0 ? pwm.rightTurnPwm : pwm.leftTurnPwm) / 255
            // Brief impulses separated by braking only in the stationary,
            // near-person case; forward tracking remains a continuous arc.
            guard nowS.truncatingRemainder(dividingBy: 0.4) < 0.12 else {
                return FollowCommand(left: 0, right: 0, action: "near turn braking")
            }
            return FollowCommand(left: steer > 0 ? speed : -speed, right: steer > 0 ? -speed : speed, action: "stationary centering")
        }
        let observedError = (observedCentreX ?? box.centreX) - 0.5
        if cornerDirection != 0 {
            if abs(observedError) <= 0.10 {
                cornerDirection = 0; cornerMoving = false; steer = 0
                cornerBrakeUntil = nowS + 0.2
                return FollowCommand(left: 0, right: 0, action: "corner braking")
            }
            if observedError * Double(cornerDirection) < 0 {
                cornerDirection = observedError > 0 ? 1 : -1
                cornerMoving = false; cornerBrakeUntil = nowS + 0.3
            }
        } else if abs(observedError) > 0.22 ||
                    (abs(observedError) > 0.18 && observedError * velocity > 0 && abs(observedError + velocity * 0.12) > 0.24) {
            cornerDirection = observedError > 0 ? 1 : -1
            cornerMoving = false
            cornerBrakeUntil = max(cornerBrakeUntil, nowS + 0.08)
        }
        if nowS < cornerBrakeUntil { return FollowCommand(left: 0, right: 0, action: "corner braking") }
        if cornerDirection != 0 {
            if cornerMoving, nowS >= cornerPulseUntil {
                cornerMoving = false; cornerBrakeUntil = nowS + 0.12
                return FollowCommand(left: 0, right: 0, action: "corner braking")
            }
            if !cornerMoving { cornerMoving = true; cornerPulseUntil = nowS + 0.18 }
            let speed = Double(cornerDirection > 0 ? pwm.rightTurnPwm : pwm.leftTurnPwm) / 255
            return FollowCommand(left: Double(cornerDirection) * speed, right: -Double(cornerDirection) * speed, action: "corner pivot")
        }
        let base = Double(pwm.drivePwm) / 255
        let turn = Double(steer >= 0 ? pwm.rightTurnPwm : pwm.leftTurnPwm) / 255
        let outer = base + (turn - base) * abs(steer)
        let inner = base * (1 - abs(steer))
        return steer >= 0 ? FollowCommand(left: outer, right: inner, action: "forward arc")
            : FollowCommand(left: inner, right: outer, action: "forward arc")
    }
}
