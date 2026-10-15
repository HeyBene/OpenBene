import Foundation

/// Wrap an angle in degrees into (-180, 180].
public func wrapDeg(_ angleDeg: Double) -> Double {
    var wrapped = angleDeg.truncatingRemainder(dividingBy: 360.0)
    if wrapped <= -180.0 { wrapped += 360.0 }
    if wrapped > 180.0 { wrapped -= 360.0 }
    return wrapped
}

/// Wrap an angle in radians into (-pi, pi].
public func wrapRad(_ angleRad: Double) -> Double {
    let twoPi = 2.0 * Double.pi
    var wrapped = angleRad.truncatingRemainder(dividingBy: twoPi)
    if wrapped <= -Double.pi { wrapped += twoPi }
    if wrapped > Double.pi { wrapped -= twoPi }
    return wrapped
}

/// A planar pose in the demo map frame: x points east, y points north and yaw is
/// measured counter-clockwise from +x. Mirrors openbene_nav.model.Pose2D.
public struct Pose2D: Equatable, Codable {
    public var x: Double
    public var y: Double
    public var yawRad: Double

    public init(x: Double, y: Double, yawRad: Double = 0.0) {
        self.x = x
        self.y = y
        self.yawRad = yawRad
    }

    public static func fromDeg(x: Double, y: Double, yawDeg: Double = 0.0) -> Pose2D {
        Pose2D(x: x, y: y, yawRad: yawDeg * Double.pi / 180.0)
    }

    public var yawDeg: Double { yawRad * 180.0 / Double.pi }

    /// Compose with another pose, which is expressed in this pose's frame.
    public func compose(_ other: Pose2D) -> Pose2D {
        let cosY = cos(yawRad)
        let sinY = sin(yawRad)
        return Pose2D(
            x: x + cosY * other.x - sinY * other.y,
            y: y + sinY * other.x + cosY * other.y,
            yawRad: wrapRad(yawRad + other.yawRad)
        )
    }

    public func inverse() -> Pose2D {
        let cosY = cos(yawRad)
        let sinY = sin(yawRad)
        return Pose2D(
            x: -cosY * x - sinY * y,
            y: sinY * x - cosY * y,
            yawRad: wrapRad(-yawRad)
        )
    }

    public func translated(forwardM: Double, leftM: Double = 0.0) -> Pose2D {
        let cosY = cos(yawRad)
        let sinY = sin(yawRad)
        return Pose2D(
            x: x + cosY * forwardM - sinY * leftM,
            y: y + sinY * forwardM + cosY * leftM,
            yawRad: yawRad
        )
    }

    public func distanceTo(_ other: Pose2D) -> Double {
        hypot(other.x - x, other.y - y)
    }

    public func bearingTo(_ other: Pose2D) -> Double {
        atan2(other.y - y, other.x - x)
    }

    /// Signed angle the robot has to turn to face another pose.
    public func headingErrorTo(_ other: Pose2D) -> Double {
        wrapRad(bearingTo(other) - yawRad)
    }
}

/// Interpolate a pose, used by the simulator in the tests.
public func lerp(_ first: Pose2D, _ second: Pose2D, _ t: Double) -> Pose2D {
    Pose2D(
        x: first.x + (second.x - first.x) * t,
        y: first.y + (second.y - first.y) * t,
        yawRad: wrapRad(first.yawRad + wrapRad(second.yawRad - first.yawRad) * t)
    )
}
