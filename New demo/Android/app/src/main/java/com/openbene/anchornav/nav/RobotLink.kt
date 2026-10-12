package com.openbene.anchornav.nav

import com.openbene.anchornav.robot.Telemetry

/**
 * The drive interface the route executor talks to.
 *
 * Implementations live in [com.openbene.anchornav.robot]:
 *
 * * [com.openbene.anchornav.robot.MockRobotLink] records the commands for the
 *   on-screen demo and keeps the pose coming from ARCore alone;
 * * [com.openbene.anchornav.robot.OpenBotBleLink] writes the OpenBot firmware
 *   control frame over Bluetooth LE and parses the telemetry stream.
 *
 * Speeds are normalised to [-1, 1] for each wheel, which the BLE link scales to
 * the 0..255 PWM values of the firmware.
 */
interface RobotLink {
    /** Latest firmware telemetry, mutated in place by the link implementation. */
    val telemetry: Telemetry

    fun drive(left: Double, right: Double)

    fun stop()

    fun close()
}
