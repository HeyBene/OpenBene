package com.openbene.anchornav.nav

import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/**
 * A planar pose in the demo map frame: x points east, y points north and yaw is
 * measured counter-clockwise from +x. Mirrors openbene_nav.model.Pose2D.
 */
data class Pose2D(val x: Double, val y: Double, val yawRad: Double) {

    val yawDeg: Double get() = Math.toDegrees(yawRad)

    fun compose(other: Pose2D): Pose2D {
        val cosY = cos(yawRad)
        val sinY = sin(yawRad)
        return Pose2D(
            x + cosY * other.x - sinY * other.y,
            y + sinY * other.x + cosY * other.y,
            wrapRad(yawRad + other.yawRad),
        )
    }

    fun inverse(): Pose2D {
        val cosY = cos(yawRad)
        val sinY = sin(yawRad)
        return Pose2D(
            -cosY * x - sinY * y,
            sinY * x - cosY * y,
            wrapRad(-yawRad),
        )
    }

    fun translated(forwardM: Double, leftM: Double = 0.0): Pose2D {
        val cosY = cos(yawRad)
        val sinY = sin(yawRad)
        return Pose2D(
            x + cosY * forwardM - sinY * leftM,
            y + sinY * forwardM + cosY * leftM,
            yawRad,
        )
    }

    fun distanceTo(other: Pose2D): Double = hypot(other.x - x, other.y - y)

    fun bearingTo(other: Pose2D): Double = atan2(other.y - y, other.x - x)

    fun headingErrorTo(other: Pose2D): Double = wrapRad(bearingTo(other) - yawRad)

    companion object {
        fun fromDeg(x: Double, y: Double, yawDeg: Double): Pose2D =
            Pose2D(x, y, Math.toRadians(yawDeg))

        fun wrapRad(angleRad: Double): Double {
            var wrapped = (angleRad + Math.PI) % (2.0 * Math.PI)
            if (wrapped <= 0.0) wrapped += 2.0 * Math.PI
            return wrapped - Math.PI
        }

        fun wrapDeg(angleDeg: Double): Double {
            var wrapped = (angleDeg + 180.0) % 360.0
            if (wrapped <= 0.0) wrapped += 360.0
            return wrapped - 180.0
        }
    }
}
