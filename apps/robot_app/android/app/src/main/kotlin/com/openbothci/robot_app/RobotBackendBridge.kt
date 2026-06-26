package com.openbothci.robot_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.gpu.GpuDelegate
import java.io.BufferedReader
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStreamReader
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.MappedByteBuffer
import java.nio.channels.FileChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger

data class BackendModelSpec(
    val id: String,
    val label: String,
    val kind: String,
    val source: String,
    val inputWidth: Int,
    val inputHeight: Int,
    val assetPath: String? = null,
    val remoteUrl: String? = null,
    val labelAssetPath: String? = null,
)

data class BackendSnapshot(
    val initialized: Boolean = false,
    val active: Boolean = false,
    val mode: String = "drive",
    val device: String = "cpu",
    val modelConfigured: Boolean = false,
    val frameWidth: Int = 0,
    val frameHeight: Int = 0,
    val framesProcessed: Int = 0,
    val framesPerSecond: Double = 0.0,
    val lastFrameTimestampMs: Int = 0,
    val lastInferenceMs: Int = 0,
    val status: String = "Backend idle",
    val suggestedLeft: Double = 0.0,
    val suggestedRight: Double = 0.0,
    val collecting: Boolean = false,
    val sampleCount: Int = 0,
    val activeModelId: String? = null,
    val detectionLabel: String? = null,
    val detectionScore: Double? = null,
    val trackingBoxLeft: Double? = null,
    val trackingBoxTop: Double? = null,
    val trackingBoxRight: Double? = null,
    val trackingBoxBottom: Double? = null,
    val collectionSessionPath: String? = null,
    val previewFrameBase64: String? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "initialized" to initialized,
        "active" to active,
        "mode" to mode,
        "device" to device,
        "modelConfigured" to modelConfigured,
        "frameWidth" to frameWidth,
        "frameHeight" to frameHeight,
        "framesProcessed" to framesProcessed,
        "framesPerSecond" to framesPerSecond,
        "lastFrameTimestampMs" to lastFrameTimestampMs,
        "lastInferenceMs" to lastInferenceMs,
        "status" to status,
        "suggestedLeft" to suggestedLeft,
        "suggestedRight" to suggestedRight,
        "collecting" to collecting,
        "sampleCount" to sampleCount,
        "activeModelId" to activeModelId,
        "detectionLabel" to detectionLabel,
        "detectionScore" to detectionScore,
        "trackingBoxLeft" to trackingBoxLeft,
        "trackingBoxTop" to trackingBoxTop,
        "trackingBoxRight" to trackingBoxRight,
        "trackingBoxBottom" to trackingBoxBottom,
        "collectionSessionPath" to collectionSessionPath,
        "previewFrameBase64" to previewFrameBase64,
        "event" to "snapshot",
    )
}

