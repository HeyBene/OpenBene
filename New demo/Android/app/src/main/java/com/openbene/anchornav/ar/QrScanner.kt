package com.openbene.anchornav.ar

import android.media.Image
import android.util.Log
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import com.openbene.anchornav.nav.Pose2D
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.AtomicBoolean

/** One decoded marker sheet, with everything the estimator needs. */
data class QrDetection(
    val rawValue: String,
    /** Clockwise from the code's own top left corner, in camera image pixels. */
    val corners: List<DoubleArray>,
    val imageWidth: Int,
    val imageHeight: Int,
    /** Camera pose captured when the frame that produced this image arrived. */
    val cameraPose: RigidTransform,
    val deviceInAr: Pose2D,
    val cameraImageRotationDegrees: Int,
    val timestampS: Double,
)

/**
 * Decodes the printed QR sheets on the ARCore camera image stream.
 *
 * The camera image arrives in sensor orientation, and so do the corners and the
 * intrinsics that [MarkerGeometry] uses, so nothing has to be rotated here. Only
 * one decode runs at a time; frames that arrive meanwhile are dropped.
 */
class QrScanner {

    private val scanner = BarcodeScanning.getClient(
        BarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .build(),
    )
    private val busy = AtomicBoolean(false)

    /** Post decoded markers here; the AR thread drains it every frame. */
    val detections = ConcurrentLinkedQueue<QrDetection>()

    /**
     * Takes ownership of [image] and always closes it. Silently drops the frame
     * when a decode is still running.
     */
    fun process(
        image: Image,
        cameraPose: RigidTransform,
        devicePose: Pose2D,
        cameraImageRotationDegrees: Int,
        timestampS: Double,
    ) {
        if (!busy.compareAndSet(false, true)) {
            image.close()
            return
        }
        val width = image.width
        val height = image.height
        val input = try {
            InputImage.fromMediaImage(image, 0)
        } catch (error: Throwable) {
            Log.w(TAG, "could not wrap the camera image", error)
            busy.set(false)
            image.close()
            return
        }
        scanner.process(input)
            .addOnSuccessListener { barcodes ->
                for (barcode in barcodes) {
                    val value = barcode.rawValue ?: continue
                    val points = barcode.cornerPoints ?: continue
                    if (points.size != 4) continue
                    val corners = points.map { doubleArrayOf(it.x.toDouble(), it.y.toDouble()) }
                    detections.add(
                        QrDetection(
                            rawValue = value,
                            corners = corners,
                            imageWidth = width,
                            imageHeight = height,
                            cameraPose = cameraPose,
                            deviceInAr = devicePose,
                            cameraImageRotationDegrees = cameraImageRotationDegrees,
                            timestampS = timestampS,
                        ),
                    )
                }
            }
            .addOnFailureListener { error -> Log.w(TAG, "barcode decode failed", error) }
            .addOnCompleteListener {
                busy.set(false)
                image.close()
            }
    }

    fun close() {
        runCatching { scanner.close() }
        detections.clear()
    }

    private companion object {
        const val TAG = "QrScanner"
    }
}
