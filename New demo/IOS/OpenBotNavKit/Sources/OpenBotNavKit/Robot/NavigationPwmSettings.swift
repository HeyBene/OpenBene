import Foundation

public struct NavigationPwmSettings: Codable, Equatable {
    public var drivePwm: Int
    public var leftTurnPwm: Int
    public var rightTurnPwm: Int
    public static let defaults = NavigationPwmSettings()

    public init(drivePwm: Int = 160, leftTurnPwm: Int = 160, rightTurnPwm: Int = 160) {
        self.drivePwm = min(255, max(0, drivePwm))
        self.leftTurnPwm = min(255, max(0, leftTurnPwm))
        self.rightTurnPwm = min(255, max(0, rightTurnPwm))
    }

    private enum CodingKeys: String, CodingKey {
        case drivePwm, leftTurnPwm, rightTurnPwm, turnPwm
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        drivePwm = try values.decode(Int.self, forKey: .drivePwm)
        if values.contains(.leftTurnPwm) || values.contains(.rightTurnPwm) {
            leftTurnPwm = try values.decode(Int.self, forKey: .leftTurnPwm)
            rightTurnPwm = try values.decode(Int.self, forKey: .rightTurnPwm)
        } else {
            // Preserve the user's previous setting when upgrading from the
            // single turning-PWM version, rather than reverting to 160.
            let previous = try values.decode(Int.self, forKey: .turnPwm)
            leftTurnPwm = previous
            rightTurnPwm = previous
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(drivePwm, forKey: .drivePwm)
        try values.encode(leftTurnPwm, forKey: .leftTurnPwm)
        try values.encode(rightTurnPwm, forKey: .rightTurnPwm)
    }

    public var valid: Bool {
        (0...255).contains(drivePwm) && (0...255).contains(leftTurnPwm) && (0...255).contains(rightTurnPwm)
    }

    public func followConfig(targetHeight: Double = 0.40) -> FollowConfig {
        FollowConfig(targetHeight: targetHeight, cruiseSpeed: Double(drivePwm) / 255,
            leftTurnSpeed: Double(leftTurnPwm) / 255, rightTurnSpeed: Double(rightTurnPwm) / 255,
            minimumCruiseFraction: 1)
    }

    public func waypointConfig(sonarInstalled: Bool = false) -> WaypointConfig {
        var config = WaypointConfig()
        config.cruiseSpeed = Double(min(255, max(0, drivePwm))) / 255
        config.leftTurnSpeed = Double(min(255, max(0, leftTurnPwm))) / 255
        config.rightTurnSpeed = Double(min(255, max(0, rightTurnPwm))) / 255
        config.sonarInstalled = sonarInstalled
        return config
    }
}

/// A device-local setting, independent of recorded map files and BLE identity.
public final class NavigationPwmStore {
    private let defaults: UserDefaults
    private let key = "navigation.pwm.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> NavigationPwmSettings {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(NavigationPwmSettings.self, from: data), value.valid
        else { return .defaults }
        return value
    }

    public func save(_ value: NavigationPwmSettings) throws {
        guard value.valid else { throw RecordingError.invalid("PWM 必须在 0～255 之间。") }
        defaults.set(try JSONEncoder().encode(value), forKey: key)
    }
}
