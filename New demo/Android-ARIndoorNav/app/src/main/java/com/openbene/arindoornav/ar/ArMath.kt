package com.openbene.arindoornav.ar

import com.google.ar.core.Pose
import kotlin.math.atan2
import kotlin.math.hypot

/**
 * Planar pose in the AR world frame, gravity aligned: x/y are the horizontal
 * position (x = ARCore world x, y = -ARCore world z) and yaw is measured from +x
 * around the world up axis, so a positive heading error means "turn left".
 */
data class Planar(val x: Double, val y: Double, val yawRad: Double) {

    fun distanceTo(other: Planar): Double = hypot(other.x - x, other.y - y)

    fun bearingTo(other: Planar): Double = atan2(other.y - y, other.x - x)

    fun headingErrorTo(other: Planar): Double = wrapRad(bearingTo(other) - yawRad)

    companion object {
        fun wrapRad(angleRad: Double): Double {
            var wrapped = (angleRad + Math.PI) % (2.0 * Math.PI)
            if (wrapped <= 0.0) wrapped += 2.0 * Math.PI
            return wrapped - Math.PI
        }
    }
}

object ArMath {

    /** Column major 4x4 matrix product, the layout ARCore hands out. */
    fun multiply(a: FloatArray, b: FloatArray): FloatArray {
        val out = FloatArray(16)
        for (column in 0 until 4) {
            for (row in 0 until 4) {
                var sum = 0.0f
                for (k in 0 until 4) sum += a[k * 4 + row] * b[column * 4 + k]
                out[column * 4 + row] = sum
            }
        }
        return out
    }

    /**
     * Projects a world point with the view projection matrix. Returns false when
     * the point is behind the camera; [out] then holds the pixel position and the
     * depth of the point.
     */
    fun project(
        viewProjection: FloatArray,
        point: FloatArray,
        width: Int,
        height: Int,
        out: FloatArray,
    ): Boolean {
        val x = viewProjection[0] * point[0] + viewProjection[4] * point[1] +
            viewProjection[8] * point[2] + viewProjection[12]
        val y = viewProjection[1] * point[0] + viewProjection[5] * point[1] +
            viewProjection[9] * point[2] + viewProjection[13]
        val w = viewProjection[3] * point[0] + viewProjection[7] * point[1] +
            viewProjection[11] * point[2] + viewProjection[15]
        if (w <= 1e-4f) return false
        out[0] = (x / w * 0.5f + 0.5f) * width
        out[1] = (1.0f - (y / w * 0.5f + 0.5f)) * height
        out[2] = w
        return true
    }

    /** Focal length in pixels, used to size the spheres like real 5 cm balls. */
    fun focalPixels(projection: FloatArray, viewportHeight: Int): Float =
        projection[5] * 0.5f * viewportHeight

    /** Planar pose of an ARCore pose: horizontal position plus the heading of the view axis. */
    fun planarOf(pose: Pose): Planar {
        val translation = pose.translation
        val forward = pose.rotateVector(floatArrayOf(0f, 0f, -1f))
        val horizontal = hypot(forward[0].toDouble(), forward[2].toDouble())
        val yaw = if (horizontal < 1e-6) {
            0.0
        } else {
            atan2(-forward[2].toDouble(), forward[0].toDouble())
        }
        return Planar(translation[0].toDouble(), -translation[2].toDouble(), yaw)
    }

    /** Planar pose of a point in the AR world; the heading is only used for the UI. */
    fun planarOfPoint(point: FloatArray, yawRad: Double = 0.0): Planar =
        Planar(point[0].toDouble(), -point[2].toDouble(), yawRad)
}
