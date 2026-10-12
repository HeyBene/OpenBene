package com.openbene.anchornav.ar

import com.google.ar.core.Pose
import com.openbene.anchornav.nav.Pose2D
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin
import kotlin.math.sqrt

/** Pinhole intrinsics of one camera image, in pixels. */
data class CameraIntrinsics(
    val fx: Double,
    val fy: Double,
    val cx: Double,
    val cy: Double,
    val width: Int,
    val height: Int,
) {
    companion object {
        /** Used when the AR session cannot report the real intrinsics. */
        fun fromHorizontalFov(width: Int, height: Int, hfovDeg: Double = 60.0): CameraIntrinsics {
            val focal = 0.5 * width / kotlin.math.tan(Math.toRadians(hfovDeg) * 0.5)
            return CameraIntrinsics(focal, focal, 0.5 * width, 0.5 * height, width, height)
        }
    }
}

/**
 * A camera pose in the AR world, kept independent of ARCore so the geometry can
 * be reasoned about (and unit tested) on its own.
 */
class RigidTransform(val x: Double, val y: Double, val z: Double, val rotation: DoubleArray) {
    fun rotate(vector: DoubleArray): DoubleArray {
        val r = rotation
        return doubleArrayOf(
            r[0] * vector[0] + r[1] * vector[1] + r[2] * vector[2],
            r[3] * vector[0] + r[4] * vector[1] + r[5] * vector[2],
            r[6] * vector[0] + r[7] * vector[1] + r[8] * vector[2],
        )
    }

    fun transformPoint(point: DoubleArray): DoubleArray {
        val rotated = rotate(point)
        return doubleArrayOf(rotated[0] + x, rotated[1] + y, rotated[2] + z)
    }

    companion object {
        fun fromPose(pose: Pose): RigidTransform {
            val t = pose.translation
            val q = pose.rotationQuaternion
            return RigidTransform(t[0].toDouble(), t[1].toDouble(), t[2].toDouble(), rotationFromQuaternion(q))
        }

        /** Quaternion (x, y, z, w) to a row major rotation matrix. */
        fun rotationFromQuaternion(q: FloatArray): DoubleArray {
            val x = q[0].toDouble()
            val y = q[1].toDouble()
            val z = q[2].toDouble()
            val w = q[3].toDouble()
            return doubleArrayOf(
                1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - z * w), 2.0 * (x * z + y * w),
                2.0 * (x * y + z * w), 1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - x * w),
                2.0 * (x * z - y * w), 2.0 * (y * z + x * w), 1.0 - 2.0 * (x * x + y * y),
            )
        }
    }
}

/**
 * Marker pose from camera pixels. Port of shared/navcore/openbene_nav/marker_math.py,
 * which is covered by the Python round trip tests; keep the two in step.
 *
 * The image tracker gives an exact marker pose on its own. This is the fallback
 * used when only a QR detection is available: corner pixels become camera rays,
 * the rays are rotated into the AR world and cut the floor plane, and the
 * resulting quad gives the marker centre and the direction of the printed arrow.
 * The planar frame is x = world x, y = -world z, which keeps ARCore rotations
 * about the gravity axis as plain 2D rotations.
 */
object MarkerGeometry {
    /** Printed size of the code block, quiet zone included, as drawn by make_markers.py. */
    const val DEFAULT_CODE_QUAD_SIZE_M = 0.12

    /** Phone on the robot: used only when neither a plane nor a code size is available. */
    const val DEFAULT_CAMERA_HEIGHT_M = 0.40

    /** The printed code sits 3.3 mm above the sheet centre along the arrow. */
    const val CODE_CENTRE_OFFSET_ALONG_Y_M = -0.0033

    const val YAW_GATE_DEG = 60.0

    fun pixelRay(intrinsics: CameraIntrinsics, u: Double, v: Double): DoubleArray {
        val dx = (u - intrinsics.cx) / intrinsics.fx
        val dy = -(v - intrinsics.cy) / intrinsics.fy
        val length = sqrt(dx * dx + dy * dy + 1.0)
        return doubleArrayOf(dx / length, dy / length, -1.0 / length)
    }

    fun intersectFloor(origin: DoubleArray, direction: DoubleArray, floorY: Double): DoubleArray? {
        if (direction[1] > -1e-3) return null
        val distance = (floorY - origin[1]) / direction[1]
        if (distance <= 0.0) return null
        return doubleArrayOf(
            origin[0] + distance * direction[0],
            origin[1] + distance * direction[1],
            origin[2] + distance * direction[2],
        )
    }

    fun quadOnFloor(
        corners: List<DoubleArray>,
        intrinsics: CameraIntrinsics,
        cameraPose: RigidTransform,
        floorY: Double,
    ): List<DoubleArray>? {
        val origin = doubleArrayOf(cameraPose.x, cameraPose.y, cameraPose.z)
        val quad = ArrayList<DoubleArray>(corners.size)
        for (corner in corners) {
            val ray = cameraPose.rotate(pixelRay(intrinsics, corner[0], corner[1]))
            val hit = intersectFloor(origin, ray, floorY) ?: return null
            quad.add(hit)
        }
        return quad
    }

    fun meanEdgeLength(quad: List<DoubleArray>): Double {
        if (quad.size < 2) return 0.0
        var total = 0.0
        for (index in quad.indices) {
            val first = quad[index]
            val second = quad[(index + 1) % quad.size]
            total += distance(first, second)
        }
        return total / quad.size
    }

    /** Heading of a world direction in the AR plane frame (x = world x, y = -world z). */
    fun planarYawOfDirection(direction: DoubleArray): Double = atan2(-direction[2], direction[0])

