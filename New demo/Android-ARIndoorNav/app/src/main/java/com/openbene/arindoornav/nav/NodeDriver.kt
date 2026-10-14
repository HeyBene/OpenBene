package com.openbene.arindoornav.nav

import com.openbene.arindoornav.ar.Planar
import java.util.Locale
import kotlin.math.abs

data class DriverConfig(
    val arriveToleranceM: Double = 0.30,
    val headingToleranceDeg: Double = 15.0,
    val cruiseSpeed: Double = 0.30,
    val turnSpeed: Double = 0.22,
    val steerGain: Double = 1.6,
    val obstacleStopCm: Double = 35.0,
    val obstacleClearCm: Double = 50.0,
)

data class DriverCommand(
    val left: Double,
    val right: Double,
    val action: String,
    val blocked: Boolean,
)

/**
 * Drives the OpenBot towards one recorded node at a time. The pose comes from
 * ARCore alone, which is what the original ARIndoorNav had: no wheel feedback, no
 * odometry, no re-localisation and no path correction. Turning is in place first,
 * then a differential speed follows the bearing to the node.
 */
object NodeDriver {

    fun command(
        pose: Planar,
        target: Planar,
        sonarCm: Double?,
        wasBlocked: Boolean,
        config: DriverConfig = DriverConfig(),
    ): DriverCommand {
        val blocked = if (wasBlocked) {
            sonarCm != null && sonarCm <= config.obstacleClearCm
        } else {
            sonarCm != null && sonarCm <= config.obstacleStopCm
        }
        if (blocked) {
            return DriverCommand(
                left = 0.0,
                right = 0.0,
                action = String.format(Locale.US, "obstacle at %.0f cm, holding", sonarCm ?: 0.0),
                blocked = true,
            )
        }

        val distance = pose.distanceTo(target)
        val error = pose.headingErrorTo(target)
        if (abs(error) > Math.toRadians(config.headingToleranceDeg)) {
            return if (error > 0) {
                DriverCommand(-config.turnSpeed, config.turnSpeed, "turning left", false)
            } else {
                DriverCommand(config.turnSpeed, -config.turnSpeed, "turning right", false)
            }
        }

        val steer = (config.steerGain * error).coerceIn(-1.0, 1.0)
        var left = config.cruiseSpeed * (1.0 - steer)
        var right = config.cruiseSpeed * (1.0 + steer)
        val scale = maxOf(abs(left), abs(right), 1e-6)
        if (scale > 1.0) {
            left /= scale
            right /= scale
        }
        return DriverCommand(
            left = left,
            right = right,
            action = String.format(Locale.US, "driving to node, %.1f m", distance),
            blocked = false,
        )
    }
}
