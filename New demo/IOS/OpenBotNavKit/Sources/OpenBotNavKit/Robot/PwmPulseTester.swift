import Foundation

public enum PwmTestAction: String {
    case forward, turnLeft, turnRight
}

/// Explicit, one-second bench commands. Calling tick after cancellation can
/// never restart motion. BLE heartbeat/watchdog remains owned by the link.
public final class PwmPulseTester {
    private let link: RobotLink
    private var deadlineS = 0.0
    private var left = 0.0
    private var right = 0.0
    public private(set) var active = false
    public private(set) var lastFrame = "c0,0"

    public init(link: RobotLink) { self.link = link }

    @discardableResult
    public func start(_ action: PwmTestAction, settings: NavigationPwmSettings, nowS: Double) -> Bool {
        stop()
        guard settings.valid, nowS.isFinite, link.telemetry.connected, link.telemetry.bumper == nil else { return false }
        let drive = Double(settings.drivePwm) / 255
        let leftTurn = Double(settings.leftTurnPwm) / 255
        let rightTurn = Double(settings.rightTurnPwm) / 255
        switch action {
        case .forward: left = drive; right = drive
        case .turnLeft: left = -leftTurn; right = leftTurn
        case .turnRight: left = rightTurn; right = -rightTurn
        }
        deadlineS = nowS + 1
        active = true
        tick(nowS: nowS)
        return true
    }

    public func tick(nowS: Double) {
        guard active else { return }
        guard nowS.isFinite, nowS < deadlineS, link.telemetry.connected, link.telemetry.bumper == nil else {
            stop()
            return
        }
        link.drive(left: left, right: right)
        lastFrame = String(decoding: OpenBotProtocol.ctrlCommand(left: left, right: right), as: UTF8.self)
            .trimmingCharacters(in: .newlines)
    }

    public func stop() {
        active = false
        left = 0; right = 0
        lastFrame = "c0,0"
        link.stop()
    }
}
