import Foundation

/// Telemetry pushed by the OpenBot firmware.
public final class Telemetry {
    public var sonarCm: Double?
    public var bumper: String?
    public var rpmLeft: Double = 0.0
    public var rpmRight: Double = 0.0
    public var voltage: Double?
    public var features: String?
    public var updatedAtS: Double = 0.0
    public var connected: Bool = false
    public var sourceName: String = "mock"

    public init(sourceName: String = "mock") {
        self.sourceName = sourceName
    }
}

/// The drive interface the route executor talks to. Speeds are normalised to
/// -1...1 per wheel; the BLE link scales them to the 0..255 PWM of the firmware.
public protocol RobotLink: AnyObject {
    var telemetry: Telemetry { get }
    func drive(left: Double, right: Double)
    func stop()
    func close()
}

/// Bench link: the demo runs without a robot. Commands are recorded so the UI can
/// show them, and the pose comes from ARKit alone.
public final class MockRobotLink: RobotLink {
    public let telemetry = Telemetry(sourceName: "mock (no robot)")
    public private(set) var lastLeft: Double = 0.0
    public private(set) var lastRight: Double = 0.0
    public private(set) var commandCount = 0

    public init() {}

    public func drive(left: Double, right: Double) {
        lastLeft = min(1.0, max(-1.0, left))
        lastRight = min(1.0, max(-1.0, right))
        commandCount += 1
    }

    public func stop() {
        lastLeft = 0.0
        lastRight = 0.0
    }

    public func close() {
        stop()
    }
}

/// A wheel robot that moves exactly like the executor expects, used by the unit
/// tests and by the desk demo: the commands drive a virtual OpenBot, the
/// telemetry feeds the same odometry the firmware would.
public final class SimulatedRobotLink: RobotLink {
    public let telemetry = Telemetry(sourceName: "simulated robot")
    public var pose: Pose2D
    public var wheelSlip: Double = 0.0
    public var obstacleX: Double? = nil
    public var obstacleMarginM: Double = 0.34

    private let wheelBaseM: Double
    private let wheelRadiusM: Double
    private var left = 0.0
    private var right = 0.0

    public init(pose: Pose2D, wheelBaseM: Double = 0.30, wheelRadiusM: Double = 0.0325) {
        self.pose = pose
        self.wheelBaseM = wheelBaseM
        self.wheelRadiusM = wheelRadiusM
        telemetry.connected = true
    }

    public func drive(left: Double, right: Double) {
        self.left = left
        self.right = right
    }

    public func stop() {
        left = 0.0
        right = 0.0
    }

    public func close() {}

    /// Advance the virtual robot and publish telemetry for the estimator.
    public func tick(dtS: Double) {
        let circumference = 2.0 * Double.pi * wheelRadiusM
        let vLeft = left * OpenBotProtocol.simulatedTopSpeedMps
        let vRight = right * OpenBotProtocol.simulatedTopSpeedMps
        let linear = 0.5 * (vLeft + vRight)
        let angular = (vRight - vLeft) / wheelBaseM

        let moved = pose.translated(forwardM: linear * dtS)
        pose = Pose2D(x: moved.x, y: moved.y, yawRad: wrapRad(pose.yawRad + angular * dtS))

        let slip = 1.0 + wheelSlip
        telemetry.rpmLeft = vLeft * slip / circumference * 60.0
        telemetry.rpmRight = vRight * slip / circumference * 60.0
        telemetry.connected = true
        telemetry.updatedAtS += dtS

        if let wall = obstacleX {
            let distance = (wall - pose.x) * 100.0
            telemetry.sonarCm = max(2.0, distance)
            if distance <= obstacleMarginM * 100.0 {
                pose = Pose2D(x: min(pose.x, wall - obstacleMarginM), y: pose.y, yawRad: pose.yawRad)
            }
        } else {
            telemetry.sonarCm = 400.0
        }
    }

    /// Where the robot really is, for test assertions.
    public var truePose: Pose2D { pose }
}