    fun planarPoseOfPoint(position: DoubleArray, yawRad: Double): Pose2D =
        Pose2D(position[0], -position[2], Pose2D.wrapRad(yawRad))

    /** Planar pose of the camera: position plus the heading of its view axis. */
    fun deviceInAr(cameraPose: RigidTransform): Pose2D {
        val forward = cameraPose.rotate(doubleArrayOf(0.0, 0.0, -1.0))
        val horizontal = hypot(forward[0], forward[2])
        val yaw = if (horizontal < 1e-6) 0.0 else planarYawOfDirection(doubleArrayOf(forward[0], 0.0, forward[2]))
        return planarPoseOfPoint(doubleArrayOf(cameraPose.x, cameraPose.y, cameraPose.z), yaw)
    }

    /**
     * Planar pose of an ARCore augmented image. ARCore reports the sheet centre
     * with the print in the pose's local X-Z plane: +X runs from the left edge of
     * the print to its right edge, +Y is the sheet normal and +Z runs from the top
     * edge to the bottom edge, so the printed arrow (the image +y axis) is the
     * local -Z axis.
     */
    fun markerInArFromImagePose(imagePose: RigidTransform): Pose2D {
        val arrow = imagePose.rotate(doubleArrayOf(0.0, 0.0, -1.0))
        val horizontal = hypot(arrow[0], arrow[2])
        val yaw = if (horizontal < 1e-6) 0.0 else planarYawOfDirection(doubleArrayOf(arrow[0], 0.0, arrow[2]))
        return planarPoseOfPoint(doubleArrayOf(imagePose.x, imagePose.y, imagePose.z), yaw)
    }

    /**
     * Camera height above the floor, solved from the printed size of the code:
     * intersecting the corner rays with a plane at a guessed height scales the
     * quad linearly, so one measurement corrects the guess.
     */
    fun solveCameraHeight(
        corners: List<DoubleArray>,
        intrinsics: CameraIntrinsics,
        cameraPose: RigidTransform,
        quadSizeM: Double,
        assumedHeightM: Double = DEFAULT_CAMERA_HEIGHT_M,
        iterations: Int = 3,
    ): Double? {
        var height = assumedHeightM
        repeat(iterations.coerceAtLeast(1)) {
            val quad = quadOnFloor(corners, intrinsics, cameraPose, cameraPose.y - height) ?: return null
            val measured = meanEdgeLength(quad)
            if (measured <= 1e-6) return null
            height *= quadSizeM / measured
            if (height <= 0.02 || height > 3.0) return null
        }
        return height
    }

    /**
     * Marker pose in the AR plane frame from four detected corner pixels.
     *
     * @param corners clockwise from the code's own top left corner, as ML Kit reports it.
     * @param floorY floor height in the AR world, when a plane is available.
     * @param ordered false when the corner order cannot be trusted; the heading then comes
     *   from [deviceYawRad], which is sound because the executor turns the robot to face the
     *   marker before it scans.
     */
    fun markerPoseFromQuad(
        corners: List<DoubleArray>,
        intrinsics: CameraIntrinsics,
        cameraPose: RigidTransform,
        floorY: Double? = null,
        quadSizeM: Double = DEFAULT_CODE_QUAD_SIZE_M,
        assumedHeightM: Double = DEFAULT_CAMERA_HEIGHT_M,
        centreOffsetAlongYM: Double = CODE_CENTRE_OFFSET_ALONG_Y_M,
        ordered: Boolean = true,
        deviceYawRad: Double? = null,
        yawGateDeg: Double = YAW_GATE_DEG,
    ): Pose2D? {
        if (corners.size != 4) return null

        val resolvedFloorY = floorY
            ?: cameraPose.y - (solveCameraHeight(corners, intrinsics, cameraPose, quadSizeM, assumedHeightM)
                ?: assumedHeightM)

        val quad = quadOnFloor(corners, intrinsics, cameraPose, resolvedFloorY) ?: return null

        var centreX = 0.0
        var centreY = 0.0
        var centreZ = 0.0
        for (point in quad) {
            centreX += point[0] / 4.0
            centreY += point[1] / 4.0
            centreZ += point[2] / 4.0
        }

        val yaw: Double
        if (ordered) {
            val topMid = midpoint(quad[0], quad[1])
            val bottomMid = midpoint(quad[3], quad[2])
            val upX = topMid[0] - bottomMid[0]
            val upZ = topMid[2] - bottomMid[2]
            if (hypot(upX, upZ) < 1e-6) return null
            val quadYaw = planarYawOfDirection(doubleArrayOf(upX, 0.0, upZ))
            yaw = if (deviceYawRad != null &&
                abs(Pose2D.wrapRad(quadYaw - deviceYawRad)) > Math.toRadians(yawGateDeg)
            ) {
                deviceYawRad
            } else {
                quadYaw
            }
        } else {
            yaw = deviceYawRad ?: return null
        }

        val shifted = doubleArrayOf(
            centreX + centreOffsetAlongYM * cos(yaw),
            centreY,
            centreZ - centreOffsetAlongYM * sin(yaw),
        )
        return planarPoseOfPoint(shifted, yaw)
    }

    private fun midpoint(first: DoubleArray, second: DoubleArray): DoubleArray = doubleArrayOf(
        (first[0] + second[0]) * 0.5,
        (first[1] + second[1]) * 0.5,
        (first[2] + second[2]) * 0.5,
    )

    private fun distance(first: DoubleArray, second: DoubleArray): Double = sqrt(
        (first[0] - second[0]) * (first[0] - second[0]) +
            (first[1] - second[1]) * (first[1] - second[1]) +
            (first[2] - second[2]) * (first[2] - second[2]),
    )
}
