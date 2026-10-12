import Foundation

/// Gains for the follow controller. Box coordinates are fractions of the frame.
public struct FollowConfig: Equatable {
    public var targetHeight: Double
    public var heightDeadband: Double
    public var centreDeadband: Double
    public var turnSpeed: Double
    public var cruiseSpeed: Double
    public var steerGain: Double
    public var lostTimeoutS: Double
    public var obstacleStopCm: Double

    public init(
        targetHeight: Double = 0.55,
        heightDeadband: Double = 0.15,
        centreDeadband: Double = 0.10,
        turnSpeed: Double = 0.22,
        cruiseSpeed: Double = 0.28,
        steerGain: Double = 1.6,
        lostTimeoutS: Double = 1.5,
        obstacleStopCm: Double = 35.0
    ) {
        self.targetHeight = targetHeight
        self.heightDeadband = heightDeadband
        self.centreDeadband = centreDeadband
        self.turnSpeed = turnSpeed
        self.cruiseSpeed = cruiseSpeed
        self.steerGain = steerGain
        self.lostTimeoutS = lostTimeoutS
        self.obstacleStopCm = obstacleStopCm
    }

    /// Preset for a detector that reports a face box instead of a whole person
    /// box, as the Android demo does. A face is roughly a quarter of the person
    /// height, so the target box is smaller and the deadband wider. Tune it on
    /// the bench before letting the robot drive.
    public static let faceBox = FollowConfig(targetHeight: 0.16, heightDeadband: 0.30)
}

public struct FollowCommand: Equatable {
    public let left: Double
    public let right: Double
    public let action: String

    public init(left: Double, right: Double, action: String) {
        self.left = left
        self.right = right
        self.action = action
    }
}

/// A detection box in normalised frame coordinates, origin at the top left.
public struct PersonBox: Equatable {
    public let centreX: Double
    public let centreY: Double
    public let width: Double
    public let height: Double

    public init(centreX: Double, centreY: Double, width: Double, height: Double) {
        self.centreX = centreX
        self.centreY = centreY
        self.width = width
        self.height = height
    }
}

/// Follow mode: keep driving behind a person the camera can see.
///
/// This is the OpenBot tracking behaviour the waypoint demo keeps alongside the
/// route executor: instead of a map, the phone drives towards whatever the
/// camera reports as a person, keeping the box centred and at a comfortable
/// size.
///
/// The controller is deliberately small and stateless: the caller feeds it one
/// detection per frame plus the sonar reading, and it returns one wheel command.
/// Distance comes from the box height, which is crude but works with the down
/// tilted camera of the robot.
///
/// Port of shared/navcore/openbene_nav/follow.py, which is covered by the Python
/// tests; keep the two in step.
public enum FollowController {

    /// A box older than this counts as no detection at all.
    public static let boxTtlS = 0.6

    public static func followCommand(
        box: PersonBox?,
        config: FollowConfig = FollowConfig(),
        sonarCm: Double? = nil,
        secondsSinceSeen: Double = 0.0
    ) -> FollowCommand {
        if let sonarCm = sonarCm, sonarCm <= config.obstacleStopCm {
            return FollowCommand(left: 0.0, right: 0.0, action: String(format: "obstacle at %.0f cm", sonarCm))
        }

        guard let box = box else {
            return secondsSinceSeen > config.lostTimeoutS
                ? FollowCommand(left: 0.0, right: 0.0, action: "target lost")
                : FollowCommand(left: 0.0, right: 0.0, action: "searching for the target")
        }

        let error = box.centreX - 0.5
        if abs(error) > config.centreDeadband {
            return error > 0
                ? FollowCommand(left: -config.turnSpeed, right: config.turnSpeed, action: "turning right")
                : FollowCommand(left: config.turnSpeed, right: -config.turnSpeed, action: "turning left")
        }

        let low = config.targetHeight * (1.0 - config.heightDeadband)
        let high = config.targetHeight * (1.0 + config.heightDeadband)
        let forward: Double
        let action: String
        if box.height < low {
            forward = config.cruiseSpeed * min(1.0, (low - box.height) / max(low, 1e-6) * 3.0 + 0.4)
            action = "closing in"
        } else if box.height > high {
            return FollowCommand(left: 0.0, right: 0.0, action: "too close, holding")
        } else {
            forward = 0.0
            action = "holding distance"
        }

        let steer = min(1.0, max(-1.0, config.steerGain * error))
        var left = forward * (1.0 - steer)
        var right = forward * (1.0 + steer)
        let scale = max(max(abs(left), abs(right)), 1e-6)
        if scale > 1.0 {
            left /= scale
            right /= scale
        }
        return FollowCommand(left: left, right: right, action: action)
    }

    /// Pixel rectangle to the normalised box the controller expects.
    public static func boxFromPixels(
        leftPx: Double,
        topPx: Double,
        rightPx: Double,
        bottomPx: Double,
        frameWidth: Double,
        frameHeight: Double
    ) -> PersonBox {
        PersonBox(
            centreX: 0.5 * (leftPx + rightPx) / max(frameWidth, 1e-6),
            centreY: 0.5 * (topPx + bottomPx) / max(frameHeight, 1e-6),
            width: max(0.0, rightPx - leftPx) / max(frameWidth, 1e-6),
            height: max(0.0, bottomPx - topPx) / max(frameHeight, 1e-6)
        )
    }

    /// Rough distance to a person of personM height, for the UI only.
    public static func distanceHintM(
        height: Double,
        cameraHeightM: Double = 0.40,
        fovDeg: Double = 60.0,
        personM: Double = 1.70
    ) -> Double {
        if height <= 1e-3 { return Double.infinity }
        let focal = 0.5 / tan(fovDeg * Double.pi / 180.0 * 0.5)
        return focal * personM / (height * 2.0 * cameraHeightM)
    }
}
