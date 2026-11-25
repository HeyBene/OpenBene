import Foundation

/// Wire-level contract shared with `zenoh_android` and the PC receiver.
///
/// Keys follow the Android prototype exactly so one PC tool can serve both
/// phones:
///
///     openbene/{robot_id}/cmd        PC  -> phone  JSON control command
///     openbene/{robot_id}/status     phone -> PC   JSON presence
///     openbene/{robot_id}/sensors    phone -> PC   JSON phone sensors
///     openbene/{robot_id}/telemetry  phone -> PC   JSON chassis telemetry
///     openbene/{robot_id}/video      phone -> PC   ZFRM binary JPEG frame
///     openbene/{robot_id}/frame      phone -> PC   ZPKD multi-plane capture
///     openbene/{robot_id}/session    phone -> PC   JSON recording boundary
public enum OpenBeneProtocol {
    public static let version: UInt16 = 1
    public static let namespace = "openbene"

    public enum Topic: String, CaseIterable, Sendable {
        case command = "cmd"
        case status
        case sensors
        case telemetry
        case video
        case frame
        case session
    }

    private static let robotIDPattern = try! NSRegularExpression(
        pattern: "[^A-Za-z0-9_-]+"
    )
    private static let endpointPattern = try! NSRegularExpression(
        pattern: "^(tcp|udp|quic|tls|ws|wss)(://|/).+"
    )

    /// Replaces anything outside `[A-Za-z0-9_-]` with `_`, mirroring the
    /// Android `Protocol.sanitizeRobotId` implementation.
    public static func sanitizeRobotID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        let cleaned = robotIDPattern.stringByReplacingMatches(
            in: trimmed, range: range, withTemplate: "_"
        )
        return cleaned.isEmpty ? "robot" : cleaned
    }

    public static func keyPrefix(robotID: String) -> String {
        "\(namespace)/\(sanitizeRobotID(robotID))"
    }

    public static func key(_ topic: Topic, robotID: String) -> String {
        "\(keyPrefix(robotID: robotID))/\(topic.rawValue)"
    }

    /// Accepts `tcp/192.168.1.10:7447`, `192.168.1.10:7447`, or a full
    /// endpoint such as `udp/...`. Returns `nil` for an empty value.
    public static func normalizeEndpoint(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        if endpointPattern.firstMatch(in: value, range: range) != nil {
            return value
        }
        return "tcp/\(value)"
    }

    /// Splits `openbene/rtr520/video` into `("rtr520", .video)`.
    public static func parseKey(_ key: String) -> (robotID: String, topic: Topic)? {
        let parts = key.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[0] == Substring(namespace), let topic = Topic(rawValue: String(parts[2])) else {
            return nil
        }
        return (String(parts[1]), topic)
    }
}

public enum ZenohSessionMode: String, CaseIterable, Sendable {
    case client
    case peer
}

public struct ZenohTransportConfig: Equatable, Sendable {
    public var robotID: String
    /// Normalized endpoint, e.g. `tcp/192.168.1.20:7447`.
    public var endpoint: String
    public var mode: ZenohSessionMode
    /// Also publish JPEG-only `ZFRM` frames on `.../video` so Android-era
    /// receivers keep working. Full capture frames always go to `.../frame`.
    public var publishLegacyVideo: Bool
    public var statusInterval: TimeInterval
    public var maxQueuedFrames: Int
    public var sessionID: String

    public init(
        robotID: String,
        endpoint: String,
        mode: ZenohSessionMode = .client,
        publishLegacyVideo: Bool = false,
        statusInterval: TimeInterval = 2,
        maxQueuedFrames: Int = 4,
        sessionID: String = UUID().uuidString.lowercased()
    ) {
        self.robotID = OpenBeneProtocol.sanitizeRobotID(robotID)
        self.endpoint = OpenBeneProtocol.normalizeEndpoint(endpoint) ?? "tcp/127.0.0.1:7447"
        self.mode = mode
        self.publishLegacyVideo = publishLegacyVideo
        self.statusInterval = statusInterval
        self.maxQueuedFrames = max(1, maxQueuedFrames)
        self.sessionID = sessionID
    }

    public var statusKey: String { OpenBeneProtocol.key(.status, robotID: robotID) }
    public var frameKey: String { OpenBeneProtocol.key(.frame, robotID: robotID) }
    public var videoKey: String { OpenBeneProtocol.key(.video, robotID: robotID) }
    public var commandKey: String { OpenBeneProtocol.key(.command, robotID: robotID) }
    public var sensorKey: String { OpenBeneProtocol.key(.sensors, robotID: robotID) }
    public var telemetryKey: String { OpenBeneProtocol.key(.telemetry, robotID: robotID) }
    public var sessionKey: String { OpenBeneProtocol.key(.session, robotID: robotID) }
}

public enum ZenohTransportError: Error, Equatable, LocalizedError {
    case invalidEndpoint(String)
    case sessionUnavailable(String)
    case publishFailed(code: Int32)
    case subscribeFailed(code: Int32)
    case notRunning

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let value):
            return "Invalid Zenoh endpoint: \(value)"
        case .sessionUnavailable(let reason):
            return "Zenoh session unavailable: \(reason)"
        case .publishFailed(let code):
            return "Zenoh publish failed with code \(code)"
        case .subscribeFailed(let code):
            return "Zenoh subscribe failed with code \(code)"
        case .notRunning:
            return "Transport is not running"
        }
    }
}

public struct TransportStats: Equatable, Sendable {
    public var framesQueued: UInt64 = 0
    public var framesSent: UInt64 = 0
    public var framesDropped: UInt64 = 0
    public var bytesSent: UInt64 = 0
    public var publishErrors: UInt64 = 0
    public var commandsReceived: UInt64 = 0

    public init() {}
}

/// Minimal session surface so the publishing pipeline can be exercised with a
/// fake in tests and with zenoh-pico on device.
public protocol ZenohSession: AnyObject {
    var isOpen: Bool { get }
    func open() throws
    func close()
    func put(key: String, payload: Data) throws
    func subscribe(key: String, handler: @escaping (String, Data) -> Void) throws -> ZenohSubscription
}

public protocol ZenohSubscription: AnyObject {
    func cancel()
}

final class Counter {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func increment(by amount: UInt64 = 1) -> UInt64 {
        lock.lock()
        value += amount
        let current = value
        lock.unlock()
        return current
    }

    func add(_ amount: UInt64) {
        _ = increment(by: amount)
    }
}

/// Snapshot of the bounded frame queue.
public struct QueueSnapshot: Equatable, Sendable {
    public var pending: Int
    public var dropped: UInt64

    public init(pending: Int = 0, dropped: UInt64 = 0) {
        self.pending = pending
        self.dropped = dropped
    }
}
