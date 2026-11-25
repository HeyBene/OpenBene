import Foundation

/// Control commands sent by the PC to the phone, wire compatible with the
/// Android `zenoh_android` prototype.
public enum RobotCommand: Equatable, Sendable {
    case drive(left: Double, right: Double, sequence: Int64, sentAtMs: Int64, ttlMs: Int64)
    case stop(sequence: Int64, sentAtMs: Int64)
    case unknown(reason: String)

    public var sequence: Int64 {
        switch self {
        case .drive(_, _, let sequence, _, _): return sequence
        case .stop(let sequence, _): return sequence
        case .unknown: return -1
        }
    }

    /// Parses `{"version":1,"cmd":"drive","val":[l,r],"seq":1,...}`.
    public static func parse(_ data: Data) -> RobotCommand {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .unknown(reason: "invalid json")
        }
        let sequence = (object["seq"] as? NSNumber)?.int64Value ?? -1
        switch object["cmd"] as? String {
        case "drive":
            guard let values = object["val"] as? [Any], values.count >= 2,
                  let left = (values[0] as? NSNumber)?.doubleValue,
                  let right = (values[1] as? NSNumber)?.doubleValue else {
                return .unknown(reason: "drive command is missing val[2]")
            }
            return .drive(
                left: min(max(left, -1), 1),
                right: min(max(right, -1), 1),
                sequence: sequence,
                sentAtMs: (object["sent_at"] as? NSNumber)?.int64Value ?? 0,
                ttlMs: (object["ttl_ms"] as? NSNumber)?.int64Value ?? 0
            )
        case "stop":
            return .stop(
                sequence: sequence,
                sentAtMs: (object["sent_at"] as? NSNumber)?.int64Value ?? 0
            )
        case let other?:
            return .unknown(reason: "unsupported cmd: \(other)")
        case nil:
            return .unknown(reason: "missing cmd")
        }
    }

    public static func driveJSONData(
        left: Double,
        right: Double,
        sequence: Int64,
        nowMs: Int64,
        ttlMs: Int64 = 250
    ) -> Data {
        encode([
            "version": Int(OpenBeneProtocol.version),
            "cmd": "drive",
            "val": [min(max(left, -1), 1), min(max(right, -1), 1)],
            "seq": sequence,
            "sent_at": nowMs,
            "ttl_ms": ttlMs,
        ])
    }

    static func encode(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
    }
}

public struct StatusMessage: Equatable, Sendable {
    public var robotID: String
    public var connected: Bool
    public var timestampMs: Int64

    public init(robotID: String, connected: Bool, timestampMs: Int64) {
        self.robotID = OpenBeneProtocol.sanitizeRobotID(robotID)
        self.connected = connected
        self.timestampMs = timestampMs
    }

    public func jsonData() -> Data {
        RobotCommand.encode([
            "version": Int(OpenBeneProtocol.version),
            "robot_id": robotID,
            "connected": connected,
            "state": connected ? "online" : "offline",
            "timestamp": timestampMs,
        ])
    }
}

public struct Vector3Sample: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct SensorSamples: Equatable, Sendable {
    public var accelerometer: Vector3Sample?
    public var gyroscope: Vector3Sample?
    public var batteryLevel: Double?
    public var timestampMs: Int64

    public init(
        accelerometer: Vector3Sample? = nil,
        gyroscope: Vector3Sample? = nil,
        batteryLevel: Double? = nil,
        timestampMs: Int64
    ) {
        self.accelerometer = accelerometer
        self.gyroscope = gyroscope
        self.batteryLevel = batteryLevel
        self.timestampMs = timestampMs
    }

    public func jsonData() -> Data {
        var data: [String: Any] = [:]
        if let accelerometer {
            data["accelerometer"] = ["x": accelerometer.x, "y": accelerometer.y, "z": accelerometer.z]
        }
        if let gyroscope {
            data["gyroscope"] = ["x": gyroscope.x, "y": gyroscope.y, "z": gyroscope.z]
        }
        if let batteryLevel {
            data["battery_level"] = batteryLevel
        }
        return RobotCommand.encode([
            "version": Int(OpenBeneProtocol.version),
            "type": "sensor_data",
            "data": data,
            "timestamp": timestampMs,
        ])
    }
}

public struct TelemetryMessage: Equatable, Sendable {
    public var voltage: Double
    public var leftRPM: Double
    public var rightRPM: Double
    public var sonarCm: Int?
    public var timestampMs: Int64

    public init(
        voltage: Double,
        leftRPM: Double,
        rightRPM: Double,
        sonarCm: Int?,
        timestampMs: Int64
    ) {
        self.voltage = voltage
        self.leftRPM = leftRPM
        self.rightRPM = rightRPM
        self.sonarCm = sonarCm
        self.timestampMs = timestampMs
    }

    public func jsonData() -> Data {
        var object: [String: Any] = [
            "version": Int(OpenBeneProtocol.version),
            "type": "telemetry",
            "voltage": voltage,
            "wheel_rpm": ["left": leftRPM, "right": rightRPM],
            "timestamp": timestampMs,
        ]
        object["sonar_cm"] = sonarCm.map { $0 as Any } ?? NSNull()
        return RobotCommand.encode(object)
    }
}

/// Marks recording boundaries so the PC can name and close a session without
/// guessing from wall-clock time.
public struct SessionEvent: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case start
        case stop
    }

    public var kind: Kind
    public var sessionID: String
    public var robotID: String
    public var timestampMs: Int64

    public init(kind: Kind, sessionID: String, robotID: String, timestampMs: Int64) {
        self.kind = kind
        self.sessionID = sessionID
        self.robotID = OpenBeneProtocol.sanitizeRobotID(robotID)
        self.timestampMs = timestampMs
    }

    public func jsonData() -> Data {
        RobotCommand.encode([
            "version": Int(OpenBeneProtocol.version),
            "event": kind.rawValue,
            "session_id": sessionID,
            "robot_id": robotID,
            "timestamp": timestampMs,
        ])
    }
}
