package io.openbene.zenoh.capture

import android.hardware.camera2.CameraCharacteristics
import android.util.Size

/**
 * Pinhole intrinsics in pixels, expressed for one specific capture size.
 *
 * Tier C (no ARCore) reads these from Camera2 so the PC still gets a calibrated
 * stream even though no camera pose is available.
 */
data class CameraIntrinsics(
    val fx: Double,
    val fy: Double,
    val cx: Double,
    val cy: Double,
    val width: Int,
    val height: Int,
    val source: String,
) {
    fun scaledTo(targetWidth: Int, targetHeight: Int): CameraIntrinsics {
        if (targetWidth == width && targetHeight == height) return this
        val scaleX = targetWidth.toDouble() / width
        val scaleY = targetHeight.toDouble() / height
        return copy(
            fx = fx * scaleX,
            fy = fy * scaleY,
            cx = cx * scaleX,
            cy = cy * scaleY,
            width = targetWidth,
            height = targetHeight,
        )
    }

    companion object {
        /**
         * Prefers the factory calibration, then falls back to focal length plus
         * physical sensor size, then to a 60 degree horizontal field of view.
         */
        fun fromCharacteristics(
            characteristics: CameraCharacteristics,
            targetWidth: Int,
            targetHeight: Int,
        ): CameraIntrinsics? {
            val sensor = characteristics.get(CameraCharacteristics.SENSOR_INFO_PIXEL_ARRAY_SIZE)
                ?: Size(targetWidth, targetHeight)
            val base = fromSensor(characteristics, sensor) ?: guessed(targetWidth, targetHeight)
            return base.scaledTo(targetWidth, targetHeight)
        }

        private fun fromSensor(
            characteristics: CameraCharacteristics,
            sensor: Size,
        ): CameraIntrinsics? {
            if (sensor.width <= 0 || sensor.height <= 0) return null
            val calibration = characteristics.get(CameraCharacteristics.LENS_INTRINSIC_CALIBRATION)
            if (calibration != null && calibration.size >= 4 && calibration[0] > 0f && calibration[1] > 0f) {
                return CameraIntrinsics(
                    fx = calibration[0].toDouble(),
                    fy = calibration[1].toDouble(),
                    cx = calibration[2].toDouble(),
                    cy = calibration[3].toDouble(),
                    width = sensor.width,
                    height = sensor.height,
                    source = "camera2_calibration",
                )
            }

            val focal = characteristics.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                ?.firstOrNull() ?: return null
            val physical = characteristics.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
                ?: return null
            if (physical.width <= 0f || physical.height <= 0f) return null
            return CameraIntrinsics(
                fx = focal.toDouble() / physical.width * sensor.width,
                fy = focal.toDouble() / physical.height * sensor.height,
                cx = sensor.width / 2.0,
                cy = sensor.height / 2.0,
                width = sensor.width,
                height = sensor.height,
                source = "camera2_focal_length",
            )
        }

        private fun guessed(width: Int, height: Int): CameraIntrinsics {
            // 60 degree horizontal FOV keeps the metadata usable when a vendor
            // hides both calibration and physical size.
            val fx = width / (2.0 * kotlin.math.tan(Math.toRadians(30.0)))
            return CameraIntrinsics(
                fx = fx,
                fy = fx,
                cx = width / 2.0,
                cy = height / 2.0,
                width = width,
                height = height,
                source = "assumed_60deg",
            )
        }
    }
}
