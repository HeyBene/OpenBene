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
        activeKey = nil
        lastCommand = .stop
        link.stop()
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
