package com.openbene.arindoornav.robot

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
 * The drive interface the AR screen talks to: one normalised speed per wheel,
 * which the BLE link scales to the 0..255 PWM values of the firmware.
 */
interface RobotLink {
    /** Latest firmware telemetry, mutated in place by the link implementation. */
    val telemetry: Telemetry

    fun drive(left: Double, right: Double)

    fun stop()

    fun close()
}

/**
 * Bench link: the demo runs without a robot. The commands are recorded so the UI
 * can show them, and nothing else changes: the pose still comes from ARCore.
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
