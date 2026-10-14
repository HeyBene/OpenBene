package com.openbene.arindoornav.robot

/**
 * OpenBot firmware wire format: one ASCII header plus payload, newline
 * terminated. Mirrors openbene_nav.robot_link.OpenBotProtocol and the ESP32
 * firmware in the OpenBot repository.
 */
object OpenBotProtocol {
    const val SERVICE_UUID: String = "61653dc3-4021-4d1e-ba83-8b4eec61d613"
    const val CHAR_RX_UUID: String = "06386c14-86ea-4d71-811c-48f97c58f8c9"
    const val CHAR_TX_UUID: String = "9bf1103b-834c-47cf-b149-c9e4bcf778a7"
    const val MAX_PWM: Int = 255

    fun clampSpeed(speed: Double): Double = speed.coerceIn(-1.0, 1.0)

    fun speedToPwm(speed: Double): Int = Math.round(clampSpeed(speed) * MAX_PWM).toInt()

    fun ctrlCmd(left: Double, right: Double): ByteArray {
        val payload = "c" + speedToPwm(left) + "," + speedToPwm(right) + "\n"
        return payload.toByteArray(Charsets.US_ASCII)
    }

    fun heartbeatCmd(intervalMs: Int): ByteArray =
        ("h" + intervalMs + "\n").toByteArray(Charsets.US_ASCII)

    fun featureCmd(): ByteArray = "f\n".toByteArray(Charsets.US_ASCII)

    fun sensorStreamCmd(header: Char, intervalMs: Int): ByteArray {
        require(header.isLetter()) { "header must be a single ASCII letter" }
        return (header + intervalMs.toString() + "\n").toByteArray(Charsets.US_ASCII)
    }

    /** Parse one firmware line into the matching telemetry field. */
    fun applyLine(telemetry: Telemetry, line: String, nowS: Double) {
        val text = line.trim()
        if (text.isEmpty()) return
        val body = text.substring(1)
        when (text[0]) {
            'v' -> body.toDoubleOrNull()?.let { telemetry.voltage = it }
            'w' -> {
                val parts = body.split(",")
                if (parts.size >= 2) {
                    parts[0].trim().toDoubleOrNull()?.let { telemetry.rpmLeft = it }
                    parts[1].trim().toDoubleOrNull()?.let { telemetry.rpmRight = it }
                }
            }
            's' -> body.toDoubleOrNull()?.let { telemetry.sonarCm = it }
            'b' -> telemetry.bumper = body.trim()
            'f' -> telemetry.features = body.trim()
        }
        telemetry.updatedAtS = nowS
    }

    fun rpmToSpeedMps(rpm: Double, wheelRadiusM: Double): Double =
        rpm / 60.0 * 2.0 * Math.PI * wheelRadiusM
}
