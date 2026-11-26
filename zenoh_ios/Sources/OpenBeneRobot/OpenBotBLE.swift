import Foundation

/// OpenBot ESP32 BLE protocol, mirrored from openbene_sdk/src/openbene/esp32_ble.py
/// and the keyboard example (examples/keyboard_ble_drive.py).
public enum OpenBotBLE {
    public static let serviceUUID = "61653dc3-4021-4d1e-ba83-8b4eec61d613"
    /// Write characteristic: phone -> robot.
    public static let rxUUID = "06386c14-86ea-4d71-811c-48f97c58f8c9"
    /// Notify characteristic: robot -> phone.
    public static let txUUID = "9bf1103b-834c-47cf-b149-c9e4bcf778a7"

    public static let maxPWM = 255

    public static func clampPWM(_ value: Int, limit: Int = maxPWM) -> Int {
        let bound = min(abs(limit), maxPWM)
        guard bound > 0 else { return 0 }
        return min(bound, Swift.max(-bound, value))
    }

    /// `c120,-90\n` — drive command from the SDK's make_ctrl_cmd.
    public static func driveCommand(left: Int, right: Int) -> Data {
        Data("c\(clampPWM(left)),\(clampPWM(right))\n".utf8)
    }

    /// `h300\n` — the firmware stops the motors if heartbeats stop.
    public static func heartbeatCommand(intervalMs: Int) -> Data {
        Data("h\(max(1, intervalMs))\n".utf8)
    }

    public static func featureCommand() -> Data { Data("f\n".utf8) }

    /// `w500\n`, `v500\n`, `s500\n`
    public static func sensorStreamCommand(_ header: Character, intervalMs: Int) -> Data {
        Data("\(header)\(max(1, intervalMs))\n".utf8)
    }

    public static func isOpenBotName(_ name: String?) -> Bool {
        guard let name = name?.lowercased(), !name.isEmpty else { return false }
        return name.contains("openbot") || name.contains("rtr_520") || name.contains("rtr 520")
    }
}

/// One telemetry line from the ESP32 firmware.
public enum OpenBotTelemetry: Equatable, Sendable {
    case voltage(Double)
    case wheel(leftRPM: Double, rightRPM: Double)
    case sonar(distanceCm: Int)
    case bumper(String)
    case features(robotType: String, capabilities: [String])
    case unknown(String)

    public static func parse(_ raw: String) -> OpenBotTelemetry {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let header = line.first else { return .unknown(line) }
        let body = String(line.dropFirst())

        switch header {
        case "v":
            return Double(body).map { .voltage($0) } ?? .unknown(line)
        case "w":
            let parts = body.split(separator: ",")
            if parts.count >= 2,
               let left = Double(parts[0]), let right = Double(parts[1]) {
                return .wheel(leftRPM: left, rightRPM: right)
            }
            return .unknown(line)
        case "s":
            return Int(body).map { .sonar(distanceCm: $0) } ?? .unknown(line)
        case "b":
            return .bumper(body)
        case "f":
            // Firmware sends "f" + robot_type + ":" + "cap:" each, e.g.
            // "frtr520:s:vf:". Tolerate a stray leading colon.
            let spec = body.hasPrefix(":") ? String(body.dropFirst()) : body
            if let separator = spec.firstIndex(of: ":") {
                let type = String(spec[spec.startIndex..<separator])
                let capabilities = spec[spec.index(after: separator)...]
                    .split(separator: ":")
                    .map(String.init)
                    .filter { !$0.isEmpty }
                return .features(robotType: type, capabilities: capabilities)
            }
            return .features(robotType: spec, capabilities: [])
        default:
            return .unknown(line)
        }
    }
}

/// The keys the keyboard teleop understands, matching keyboard_ble_drive.py.
public enum DriveKey: Character, CaseIterable, Sendable {
    case forward = "w"
    case reverse = "s"
    case turnLeft = "a"
    case turnRight = "d"
    case arcLeft = "q"
    case arcRight = "e"
    case stop = "x"
    case space = " "

    public var symbol: String {
        switch self {
        case .forward: return "arrow.up"
        case .reverse: return "arrow.down"
        case .turnLeft: return "arrow.left"
        case .turnRight: return "arrow.right"
        case .arcLeft: return "arrow.up.left"
        case .arcRight: return "arrow.up.right"
        case .stop, .space: return "stop.fill"
        }
    }

    public var label: String {
        switch self {
        case .forward: return "前进"
        case .reverse: return "后退"
        case .turnLeft: return "左转"
        case .turnRight: return "右转"
        case .arcLeft: return "左弧线"
        case .arcRight: return "右弧线"
        case .stop, .space: return "停止"
        }
    }
}

public struct WheelCommand: Equatable, Sendable {
    public var left: Int
    public var right: Int
    public var label: String

    public init(left: Int, right: Int, label: String) {
        self.left = OpenBotBLE.clampPWM(left)
        self.right = OpenBotBLE.clampPWM(right)
        self.label = label
    }

    public static let stop = WheelCommand(left: 0, right: 0, label: "停止")
}

/// Pure mapping from a key to wheel speeds; defaults follow the SDK example.
public enum DriveMapping {
    public static func command(
        for character: Character,
        drivePWM: Int = 120,
        turnPWM: Int = 90,
        arcScale: Double = 0.55
    ) -> WheelCommand? {
        guard let key = DriveKey(rawValue: Character(character.lowercased())) else { return nil }
        return command(for: key, drivePWM: drivePWM, turnPWM: turnPWM, arcScale: arcScale)
    }

    public static func command(
        for key: DriveKey,
        drivePWM: Int,
        turnPWM: Int,
        arcScale: Double
    ) -> WheelCommand {
        let drive = OpenBotBLE.clampPWM(drivePWM)
        let turn = OpenBotBLE.clampPWM(turnPWM)
        let arcInner = OpenBotBLE.clampPWM(Int((Double(drive) * arcScale).rounded()))

        switch key {
        case .forward: return WheelCommand(left: drive, right: drive, label: "前进")
        case .reverse: return WheelCommand(left: -drive, right: -drive, label: "后退")
        case .turnLeft: return WheelCommand(left: -turn, right: turn, label: "左转")
        case .turnRight: return WheelCommand(left: turn, right: -turn, label: "右转")
        case .arcLeft: return WheelCommand(left: arcInner, right: drive, label: "左弧线")
        case .arcRight: return WheelCommand(left: drive, right: arcInner, label: "右弧线")
        case .stop, .space: return .stop
        }
    }
}
