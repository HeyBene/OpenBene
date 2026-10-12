package com.openbene.anchornav.robot

import android.media.Image
import android.util.Log
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.openbene.anchornav.nav.FollowController
import com.openbene.anchornav.nav.PersonBox
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The detection source of follow mode.
 *
 * OpenBot's own tracking app runs a TFLite person detector on the phone; that
 * model is not bundled here, so the demo follows the operator's face with the
 * on-device ML Kit face detector. The controller only ever sees a normalised
 * box, so following a whole person instead means replacing this class and
 * switching to [com.openbene.anchornav.nav.FollowConfig] defaults.
 *
 * Only one decode runs at a time; frames that arrive meanwhile are dropped.
 */
class PersonBoxDetector {

    private val detector = FaceDetection.getClient(
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setMinFaceSize(0.15f)
            .build(),
    )
    private val busy = AtomicBoolean(false)

    @Volatile
    var latestBox: PersonBox? = null
        private set

    /** Timestamp of the frame that produced [latestBox]. */
    @Volatile
    var latestAtS: Double = -10.0
        private set

    /**
     * Takes ownership of [image] and always closes it. Silently drops the frame
     * when a detection is still running or when nothing is in front of the camera.
     */
    fun process(image: Image, timestampS: Double) {
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
        detector.process(input)
            .addOnSuccessListener { faces ->
                val largest = faces.maxByOrNull { it.boundingBox.width() * it.boundingBox.height() }
                if (largest != null) {
                    val bounds = largest.boundingBox
                    latestBox = FollowController.boxFromPixels(
                        leftPx = bounds.left.toDouble(),
                        topPx = bounds.top.toDouble(),
                        rightPx = bounds.right.toDouble(),
                        bottomPx = bounds.bottom.toDouble(),
                        frameWidth = width.toDouble(),
                        frameHeight = height.toDouble(),
                    )
                    latestAtS = timestampS
                }
            }
            .addOnFailureListener { error -> Log.w(TAG, "face detection failed", error) }
            .addOnCompleteListener {
                busy.set(false)
                image.close()
            }
    }

    fun close() {
        runCatching { detector.close() }
        latestBox = null
        latestAtS = -10.0
    }

    private companion object {
        const val TAG = "PersonBoxDetector"
    }
}