class RobotBackendBridge(
    private val context: Context,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val METHOD_CHANNEL = "com.openbothci.robot_app/backend/methods"
        private const val EVENT_CHANNEL = "com.openbothci.robot_app/backend/events"
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private val framesProcessed = AtomicInteger(0)

    private val models = listOf(
        BackendModelSpec(
            id = "autopilot_float",
            label = "OpenBot Autopilot",
            kind = "autopilot",
            source = "asset",
            inputWidth = 256,
            inputHeight = 96,
            assetPath = "models/autopilot_float.tflite",
        ),
        BackendModelSpec(
            id = "ssd_mobilenet_v1",
            label = "SSD MobileNet V1",
            kind = "detector",
            source = "asset",
            inputWidth = 300,
            inputHeight = 300,
            assetPath = "models/ssd_mobilenet_v1_1_metadata.tflite",
            labelAssetPath = "labels/labelmap.txt",
        ),
    )

    private var snapshot = BackendSnapshot()
    private var trackingTarget: RectF? = null
    private var trackingTargetLabel: String = "person"
    private var activeInterpreter: Interpreter? = null
    private var activeGpuDelegate: GpuDelegate? = null
    private var activeModelSpec: BackendModelSpec? = null
    private var detectorLabels: List<String> = emptyList()
    private var collectionSessionDir: File? = null
    private var lastTrackDetectionMs: Long = 0L
    private var smoothedTrackAreaRatio: Double = 0.0

    fun attach(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler(this)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                snapshot = snapshot.copy(
                    initialized = true,
                    status = "Backend ready",
                )
                emitSnapshot()
                result.success(snapshot.toMap())
            }

            "listModels" -> {
                result.success(models.map { modelToMap(it) })
            }

            "configure" -> {
                val mode = call.argument<String>("mode") ?: "drive"
                val device = call.argument<String>("device") ?: "cpu"
                val modelId = call.argument<String>("modelId")
                trackingTargetLabel = call.argument<String>("trackTargetLabel") ?: trackingTargetLabel

                closeRuntime()
                smoothedTrackAreaRatio = 0.0
                lastTrackDetectionMs = 0L

                if (mode == "drive") {
                    snapshot = snapshot.copy(
                        mode = mode,
                        device = device,
                        modelConfigured = false,
                        active = false,
                        activeModelId = null,
                        suggestedLeft = 0.0,
                        suggestedRight = 0.0,
                        detectionLabel = null,
                        detectionScore = null,
                        trackingBoxLeft = null,
                        trackingBoxTop = null,
                        trackingBoxRight = null,
                        trackingBoxBottom = null,
                        status = "Drive ready",
                    )
                    emitSnapshot()
                    result.success(snapshot.toMap())
                    return
                }

                val model = models.firstOrNull { it.id == modelId }
                if (model == null || model.assetPath.isNullOrBlank()) {
                    snapshot = snapshot.copy(
                        mode = mode,
                        device = device,
                        modelConfigured = false,
                        active = false,
                        activeModelId = null,
                        suggestedLeft = 0.0,
                        suggestedRight = 0.0,
                        detectionLabel = null,
                        detectionScore = null,
                        trackingBoxLeft = null,
                        trackingBoxTop = null,
                        trackingBoxRight = null,
                        trackingBoxBottom = null,
                        status = missingModelStatus(mode),
                    )
                    emitSnapshot()
                    result.success(snapshot.toMap())
                    return
                }

                if (!assetExists(model.assetPath)) {
                    snapshot = snapshot.copy(
                        mode = mode,
                        device = device,
                        modelConfigured = false,
                        active = false,
                        activeModelId = model.id,
                        suggestedLeft = 0.0,
                        suggestedRight = 0.0,
                        detectionLabel = null,
                        detectionScore = null,
                        trackingBoxLeft = null,
                        trackingBoxTop = null,
                        trackingBoxRight = null,
                        trackingBoxBottom = null,
                        status = missingAssetStatus(mode),
                    )
                    emitSnapshot()
                    result.success(snapshot.toMap())
                    return
                }

                try {
                    activeInterpreter = createInterpreter(model, device)
                    activeModelSpec = model
                    detectorLabels = loadLabels(model.labelAssetPath)
                    snapshot = snapshot.copy(
                        mode = mode,
                        device = device,
                        modelConfigured = true,
                        active = false,
                        activeModelId = model.id,
                        suggestedLeft = 0.0,
                        suggestedRight = 0.0,
                        detectionLabel = if (model.kind == "detector") trackingTargetLabel else null,
                        detectionScore = if (model.kind == "detector") 0.0 else null,
                        trackingBoxLeft = null,
                        trackingBoxTop = null,
                        trackingBoxRight = null,
                        trackingBoxBottom = null,
                        status = readyStatus(mode),
                    )
                } catch (_: Exception) {
                    closeRuntime()
                    snapshot = snapshot.copy(
                        mode = mode,
                        device = device,
                        modelConfigured = false,
                        active = false,
                        activeModelId = model.id,
                        suggestedLeft = 0.0,
                        suggestedRight = 0.0,
                        detectionLabel = null,
                        detectionScore = null,
                        trackingBoxLeft = null,
                        trackingBoxTop = null,
                        trackingBoxRight = null,
                        trackingBoxBottom = null,
                        status = loadFailedStatus(mode),
                    )
                }

                emitSnapshot()
                result.success(snapshot.toMap())
            }

            "startSession" -> {
                val canStart = when (snapshot.mode) {
                    "auto" -> snapshot.modelConfigured && activeInterpreter != null
                    "track" -> snapshot.modelConfigured && activeInterpreter != null
                    else -> true
                }
                snapshot = snapshot.copy(
                    active = canStart,
                    suggestedLeft = 0.0,
                    suggestedRight = 0.0,
                    status = when {
                        !canStart && snapshot.mode == "auto" && snapshot.modelConfigured -> loadFailedStatus("auto")
                        !canStart && snapshot.mode == "auto" -> missingModelStatus("auto")
                        !canStart && snapshot.mode == "track" -> missingModelStatus("track")
                        snapshot.mode == "auto" -> "Auto active"
                        snapshot.mode == "track" -> "Track active"
                        else -> "Drive active"
                    },
                )
                emitSnapshot()
                result.success(snapshot.toMap())
            }

            "stopSession" -> {
                snapshot = snapshot.copy(
                    active = false,
                    suggestedLeft = 0.0,
                    suggestedRight = 0.0,
                    trackingBoxLeft = null,
                    trackingBoxTop = null,
                    trackingBoxRight = null,
                    trackingBoxBottom = null,
                    status = when (snapshot.mode) {
                        "auto" -> if (snapshot.modelConfigured) "Auto ready" else missingModelStatus("auto")
                        "track" -> when {
                            !snapshot.modelConfigured -> missingModelStatus("track")
                            else -> "Track ready"
                        }
                        else -> "Drive ready"
                    },
                )
                emitSnapshot()
                result.success(snapshot.toMap())
            }

            "setCollecting" -> {
                val next = call.argument<Boolean>("value") == true
                if (next) {
                    ensureCollectionSession()
                }
                snapshot = snapshot.copy(
                    collecting = next,
                    collectionSessionPath = if (next) collectionSessionDir?.absolutePath else null,
                    sampleCount = if (next) snapshot.sampleCount else snapshot.sampleCount,
                )
                emitSnapshot()
                result.success(snapshot.toMap())
            }

            "submitFrame" -> {
                val width = (call.argument<Number>("width") ?: 0).toInt()
                val height = (call.argument<Number>("height") ?: 0).toInt()
                val timestampMs = (call.argument<Number>("timestampMs") ?: 0).toInt()
                val planes = call.argument<List<Map<String, Any?>>>("planes") ?: emptyList()
                val processed = framesProcessed.incrementAndGet()
                val loadedModel = activeModelSpec

                val inference = when {
                    !snapshot.active || loadedModel == null -> InferenceResult(0.0, 0.0, null, null, 0)
                    loadedModel.kind == "autopilot" -> runAutopilotInference(width, height, planes, loadedModel)
                    loadedModel.kind == "detector" -> runDetectorInference(width, height, planes, loadedModel)
                    else -> InferenceResult(0.0, 0.0, null, null, 0)
                }

                if (snapshot.collecting && snapshot.mode == "drive") {
                    saveCollectionFrame(width, height, planes, timestampMs)
                }

                val fps = when {
                    inference.inferenceMs <= 0 -> 0.0
                    else -> 1000.0 / inference.inferenceMs.toDouble()
                }
                snapshot = snapshot.copy(
                    frameWidth = width,
                    frameHeight = height,
                    framesProcessed = processed,
                    framesPerSecond = fps,
                    lastFrameTimestampMs = timestampMs,
                    lastInferenceMs = inference.inferenceMs,
                    suggestedLeft = inference.left,
                    suggestedRight = inference.right,
                    detectionLabel = inference.label ?: snapshot.detectionLabel,
                    detectionScore = inference.score ?: snapshot.detectionScore,
                    trackingBoxLeft = trackingTarget?.left?.toDouble(),
                    trackingBoxTop = trackingTarget?.top?.toDouble(),
                    trackingBoxRight = trackingTarget?.right?.toDouble(),
                    trackingBoxBottom = trackingTarget?.bottom?.toDouble(),
                    sampleCount = if (snapshot.collecting && snapshot.mode == "drive") snapshot.sampleCount + 1 else snapshot.sampleCount,
                    collectionSessionPath = collectionSessionDir?.absolutePath,
                    previewFrameBase64 = encodePreviewFrame(bitmap = planesToBitmap(width, height, planes)),
                    status = when {
                        snapshot.collecting && snapshot.mode == "drive" -> "Collecting"
                        snapshot.mode == "auto" && snapshot.active -> "Auto inferencing"
                        snapshot.mode == "track" && snapshot.active -> "Track inferencing"
                        else -> snapshot.status
                    },
                )
                emitSnapshot()
                result.success(snapshot.toMap())
            }

            "dispose" -> {
                closeRuntime()
                trackingTarget = null
                framesProcessed.set(0)
                snapshot = BackendSnapshot()
                emitSnapshot()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        emitSnapshot()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun createInterpreter(
        model: BackendModelSpec,
        device: String,
    ): Interpreter {
        val options = Interpreter.Options()
        when (device) {
            "nnapi" -> options.setUseNNAPI(true)
            "gpu" -> {
                val delegate = GpuDelegate()
                activeGpuDelegate = delegate
                options.addDelegate(delegate)
            }
        }
        options.setNumThreads(if (device == "cpu") 4 else 1)
        return Interpreter(loadModelFile(model.assetPath!!), options)
    }

    private fun loadModelFile(assetPath: String): MappedByteBuffer {
        val fileDescriptor = context.assets.openFd(assetPath)
        FileInputStream(fileDescriptor.fileDescriptor).use { inputStream ->
            val fileChannel = inputStream.channel
            return fileChannel.map(
                FileChannel.MapMode.READ_ONLY,
                fileDescriptor.startOffset,
                fileDescriptor.declaredLength,
            )
        }
    }

    private fun loadLabels(path: String?): List<String> {
        if (path.isNullOrBlank() || !assetExists(path)) return emptyList()
        val labels = mutableListOf<String>()
        BufferedReader(InputStreamReader(context.assets.open(path))).use { reader ->
            while (true) {
                val line = reader.readLine() ?: break
                if (line.isNotBlank()) {
                    labels += line.trim()
                }
            }
        }
        return labels
    }

    private fun assetExists(path: String?): Boolean {
        if (path.isNullOrBlank()) return false
        return try {
            context.assets.open(path).close()
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun closeRuntime() {
        activeInterpreter?.close()
        activeInterpreter = null
        activeGpuDelegate?.close()
        activeGpuDelegate = null
        activeModelSpec = null
        detectorLabels = emptyList()
        trackingTarget = null
        lastTrackDetectionMs = 0L
        smoothedTrackAreaRatio = 0.0
    }

    private fun ensureCollectionSession() {
        if (collectionSessionDir != null) return
        val timestamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
        val root = File(context.getExternalFilesDir(null), "OpenBotSessions")
        val session = File(root, timestamp)
        File(session, "images").mkdirs()
        File(session, "meta").mkdirs()
        collectionSessionDir = session
    }

    private fun saveCollectionFrame(
        frameWidth: Int,
        frameHeight: Int,
        planes: List<Map<String, Any?>>,
        timestampMs: Int,
    ) {
        val session = collectionSessionDir ?: return
        val bitmap = planesToBitmap(frameWidth, frameHeight, planes) ?: return
        val imageFile = File(session, "images/${timestampMs}_preview.png")
        FileOutputStream(imageFile).use { output ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
        }
        val cropFile = File(session, "images/${timestampMs}_crop.png")
        val cropBitmap = cropAndScaleAutopilot(bitmap, 256, 96)
        FileOutputStream(cropFile).use { output ->
            cropBitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
        }
        val metaFile = File(session, "meta/${timestampMs}.txt")
        metaFile.writeText(
            buildString {
                appendLine("timestampMs=$timestampMs")
                appendLine("mode=${snapshot.mode}")
                appendLine("left=${snapshot.suggestedLeft}")
                appendLine("right=${snapshot.suggestedRight}")
                appendLine("status=${snapshot.status}")
            },
        )
    }

    private fun encodePreviewFrame(bitmap: Bitmap?): String? {
        if (bitmap == null) return null
        val scaled = Bitmap.createScaledBitmap(bitmap, 480, 270, true)
        val output = ByteArrayOutputStream()
        scaled.compress(Bitmap.CompressFormat.JPEG, 55, output)
        return Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
    }

    private fun runAutopilotInference(
        frameWidth: Int,
        frameHeight: Int,
        planes: List<Map<String, Any?>>,
        model: BackendModelSpec,
    ): InferenceResult {
        val start = System.currentTimeMillis()
        val bitmap = planesToBitmap(frameWidth, frameHeight, planes) ?: return InferenceResult(0.0, 0.0, null, null, 0)
        val cropped = cropAndScaleAutopilot(bitmap, model.inputWidth, model.inputHeight)
        val imageInput = bitmapToFloatBuffer(cropped)
        val cmdInput = ByteBuffer.allocateDirect(4).order(ByteOrder.nativeOrder()).apply {
            putFloat(0f)
            rewind()
        }
        val output = Array(1) { FloatArray(2) }
        val interpreter = activeInterpreter ?: return InferenceResult(0.0, 0.0, null, null, 0)
        val inputs = try {
            val cmdIndex = interpreter.getInputIndex("serving_default_cmd_input:0")
            if (cmdIndex == 0) arrayOf(cmdInput, imageInput) else arrayOf(imageInput, cmdInput)
        } catch (_: Exception) {
            arrayOf(imageInput, cmdInput)
        }
        interpreter.runForMultipleInputsOutputs(inputs, mapOf(0 to output))
        val end = System.currentTimeMillis()
        val left = output[0][0].toDouble().coerceIn(-1.0, 1.0)
        val right = output[0][1].toDouble().coerceIn(-1.0, 1.0)
        return InferenceResult(left, right, null, null, (end - start).toInt())
    }

    private fun runDetectorInference(
        frameWidth: Int,
        frameHeight: Int,
        planes: List<Map<String, Any?>>,
        model: BackendModelSpec,
    ): InferenceResult {
        val start = System.currentTimeMillis()
        val bitmap = planesToBitmap(frameWidth, frameHeight, planes) ?: return InferenceResult(0.0, 0.0, null, null, 0)
        val scaled = Bitmap.createScaledBitmap(bitmap, model.inputWidth, model.inputHeight, true)
        val imageInput = bitmapToByteBuffer(scaled)
        val interpreter = activeInterpreter ?: return InferenceResult(0.0, 0.0, null, null, 0)

        val outputLocations = Array(1) { Array(10) { FloatArray(4) } }
        val outputClasses = Array(1) { FloatArray(10) }
        val outputScores = Array(1) { FloatArray(10) }
        val numDetections = FloatArray(1)
        val outputs = linkedMapOf<Int, Any>(
            0 to outputLocations,
            1 to outputClasses,
            2 to outputScores,
            3 to numDetections,
        )
        interpreter.runForMultipleInputsOutputs(arrayOf(imageInput), outputs)

        val now = System.currentTimeMillis()
        val detectionCount = numDetections[0].toInt().coerceIn(0, outputScores[0].size)
        val candidates = mutableListOf<DetectorCandidate>()
        for (index in 0 until detectionCount) {
            val score = outputScores[0][index].toDouble()
            if (score <= 0.2) continue
            val classId = outputClasses[0][index].toInt() + 1
            val label = detectorLabels.getOrNull(classId) ?: continue
            if (!label.equals(trackingTargetLabel, ignoreCase = true)) continue
            val box = outputLocations[0][index]
            val target = RectF(
                box[1] * frameWidth,
                box[0] * frameHeight,
                box[3] * frameWidth,
                box[2] * frameHeight,
            )
            candidates += DetectorCandidate(label = label, score = score, box = sanitizeRect(target, frameWidth, frameHeight))
        }

        val bestCandidate = selectBestTrackCandidate(candidates)
        val leftRight: Pair<Double, Double>
        val label: String?
        val score: Double?

        if (bestCandidate != null) {
            trackingTarget = bestCandidate.box
            lastTrackDetectionMs = now
            leftRight = computeTrackControls(frameWidth, frameHeight)
            label = bestCandidate.label
            score = bestCandidate.score
        } else if (trackingTarget != null && now - lastTrackDetectionMs <= 450L) {
            leftRight = computeTrackControls(frameWidth, frameHeight)
            label = snapshot.detectionLabel ?: trackingTargetLabel
            score = snapshot.detectionScore
        } else {
            trackingTarget = null
            smoothedTrackAreaRatio = 0.0
            leftRight = 0.0 to 0.0
            label = trackingTargetLabel
            score = 0.0
        }

        val end = System.currentTimeMillis()
        return InferenceResult(leftRight.first, leftRight.second, label, score, (end - start).toInt())
    }

    private fun cropAndScaleAutopilot(
        bitmap: Bitmap,
        dstWidth: Int,
        dstHeight: Int,
    ): Bitmap {
        val cropTop = bitmap.height * (240f / 720f)
        val srcRect = RectF(0f, cropTop, bitmap.width.toFloat(), bitmap.height.toFloat())
        val dstBitmap = Bitmap.createBitmap(dstWidth, dstHeight, Bitmap.Config.ARGB_8888)
        val canvas = android.graphics.Canvas(dstBitmap)
        val matrix = Matrix().apply {
            setRectToRect(srcRect, RectF(0f, 0f, dstWidth.toFloat(), dstHeight.toFloat()), Matrix.ScaleToFit.CENTER)
        }
        canvas.drawBitmap(bitmap, matrix, null)
        return dstBitmap
    }

    private fun bitmapToFloatBuffer(bitmap: Bitmap): ByteBuffer {
        val buffer = ByteBuffer.allocateDirect(4 * bitmap.width * bitmap.height * 3)
        buffer.order(ByteOrder.nativeOrder())
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        for (pixel in pixels) {
            buffer.putFloat(((pixel shr 16 and 0xFF) / 255.0f))
            buffer.putFloat(((pixel shr 8 and 0xFF) / 255.0f))
            buffer.putFloat(((pixel and 0xFF) / 255.0f))
        }
        buffer.rewind()
        return buffer
    }

    private fun bitmapToByteBuffer(bitmap: Bitmap): ByteBuffer {
        val buffer = ByteBuffer.allocateDirect(bitmap.width * bitmap.height * 3)
        val pixels = IntArray(bitmap.width * bitmap.height)
        bitmap.getPixels(pixels, 0, bitmap.width, 0, 0, bitmap.width, bitmap.height)
        for (pixel in pixels) {
            buffer.put((pixel shr 16 and 0xFF).toByte())
            buffer.put((pixel shr 8 and 0xFF).toByte())
            buffer.put((pixel and 0xFF).toByte())
        }
        buffer.rewind()
        return buffer
    }

    private fun planesToBitmap(
        width: Int,
        height: Int,
        planes: List<Map<String, Any?>>,
    ): Bitmap? {
        if (planes.size < 3) return null
        val yPlane = planes[0]["bytes"] as? ByteArray ?: return null
        val uPlane = planes[1]["bytes"] as? ByteArray ?: return null
        val vPlane = planes[2]["bytes"] as? ByteArray ?: return null
        val yRowStride = (planes[0]["bytesPerRow"] as? Number)?.toInt() ?: width
        val uRowStride = (planes[1]["bytesPerRow"] as? Number)?.toInt() ?: width / 2
        val uPixelStride = (planes[1]["bytesPerPixel"] as? Number)?.toInt() ?: 2
        val vPixelStride = (planes[2]["bytesPerPixel"] as? Number)?.toInt() ?: 2

        val out = IntArray(width * height)
        var yp = 0
        for (j in 0 until height) {
            val pY = yRowStride * j
            val pUV = uRowStride * (j shr 1)
            for (i in 0 until width) {
                val uvOffsetU = pUV + (i shr 1) * uPixelStride
                val uvOffsetV = pUV + (i shr 1) * vPixelStride
                out[yp++] = yuvToRgb(
                    yPlane[pY + i].toInt() and 0xFF,
                    uPlane[uvOffsetU].toInt() and 0xFF,
                    vPlane[uvOffsetV].toInt() and 0xFF,
                )
            }
        }
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        bitmap.setPixels(out, 0, width, 0, 0, width, height)
        return bitmap
    }

    private fun yuvToRgb(y: Int, u: Int, v: Int): Int {
        var yVal = y - 16
        var uVal = u - 128
        var vVal = v - 128
        if (yVal < 0) yVal = 0
        var r = 1192 * yVal + 1634 * vVal
        var g = 1192 * yVal - 833 * vVal - 400 * uVal
        var b = 1192 * yVal + 2066 * uVal
        r = r.coerceIn(0, 262143)
        g = g.coerceIn(0, 262143)
        b = b.coerceIn(0, 262143)
        return -0x1000000 or ((r shl 6) and 0x00FF0000) or ((g shr 2) and 0x0000FF00) or ((b shr 10) and 0x000000FF)
    }

    private fun sanitizeRect(rect: RectF, frameWidth: Int, frameHeight: Int): RectF {
        val left = rect.left.coerceIn(0f, frameWidth.toFloat())
        val top = rect.top.coerceIn(0f, frameHeight.toFloat())
        val right = rect.right.coerceIn(left, frameWidth.toFloat())
        val bottom = rect.bottom.coerceIn(top, frameHeight.toFloat())
        return RectF(left, top, right, bottom)
    }

    private fun selectBestTrackCandidate(candidates: List<DetectorCandidate>): DetectorCandidate? {
        if (candidates.isEmpty()) return null
        val previousTarget = trackingTarget
        return candidates.maxWithOrNull(
            compareBy<DetectorCandidate>(
                { (it.score * 100).toInt() },
                { trackCenterPreference(it.box, previousTarget) },
                { (it.box.width() * it.box.height()).toDouble() },
            ),
        )
    }

    private fun trackCenterPreference(box: RectF, previousTarget: RectF?): Double {
        if (previousTarget == null) return 0.0
        val dx = box.centerX() - previousTarget.centerX()
        val dy = box.centerY() - previousTarget.centerY()
        return -kotlin.math.hypot(dx.toDouble(), dy.toDouble())
    }

    private fun computeTrackControls(
        frameWidth: Int,
        frameHeight: Int,
    ): Pair<Double, Double> {
        val target = trackingTarget ?: return 0.0 to 0.0
        if (frameWidth <= 0 || frameHeight <= 0) return 0.0 to 0.0

        val centerX = target.centerX().coerceIn(0f, frameWidth.toFloat())
        val xNorm = 1.0 - 2.0 * centerX / frameWidth.toDouble()
        val steering = (xNorm * 0.72).coerceIn(-0.72, 0.72)

        val boxArea = target.width().toDouble() * target.height().toDouble()
        val frameArea = frameWidth.toDouble() * frameHeight.toDouble()
        val rawAreaRatio = (boxArea / frameArea).coerceIn(0.0, 1.0)
        smoothedTrackAreaRatio = if (smoothedTrackAreaRatio == 0.0) {
            rawAreaRatio
        } else {
            smoothedTrackAreaRatio * 0.72 + rawAreaRatio * 0.28
        }

        val speed = when {
            smoothedTrackAreaRatio < 0.06 -> 0.78
            smoothedTrackAreaRatio < 0.18 -> 0.62
            smoothedTrackAreaRatio < 0.30 -> 0.42
            smoothedTrackAreaRatio < 0.42 -> 0.24
            else -> 0.0
        }

        val left = (speed + steering).coerceIn(-1.0, 1.0)
        val right = (speed - steering).coerceIn(-1.0, 1.0)
        return left to right
    }

    private fun readyStatus(mode: String): String {
        return when (mode) {
            "auto" -> "Auto ready"
            "track" -> "Track ready"
            else -> if (snapshot.collecting) "Collecting" else "Drive ready"
        }
    }

    private fun missingModelStatus(mode: String): String {
        return when (mode) {
            "auto" -> "Auto model missing"
            "track" -> "Track model missing"
            else -> "Drive ready"
        }
    }

    private fun missingAssetStatus(mode: String): String {
        return when (mode) {
            "auto" -> "Auto model asset missing"
            "track" -> "Track model asset missing"
            else -> "Drive ready"
        }
    }

    private fun loadFailedStatus(mode: String): String {
        return when (mode) {
            "auto" -> "Auto model load failed"
            "track" -> "Track model load failed"
            else -> "Drive ready"
        }
    }

    private fun emitSnapshot() {
        val payload = snapshot.toMap()
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    private fun modelToMap(model: BackendModelSpec): Map<String, Any?> = mapOf(
        "id" to model.id,
        "label" to model.label,
        "kind" to model.kind,
        "source" to model.source,
        "inputWidth" to model.inputWidth,
        "inputHeight" to model.inputHeight,
        "assetPath" to model.assetPath,
        "remoteUrl" to model.remoteUrl,
        "labelAssetPath" to model.labelAssetPath,
        "assetAvailable" to assetExists(model.assetPath),
    )
}

data class DetectorCandidate(
    val label: String,
    val score: Double,
    val box: RectF,
)

data class InferenceResult(
    val left: Double,
    val right: Double,
    val label: String?,
    val score: Double?,
    val inferenceMs: Int,
)
