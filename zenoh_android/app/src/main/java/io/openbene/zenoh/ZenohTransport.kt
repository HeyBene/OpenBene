package io.openbene.zenoh

import io.zenoh.Config
import io.zenoh.Session
import io.zenoh.Zenoh
import io.zenoh.bytes.ZBytes
import io.zenoh.keyexpr.intoKeyExpr
import io.zenoh.pubsub.Publisher
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/**
 * Standalone phone-side Zenoh transport.
 *
 * This class deliberately knows nothing about USB/BLE motor control. Wire
 * [Listener.onCommand] to the existing OpenBot command sink when integrating.
 */
class ZenohTransport(
    private val listener: Listener,
) : AutoCloseable {

    interface Listener {
        fun onState(message: String)
        fun onCommand(command: RobotCommand, raw: String)
        fun onSample(key: String, payload: ByteArray)
    }

    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private val publishers = ConcurrentHashMap<String, Publisher>()
    private val sequence = AtomicLong(0L)

    @Volatile
    private var session: Session? = null

    @Volatile
    private var commandSubscriber: AutoCloseable? = null

    @Volatile
    private var heartbeat: ScheduledFuture<*>? = null

    @Volatile
    private var activeRobotId: String = "robot"

    @Volatile
    private var activePrefix: String = "openbene/robot"

    /** Stable identifier for this app session, used to name recording runs. */
    val sessionId: String = java.util.UUID.randomUUID().toString().lowercase()

    val isConnected: Boolean
        get() = session != null

    fun connect(rawEndpoint: String, robotId: String) {
        val endpoint = Protocol.normalizeEndpoint(rawEndpoint)
        if (endpoint == null) {
            listener.onState("Endpoint is empty")
            return
        }
        val safeRobotId = Protocol.sanitizeRobotId(robotId)
        ioExecutor.execute {
            runCatching {
                closeSession()
                Zenoh.initLogFromEnvOr("warn")
                val config = if (endpoint.isEmpty()) {
                    Config.default()
                } else {
                    Config.fromJson5(
                        """
                        {
                          mode: "client",
                          connect: { endpoints: ["${escapeJson(endpoint)}"] },
                          scouting: { multicast: { enabled: false } }
                        }
                        """.trimIndent(),
                    ).getOrThrow()
                }
                val opened = Zenoh.open(config).getOrThrow()
                activeRobotId = safeRobotId
                activePrefix = Protocol.keyPrefix(safeRobotId)
                session = opened

                listOf("status", "sensors", "telemetry", "video", "frame", "session").forEach { suffix ->
                    val key = "$activePrefix/$suffix"
                    publishers[suffix] = opened.declarePublisher(key.intoKeyExpr().getOrThrow()).getOrThrow()
                }

                commandSubscriber = opened.declareSubscriber(
                    "$activePrefix/cmd".intoKeyExpr().getOrThrow(),
                    callback = { sample ->
                        val raw = sample.payload.tryToString().getOrElse { "<binary>" }
                        val payload = sample.payload.toBytes()
                        listener.onSample(sample.keyExpr.toString(), payload)
                        listener.onCommand(Protocol.parseCommand(raw), raw)
                    },
                ).getOrThrow()

                heartbeat?.cancel(false)
                heartbeat = scheduler.scheduleAtFixedRate(
                    { publishHeartbeatSafely() },
                    0L,
                    2L,
                    TimeUnit.SECONDS,
                )
                listener.onState("Connected to $endpoint as $activePrefix")
            }.onFailure { error ->
                closeSession()
                listener.onState("Connect failed: ${error.message}")
            }
        }
    }

    fun publishHeartbeat() {
        publishJson("status", Protocol.encodeStatus(activeRobotId, true))
    }

    fun publishSensors(
        accelerometer: Triple<Double, Double, Double>? = Triple(0.0, 0.0, 9.81),
        gyroscope: Triple<Double, Double, Double>? = Triple(0.0, 0.0, 0.0),
        batteryLevel: Double? = 0.86,
    ) {
        publishJson(
            "sensors",
            Protocol.encodeSensors(accelerometer, gyroscope, batteryLevel),
        )
    }

    fun publishTelemetry(
        voltage: Double = 11.8,
        leftRpm: Double = 0.0,
        rightRpm: Double = 0.0,
        sonarCm: Int? = null,
    ) {
        publishJson(
            "telemetry",
            Protocol.encodeTelemetry(voltage, leftRpm, rightRpm, sonarCm),
        )
    }

    fun publishVideoFrame(jpeg: ByteArray, frameId: Long = sequence.incrementAndGet()) {
        val publisher = publishers["video"] ?: error("Not connected")
        val payload = Protocol.encodeVideoFrame(jpeg, frameId)
        publisher.put(ZBytes.from(payload)).getOrThrow()
        listener.onState("Published binary video frame: ${payload.size} bytes, id=$frameId")
    }

    /**
     * Publishes one multi-plane capture frame on `.../frame`.
     *
     * This mirrors the iOS `ZPKD` payload, so the same PC receiver decodes both
     * phones. [legacyVideo] also emits the JPEG-only `ZFRM` frame on
     * `.../video` for older receivers.
     */
    fun publishCaptureFrame(frame: CaptureFrame, legacyVideo: Boolean = false) {
        val publisher = publishers["frame"] ?: error("Not connected")
        val payload = FrameCodec.encode(frame)
        publisher.put(ZBytes.from(payload)).getOrThrow()
        listener.onState(
            "Published capture frame: ${payload.size} bytes, id=${frame.frameId}, " +
                "flags=0x${Integer.toHexString(FrameCodec.flagsFor(frame))}",
        )
        if (legacyVideo) {
            frame.rgbJpeg?.let { publishVideoFrame(it, frame.frameId) }
        }
    }

    /** Marks recording boundaries so the PC can open and close a session. */
    fun publishSessionEvent(kind: SessionEvent) {
        publishJson("session", kind.toJson(activeRobotId, sessionId))
    }

    /** Only for local smoke testing; the real command publisher is the PC. */
    fun publishLoopbackDrive(left: Double = 0.4, right: Double = 0.4) {
        val seq = sequence.incrementAndGet()
        publishJson("cmd", Protocol.encodeDrive(left, right, seq))
    }

    /** Only for local smoke testing; the real command publisher is the PC. */
    fun publishLoopbackStop() {
        val seq = sequence.incrementAndGet()
        publishJson("cmd", Protocol.encodeStop(seq))
    }

    fun publishJson(suffix: String, json: String) {
        val publisher = publishers[suffix] ?: error("Publisher '$suffix' is not ready; connect first")
        publisher.put(ZBytes.from(json)).getOrThrow()
    }

    fun disconnect() {
        ioExecutor.execute { closeSession() }
    }

    private fun publishHeartbeatSafely() {
        runCatching { publishHeartbeat() }.onFailure {
            listener.onState("Heartbeat failed: ${it.message}")
        }
    }

    private fun closeSession() {
        heartbeat?.cancel(false)
        heartbeat = null
        runCatching { commandSubscriber?.close() }
        commandSubscriber = null
        publishers.values.forEach { runCatching { it.undeclare() } }
        publishers.clear()
        runCatching { session?.close() }
        session = null
        listener.onState("Disconnected")
    }

    override fun close() {
        runCatching { closeSession() }
        scheduler.shutdownNow()
        ioExecutor.shutdownNow()
    }

    private fun escapeJson(value: String): String =
        value.replace("\\", "\\\\").replace("\"", "\\\"")
}
