package io.openbene.zenoh.capture

import android.content.Context
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import io.openbene.zenoh.CaptureFrame
import io.openbene.zenoh.FrameMetadata
import io.openbene.zenoh.ZenohTransport
import java.util.concurrent.atomic.AtomicLong

/**
 * Glue between Camera2, the IMU and the Zenoh transport.
 *
 * Tier C only: every frame carries RGB, intrinsics and a timestamp. Pose, depth
 * and confidence stay empty, so the receiver shows them as unavailable.
 */
class CaptureController(
    private val context: Context,
    private val transport: ZenohTransport,
) {
    interface Listener {
        fun onCaptureState(message: String)
        fun onCaptureStats(text: String)
    }

    var listener: Listener? = null

    private val imu = ImuReader(context)
    private val handler = Handler(Looper.getMainLooper())
    private val frameIds = AtomicLong(0)
    private var camera: CameraSource? = null
    private var intrinsicsSource: String = "none"
    private var framesSent = 0L
    private var framesFailed = 0L
    private var bytesSent = 0L
    private var windowStartedAt = 0L
    private var windowFrames = 0

    val isRunning: Boolean get() = camera?.isRunning == true

    fun start(width: Int = 1280, height: Int = 720, fps: Int = 15) {
        if (camera != null) return
        val source = CameraSource(
            context,
            object : CameraSource.Listener {
                override fun onState(message: String) = listener?.onCaptureState(message) ?: Unit
                override fun onError(message: String) = listener?.onCaptureState(message) ?: Unit

                override fun onFrame(
                    jpeg: ByteArray,
                    timestampNs: Long,
                    width: Int,
                    height: Int,
                    intrinsics: CameraIntrinsics?,
                ) {
                    publish(jpeg, timestampNs, width, height, intrinsics)
                }
            },
        )
        camera = source
        windowStartedAt = System.currentTimeMillis()
        windowFrames = 0
        if (imu.available) {
            imu.start()
            handler.post(sensorLoop)
        }
        source.start(width, height, fps)
        handler.post(statsLoop)
    }

    fun stop() {
        handler.removeCallbacks(sensorLoop)
        handler.removeCallbacks(statsLoop)
        imu.stop()
        camera?.stop()
        camera = null
        listener?.onCaptureState("采集已停止")
    }

    private fun publish(
        jpeg: ByteArray,
        timestampNs: Long,
        width: Int,
        height: Int,
        intrinsics: CameraIntrinsics?,
    ) {
        intrinsicsSource = intrinsics?.source ?: "unknown"
        val frame = CaptureFrame(
            frameId = frameIds.incrementAndGet(),
            timestampNs = timestampNs,
            rgbJpeg = jpeg,
            metadata = FrameMetadata(
                width = width,
                height = height,
                fx = intrinsics?.fx ?: 0.0,
                fy = intrinsics?.fy ?: 0.0,
                cx = intrinsics?.cx ?: 0.0,
                cy = intrinsics?.cy ?: 0.0,
                trackingState = "camera_only",
                depthSource = "none",
            ),
        )
        runCatching { transport.publishCaptureFrame(frame) }
            .onSuccess {
                framesSent++
                windowFrames++
                bytesSent += jpeg.size
            }
            .onFailure { framesFailed++ }
    }

    private val sensorLoop = object : Runnable {
        override fun run() {
            val sample = imu.latest
            if (sample != null && transport.isConnected) {
                runCatching {
                    transport.publishSensors(
                        accelerometer = sample.accelerometer,
                        gyroscope = sample.gyroscope,
                        batteryLevel = batteryLevel(),
                    )
                }
            }
            handler.postDelayed(this, SENSOR_INTERVAL_MS)
        }
    }

    private val statsLoop = object : Runnable {
        override fun run() {
            val now = System.currentTimeMillis()
            val elapsed = (now - windowStartedAt).coerceAtLeast(1) / 1000.0
            val fps = windowFrames / elapsed
            val mbps = bytesSent / 1_000_000.0 / elapsed
            listener?.onCaptureStats(
                "帧 $framesSent · ${String.format("%.1f", fps)} fps · " +
                    "${String.format("%.1f", mbps)} MB/s · 失败 $framesFailed · 内参 $intrinsicsSource",
            )
            windowStartedAt = now
            windowFrames = 0
            bytesSent = 0
            handler.postDelayed(this, 1000L)
        }
    }

    private fun batteryLevel(): Double? {
        val manager = context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            ?: return null
        val percent = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (percent in 0..100) percent / 100.0 else null
    }

    companion object {
        private const val SENSOR_INTERVAL_MS = 200L
    }
}
