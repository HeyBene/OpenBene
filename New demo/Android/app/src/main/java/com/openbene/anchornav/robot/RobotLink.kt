package com.openbene.anchornav.robot

import com.openbene.anchornav.nav.RobotLink

/** Telemetry pushed by the OpenBot firmware. */
data class Telemetry(
    var sonarCm: Double? = null,
    var bumper: String? = null,
    var rpmLeft: Double = 0.0,
    var rpmRight: Double = 0.0,
    var voltage: Double? = null,
    var features: String? = null,
    var updatedAtS: Double = 0.0,
    var connected: Boolean = false,
    var sourceName: String = "mock",
)

/**
 * Bench link: the demo runs without a robot. The executor commands are recorded
 * so the UI can show them, and the pose comes from ARCore alone.
 */
class MockRobotLink : RobotLink {
    override val telemetry = Telemetry(sourceName = "mock (no robot)")
    var lastLeft: Double = 0.0
        private set
    var lastRight: Double = 0.0
        private set

    override fun drive(left: Double, right: Double) {
        lastLeft = left.coerceIn(-1.0, 1.0)
        lastRight = right.coerceIn(-1.0, 1.0)
    }

    override fun stop() {
        lastLeft = 0.0
        lastRight = 0.0
    }

    override fun close() = stop()
}
