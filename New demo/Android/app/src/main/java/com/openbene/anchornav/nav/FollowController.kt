package com.openbene.anchornav.nav

import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.tan

/**
 * Gains for the follow controller. Box coordinates are fractions of the frame.
 */
data class FollowConfig(
    val targetHeight: Double = 0.55,
    val heightDeadband: Double = 0.15,
    val centreDeadband: Double = 0.10,
    val turnSpeed: Double = 0.22,
    val cruiseSpeed: Double = 0.28,
    val steerGain: Double = 1.6,
    val lostTimeoutS: Double = 1.5,
    val obstacleStopCm: Double = 35.0,
) {
    companion object {
        /**
         * Preset for a detector that reports a face box instead of a whole person
         * box, which is what the Android demo uses. A face is roughly a quarter of
         * the person height, so the target box is smaller and the deadband wider.
         * Tune it on the bench before letting the robot drive.
         */
        val FACE_BOX = FollowConfig(targetHeight = 0.16, heightDeadband = 0.30)
    }
}

data class FollowCommand(val left: Double, val right: Double, val action: String)

/** A detection box in normalised frame coordinates, origin at the top left. */
data class PersonBox(
    val centreX: Double,
    val centreY: Double,
    val width: Double,
    val height: Double,
)

/**
 * Follow mode: keep driving behind a person the camera can see.
 *
 * This is the OpenBot tracking behaviour the waypoint demo keeps alongside the
 * route executor: instead of a map, the phone drives towards whatever the camera
 * reports as a person, keeping the box centred and at a comfortable size.
 *
 * The controller is deliberately small and stateless: the caller feeds it one
 * detection per frame plus the sonar reading, and it returns one wheel command.
 * Distance comes from the box height, which is crude but works with the down
 * tilted camera of the robot.
 *
 * Port of shared/navcore/openbene_nav/follow.py, which is covered by the Python
 * tests; keep the two in step.
 */
object FollowController {

    /** A box older than this counts as no detection at all. */
    const val BOX_TTL_S = 0.6

    fun followCommand(
        box: PersonBox?,
        config: FollowConfig = FollowConfig(),
        sonarCm: Double? = null,
        secondsSinceSeen: Double = 0.0,
    ): FollowCommand {
        if (sonarCm != null && sonarCm <= config.obstacleStopCm) {
            return FollowCommand(0.0, 0.0, String.format(Locale.US, "obstacle at %.0f cm", sonarCm))
        }

        if (box == null) {
            return if (secondsSinceSeen > config.lostTimeoutS) {
                FollowCommand(0.0, 0.0, "target lost")
            } else {
                FollowCommand(0.0, 0.0, "searching for the target")
            }
        }

        val error = box.centreX - 0.5
        if (abs(error) > config.centreDeadband) {
            return if (error > 0) {
                FollowCommand(-config.turnSpeed, config.turnSpeed, "turning right")
            } else {
                FollowCommand(config.turnSpeed, -config.turnSpeed, "turning left")
            }
        }

        val low = config.targetHeight * (1.0 - config.heightDeadband)
        val high = config.targetHeight * (1.0 + config.heightDeadband)
        val forward: Double
        val action: String
        if (box.height < low) {
            forward = config.cruiseSpeed * min(1.0, (low - box.height) / max(low, 1e-6) * 3.0 + 0.4)
            action = "closing in"
        } else if (box.height > high) {
            return FollowCommand(0.0, 0.0, "too close, holding")
        } else {
            forward = 0.0
            action = "holding distance"
        }

        val steer = max(-1.0, min(1.0, config.steerGain * error))
        var left = forward * (1.0 - steer)
        var right = forward * (1.0 + steer)
        val scale = max(max(abs(left), abs(right)), 1e-6)
        if (scale > 1.0) {
            left /= scale
            right /= scale
        }
        return FollowCommand(left, right, action)
    }

    /** Pixel rectangle to the normalised box the controller expects. */
    fun boxFromPixels(
        leftPx: Double,
        topPx: Double,
        rightPx: Double,
        bottomPx: Double,
        frameWidth: Double,
        frameHeight: Double,
    ): PersonBox = PersonBox(
        centreX = 0.5 * (leftPx + rightPx) / max(frameWidth, 1e-6),
        centreY = 0.5 * (topPx + bottomPx) / max(frameHeight, 1e-6),
        width = max(0.0, rightPx - leftPx) / max(frameWidth, 1e-6),
        height = max(0.0, bottomPx - topPx) / max(frameHeight, 1e-6),
    )

    /** Rough distance to a person of [personM] height, for the UI only. */
    fun distanceHintM(
        height: Double,
        cameraHeightM: Double = 0.40,
        fovDeg: Double = 60.0,
        personM: Double = 1.70,
    ): Double {
        if (height <= 1e-3) return Double.POSITIVE_INFINITY
        val focal = 0.5 / tan(Math.toRadians(fovDeg) * 0.5)
        return focal * personM / (height * 2.0 * cameraHeightM)
    }
}
