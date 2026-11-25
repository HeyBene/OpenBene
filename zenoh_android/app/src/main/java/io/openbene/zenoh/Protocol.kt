package io.openbene.zenoh

import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder

sealed interface RobotCommand {
    val sequence: Long

    data class Drive(
        val left: Double,
        val right: Double,
        override val sequence: Long,
        val sentAtMs: Long,
        val ttlMs: Long,
    ) : RobotCommand

    data class Stop(
        override val sequence: Long,
        val sentAtMs: Long,
    ) : RobotCommand

    data class Unknown(val reason: String) : RobotCommand {
        override val sequence: Long = -1
    }
}

object Protocol {
    const val VERSION = 1
    // Little-endian encoding of this value produces the ASCII bytes "ZFRM".
    const val VIDEO_MAGIC = 0x4D52465A
    const val VIDEO_HEADER_BYTES = 20

    private val robotIdPattern = Regex("[^A-Za-z0-9_-]+")
    private val supportedEndpointPrefix = Regex("^(tcp|udp|quic|tls|ws)(://|/).+")

    fun sanitizeRobotId(raw: String): String {
        val cleaned = robotIdPattern.replace(raw.trim(), "_")
        return cleaned.ifBlank { "robot" }
    }

    fun normalizeEndpoint(raw: String): String? {
        val value = raw.trim()
        if (value.isEmpty()) return null
        if (supportedEndpointPrefix.matches(value)) return value
        return "tcp/$value"
    }

    fun keyPrefix(robotId: String): String = "openbene/${sanitizeRobotId(robotId)}"

    fun encodeDrive(
        left: Double,
        right: Double,
        sequence: Long,
        nowMs: Long = System.currentTimeMillis(),
        ttlMs: Long = 250,
    ): String = JSONObject()
        .put("version", VERSION)
        .put("cmd", "drive")
        .put("val", JSONArray().put(left.coerceIn(-1.0, 1.0)).put(right.coerceIn(-1.0, 1.0)))
        .put("seq", sequence)
        .put("sent_at", nowMs)
        .put("ttl_ms", ttlMs)
        .toString()

    fun encodeStop(
        sequence: Long,
        nowMs: Long = System.currentTimeMillis(),
    ): String = JSONObject()
        .put("version", VERSION)
        .put("cmd", "stop")
        .put("seq", sequence)
        .put("sent_at", nowMs)
        .toString()

    fun encodeStatus(
        robotId: String,
        connected: Boolean,
        nowMs: Long = System.currentTimeMillis(),
    ): String = JSONObject()
        .put("version", VERSION)
        .put("robot_id", sanitizeRobotId(robotId))
        .put("connected", connected)
        .put("state", if (connected) "online" else "offline")
        .put("timestamp", nowMs)
        .toString()

    fun encodeSensors(
        accelerometer: Triple<Double, Double, Double>?,
        gyroscope: Triple<Double, Double, Double>?,
        batteryLevel: Double?,
        nowMs: Long = System.currentTimeMillis(),
    ): String {
        val data = JSONObject()
        accelerometer?.let {
            data.put("accelerometer", JSONObject().put("x", it.first).put("y", it.second).put("z", it.third))
        }
        gyroscope?.let {
            data.put("gyroscope", JSONObject().put("x", it.first).put("y", it.second).put("z", it.third))
        }
        batteryLevel?.let { data.put("battery_level", it) }
        return JSONObject()
            .put("version", VERSION)
            .put("type", "sensor_data")
            .put("data", data)
            .put("timestamp", nowMs)
            .toString()
    }

    fun encodeTelemetry(
        voltage: Double,
        leftRpm: Double,
        rightRpm: Double,
        sonarCm: Int?,
        nowMs: Long = System.currentTimeMillis(),
    ): String = JSONObject()
        .put("version", VERSION)
        .put("type", "telemetry")
        .put("voltage", voltage)
        .put("wheel_rpm", JSONObject().put("left", leftRpm).put("right", rightRpm))
        .put("sonar_cm", sonarCm ?: JSONObject.NULL)
        .put("timestamp", nowMs)
        .toString()

    fun parseCommand(json: String): RobotCommand {
        return try {
            val root = JSONObject(json)
            val sequence = root.optLong("seq", -1L)
            when (root.optString("cmd")) {
                "drive" -> {
                    val values = root.optJSONArray("val")
                    if (values == null || values.length() < 2) {
                        RobotCommand.Unknown("drive command is missing val[2]")
                    } else {
                        RobotCommand.Drive(
                            left = values.getDouble(0),
                            right = values.getDouble(1),
                            sequence = sequence,
                            sentAtMs = root.optLong("sent_at", 0L),
                            ttlMs = root.optLong("ttl_ms", 0L),
                        )
                    }
                }

                "stop" -> RobotCommand.Stop(
                    sequence = sequence,
                    sentAtMs = root.optLong("sent_at", 0L),
                )

                else -> RobotCommand.Unknown("unsupported cmd: ${root.optString("cmd")}")
            }
        } catch (error: Exception) {
            RobotCommand.Unknown("invalid json: ${error.message}")
        }
    }

    fun encodeVideoFrame(
        jpeg: ByteArray,
        frameId: Long,
        timestampNs: Long = System.nanoTime(),
    ): ByteArray {
        val header = ByteBuffer.allocate(VIDEO_HEADER_BYTES + jpeg.size).order(ByteOrder.LITTLE_ENDIAN)
        header.putInt(VIDEO_MAGIC)
        header.putShort(VERSION.toShort())
        header.putShort(0)
        header.putLong(timestampNs)
        header.putInt(frameId.toInt())
        header.put(jpeg)
        return header.array()
    }
}
