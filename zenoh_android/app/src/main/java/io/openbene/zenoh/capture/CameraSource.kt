package io.openbene.zenoh.capture

import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.SystemClock
import android.util.Size
import java.io.ByteArrayOutputStream

/**
 * Tier C capture: Camera2 only, no ARCore required.
 *
 * Streams JPEG frames together with calibrated intrinsics. There is no camera
 * pose or depth here; those stay null so the ZPKD flags mark them absent.
 */
class CameraSource(
    private val context: Context,
    private val listener: Listener,
) {
    interface Listener {
        fun onState(message: String)
        fun onFrame(
            jpeg: ByteArray,
            timestampNs: Long,
            width: Int,
            height: Int,
            intrinsics: CameraIntrinsics?,
        )

        fun onError(message: String)
    }

    private val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null

    @Volatile
    private var running = false

    @Volatile
    private var minIntervalNs = 66_000_000L

    @Volatile
    private var intrinsics: CameraIntrinsics? = null

    @Volatile
    private var lastFrameNs = 0L

    @Volatile
    private var afModes: IntArray? = null

    val isRunning: Boolean get() = running

    fun start(width: Int, height: Int, fps: Int) {
        if (running) return
        minIntervalNs = 1_000_000_000L / fps.coerceIn(1, 30)
        val worker = HandlerThread("openbene-camera").also { it.start() }
        thread = worker
        handler = Handler(worker.looper)
        running = true
        try {
            val cameraId = pickCamera()
            val characteristics = manager.getCameraCharacteristics(cameraId)
            val size = pickSize(characteristics, width, height) ?: Size(width, height)
            intrinsics = CameraIntrinsics.fromCharacteristics(
                characteristics,
                size.width,
                size.height,
            )
            afModes = characteristics.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)
            val imageReader = ImageReader.newInstance(
                size.width,
                size.height,
                ImageFormat.YUV_420_888,
                2,
            )
            reader = imageReader
            imageReader.setOnImageAvailableListener({ onImageAvailable(it) }, handler)
            listener.onState("Camera ${size.width}x${size.height} via $cameraId")
            @Suppress("MissingPermission")
            manager.openCamera(cameraId, deviceCallback, handler)
        } catch (error: CameraAccessException) {
            stop()
            listener.onError("Camera open failed: ${error.message}")
        } catch (error: IllegalArgumentException) {
            stop()
            listener.onError("Camera configuration failed: ${error.message}")
        }
    }

    fun stop() {
        running = false
        runCatching { session?.close() }
        session = null
        runCatching { device?.close() }
        device = null
        runCatching { reader?.close() }
        reader = null
        thread?.quitSafely()
        thread = null
        handler = null
        listener.onState("Camera stopped")
    }

    private fun pickCamera(): String {
        val ids = manager.cameraIdList
        if (ids.isEmpty()) throw IllegalArgumentException("no camera reported")
        val back = ids.firstOrNull {
            manager.getCameraCharacteristics(it)
                .get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
        }
        return back ?: ids.first()
    }

    private fun pickSize(
        characteristics: CameraCharacteristics,
        width: Int,
        height: Int,
    ): Size? {
        val sizes = characteristics
            .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?.getOutputSizes(ImageFormat.YUV_420_888)
            ?.toList()
            ?: return null
        if (sizes.isEmpty()) return null
        return sizes.firstOrNull { it.width == width && it.height == height }
            ?: sizes.filter { it.width <= width * 3 / 2 }
                .minByOrNull { kotlin.math.abs(it.width - width) }
            ?: sizes.minByOrNull { it.width }
    }

    private val deviceCallback = object : CameraDevice.StateCallback() {
        override fun onOpened(camera: CameraDevice) {
            if (!running) {
                camera.close()
                return
            }
            device = camera
            val surface = reader?.surface ?: return
            runCatching {
                @Suppress("DEPRECATION")
                camera.createCaptureSession(
                    listOf(surface),
                    sessionCallback,
                    handler,
                )
            }.onFailure { listener.onError("Capture session failed: ${it.message}") }
        }

        override fun onDisconnected(camera: CameraDevice) {
            camera.close()
            device = null
            if (running) listener.onError("Camera disconnected")
            running = false
        }

        override fun onError(camera: CameraDevice, error: Int) {
            camera.close()
            device = null
            running = false
            listener.onError("Camera error $error")
        }
    }

    private val sessionCallback = object : CameraCaptureSession.StateCallback() {
        override fun onConfigured(configured: CameraCaptureSession) {
            if (!running) {
                configured.close()
                return
            }
            session = configured
            val camera = device ?: return
            val surface = reader?.surface ?: return
            runCatching {
                val request = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                    addTarget(surface)
                    set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                    set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                    if (afModes?.contains(CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE) == true) {
                        set(
                            CaptureRequest.CONTROL_AF_MODE,
                            CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE,
                        )
                    }
                }
                configured.setRepeatingRequest(request.build(), null, handler)
                listener.onState("Camera streaming")
            }.onFailure { listener.onError("Camera start failed: ${it.message}") }
        }

        override fun onConfigureFailed(session: CameraCaptureSession) {
            listener.onError("Camera session configure failed")
        }
    }

    private fun onImageAvailable(source: ImageReader) {
        val image = runCatching { source.acquireLatestImage() }.getOrNull() ?: return
        val timestampNs = SystemClock.elapsedRealtimeNanos()
        try {
            if (!running || timestampNs - lastFrameNs < minIntervalNs) return
            val planes = image.planes
            if (planes.size < 3) return
            val nv21 = ByteArray(Nv21.size(image.width, image.height))
            Nv21.writeLuma(
                planes[0].buffer,
                planes[0].rowStride,
                planes[0].pixelStride,
                image.width,
                image.height,
                nv21,
            )
            Nv21.writeChroma(
                planes[2].buffer,
                planes[2].rowStride,
                planes[2].pixelStride,
                planes[1].buffer,
                planes[1].rowStride,
                planes[1].pixelStride,
                image.width,
                image.height,
                nv21,
            )
            val jpeg = ByteArrayOutputStream().use { out ->
                YuvImage(nv21, ImageFormat.NV21, image.width, image.height, null)
                    .compressToJpeg(Rect(0, 0, image.width, image.height), 80, out)
                out.toByteArray()
            }
            lastFrameNs = timestampNs
            listener.onFrame(jpeg, timestampNs, image.width, image.height, intrinsics)
        } catch (error: Exception) {
            listener.onError("Frame encode failed: ${error.message}")
        } finally {
            image.close()
        }
    }
}
