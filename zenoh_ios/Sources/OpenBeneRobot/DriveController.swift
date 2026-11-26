import Foundation

/// Turns keyboard events into repeatable wheel commands.
///
/// Holding a key repeats its command every 100 ms; releasing it (or releasing
/// every key) immediately sends stop, matching the safety model of
/// openbene_sdk/examples/keyboard_ble_drive.py.
@MainActor
public final class DriveController: ObservableObject {
    @Published public private(set) var activeKey: DriveKey?
    @Published public var speedPercent: Double = 47   // 120 PWM of 255
    @Published public var turnPercent: Double = 35    // 90 PWM of 255
    @Published public var arcScale: Double = 0.55
    @Published public private(set) var lastCommand: WheelCommand = .stop

    private let link: OpenBotLink
    private let queue = DispatchQueue(label: "io.openbene.drive.repeat", qos: .userInteractive)
    private var repeatTimer: DispatchSourceTimer?
    private var remoteWatchdog: Timer?
    private let repeatInterval: TimeInterval = 0.1

    public init(link: OpenBotLink) {
        self.link = link
    }

    /// PWM values derived from the sliders.
    public var drivePWM: Int {
        OpenBotBLE.clampPWM(Int((speedPercent / 100) * Double(OpenBotBLE.maxPWM)))
    }

    public var turnPWM: Int {
        OpenBotBLE.clampPWM(Int((turnPercent / 100) * Double(OpenBotBLE.maxPWM)))
    }

    public var isDriving: Bool { activeKey != nil && activeKey != .stop }

    public func press(_ character: Character) {
        guard let key = DriveKey(rawValue: Character(character.lowercased())) else { return }
        press(key)
    }

    public func press(_ key: DriveKey) {
        if key == .stop || key == .space {
            releaseAll()
            return
        }
        activeKey = key
        let command = command(for: key)
        lastCommand = command
        link.send(command)
        startRepeating(command)
    }

    /// Called when the key goes up. Repeating stops; the robot is told to stop.
    public func release(_ character: Character) {
        guard let key = DriveKey(rawValue: Character(character.lowercased())) else { return }
        guard activeKey == key else { return }
        releaseAll()
    }

    public func releaseAll() {
        stopRepeating()
        remoteWatchdog?.invalidate()
        remoteWatchdog = nil
        activeKey = nil
        lastCommand = .stop
        link.stop()
    }

    /// Applies normalized wheel speeds received from the PC (-1...1).
    /// Unlike the preset keys this keeps the magnitude, so the PC's speed
    /// slider maps to real PWM values on the robot.
    public func applyRemote(left: Double, right: Double) {
        let leftPWM = Int((min(max(left, -1), 1) * Double(OpenBotBLE.maxPWM)).rounded())
        let rightPWM = Int((min(max(right, -1), 1) * Double(OpenBotBLE.maxPWM)).rounded())
        if leftPWM == 0 && rightPWM == 0 {
            releaseAll()
            return
        }
        stopRepeating()
        activeKey = nil
        let command = WheelCommand(left: leftPWM, right: rightPWM, label: "远程")
        lastCommand = command
        link.send(command)
        startRepeating(command)
        // If the PC page disappears mid-drive, stop instead of running on.
        remoteWatchdog?.invalidate()
        remoteWatchdog = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.releaseAll() }
        }
    }

    private func command(for key: DriveKey) -> WheelCommand {
        DriveMapping.command(
            for: key,
            drivePWM: drivePWM,
            turnPWM: turnPWM,
            arcScale: arcScale
        )
    }

    private func startRepeating(_ command: WheelCommand) {
        stopRepeating()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + repeatInterval, repeating: repeatInterval)
        timer.setEventHandler { [weak self] in
            Task { @MainActor in self?.link.send(command) }
        }
        timer.resume()
        repeatTimer = timer
    }

    private func stopRepeating() {
        repeatTimer?.cancel()
        repeatTimer = nil
    }

    deinit {
        repeatTimer?.cancel()
    }
}
