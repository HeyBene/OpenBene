import Foundation

/// OpenBot firmware wire format: one ASCII header plus payload, newline
/// terminated. Mirrors openbene_nav.robot_link.OpenBotProtocol and
/// openbene_sdk/src/openbene/esp32_ble.py.
public enum OpenBotProtocol {
    public static let serviceUuid = "61653dc3-4021-4d1e-ba83-8b4eec61d613"
    public static let charRxUuid = "06386c14-86ea-4d71-811c-48f97c58f8c9"
    public static let charTxUuid = "9bf1103b-834c-47cf-b149-c9e4bcf778a7"
    public static let maxPwm = 255

    /// Wheel speed at command 1.0 for the simulated robot; the real robot's top
    /// speed depends on the firmware and battery.
    public static let simulatedTopSpeedMps = 0.75

    public static func clampSpeed(_ speed: Double) -> Double {
        min(1.0, max(-1.0, speed))
    }

    public static func speedToPwm(_ speed: Double) -> Int {
        Int((clampSpeed(speed) * Double(maxPwm)).rounded())
    }

    public static func ctrlCommand(left: Double, right: Double) -> Data {
        Data("c\(speedToPwm(left)),\(speedToPwm(right))\n".utf8)
    }

    public static func heartbeatCommand(intervalMs: Int) -> Data {
        Data("h\(intervalMs)\n".utf8)
    }

    public static func featureCommand() -> Data {
        Data("f\n".utf8)
    }

    public static func sensorStreamCommand(header: String, intervalMs: Int) -> Data {
        Data("\(header)\(intervalMs)\n".utf8)
    }

    /// Matches openbene_sdk's is_openbot_device_name.
    public static func isOpenBotName(_ name: String?) -> Bool {
        guard let name = name else { return false }
        let lowered = name.lowercased()
        return lowered.contains("openbot") || lowered.contains("rtr_520") || lowered.contains("rtr 520")
    }

    public enum Message: Equatable {
        case voltage(Double)
        case wheel(rpmLeft: Double, rpmRight: Double)
        case sonar(distanceCm: Double)
        case bumper(collisionId: String)
        case features(String)
        case unknown(String)
    }

    public static func parse(_ raw: String) -> Message? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let header = line.first else { return nil }
        let body = String(line.dropFirst())

        switch header {
        case "v":
            guard let value = Double(body) else { return .unknown(line) }
            return .voltage(value)
        case "w":
            let parts = body.split(separator: ",")
            guard parts.count >= 2,
                  let left = Double(parts[0].trimmingCharacters(in: .whitespaces)),
                  let right = Double(parts[1].trimmingCharacters(in: .whitespaces))
            else { return .unknown(line) }
            return .wheel(rpmLeft: left, rpmRight: right)
        case "s":
            guard let value = Double(body) else { return .unknown(line) }
            return .sonar(distanceCm: value)
        case "b":
            return .bumper(collisionId: body)
        case "f":
            return .features(body)
        default:
            return .unknown(line)
        }
    }

    /// Parse one firmware line straight into the telemetry object.
    @discardableResult
    public static func apply(_ raw: String, to telemetry: Telemetry, nowS: Double) -> Message? {
        guard let message = parse(raw) else { return nil }
        switch message {
        case .voltage(let value): telemetry.voltage = value
        case .wheel(let left, let right):
            telemetry.rpmLeft = left
            telemetry.rpmRight = right
        case .sonar(let distance): telemetry.sonarCm = distance
        case .bumper(let collisionId): telemetry.bumper = collisionId
        case .features(let text): telemetry.features = text
        case .unknown: break
        }
        telemetry.updatedAtS = nowS
        return message
    }

    public static func rpmToSpeedMps(_ rpm: Double, wheelRadiusM: Double) -> Double {
        rpm / 60.0 * 2.0 * Double.pi * wheelRadiusM
    }
}
