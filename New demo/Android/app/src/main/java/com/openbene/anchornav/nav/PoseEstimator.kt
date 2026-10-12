package com.openbene.anchornav.nav

/**
 * One AR frame in which a marker was visible. Both poses are planar projections
 * of the AR session poses: x/y is the horizontal position and yaw is the
 * rotation around the gravity axis.
 */
data class ArObservation(
    val markerId: String,
    val markerInAr: Pose2D,
    val deviceInAr: Pose2D,
    val timestampS: Double = 0.0,
)

/**
 * Robot pose estimation: AR anchor alignment plus wheel-odometry dead reckoning.
 * Mirrors openbene_nav.pose.PoseEstimator.
 */
class PoseEstimator(
    private val mapData: MapData,
    private val wheelBaseM: Double = 0.30,
    private val wheelRadiusM: Double = 0.0325,
) {
    var aligned: Boolean = false
        private set
    var mapFromAr: Pose2D? = null
        private set
    var pose: Pose2D? = null
    var lastMarkerId: String? = null
        private set
    var driftM: Double = 0.0
        private set
    var arUpdates: Int = 0
        private set
    var odometryUpdates: Int = 0
        private set

    fun align(observation: ArObservation): Pose2D {
        val marker = mapData.marker(observation.markerId)
        val transform = marker.pose.compose(observation.markerInAr.inverse())
        mapFromAr = transform
        aligned = true
        lastMarkerId = observation.markerId
        val updated = transform.compose(observation.deviceInAr)
        pose = updated
        driftM = 0.0
        arUpdates += 1
        return updated
    }

    fun updateFromAr(deviceInAr: Pose2D): Pose2D? {
        if (!aligned) return null
        val transform = mapFromAr ?: return null
        val updated = transform.compose(deviceInAr)
        pose = updated
        driftM = 0.0
        arUpdates += 1
        return updated
    }

    fun integrateOdometry(rpmLeft: Double, rpmRight: Double, dtS: Double): Pose2D? {
        val current = pose ?: return null
        if (dtS <= 0.0) return current
        val circumference = 2.0 * Math.PI * wheelRadiusM
        val vLeft = rpmLeft / 60.0 * circumference
        val vRight = rpmRight / 60.0 * circumference
        val linear = 0.5 * (vLeft + vRight)
        val angular = (vRight - vLeft) / wheelBaseM
        val moved = current.translated(linear * dtS)
        val updated = Pose2D(moved.x, moved.y, Pose2D.wrapRad(current.yawRad + angular * dtS))
        pose = updated
        driftM += Math.abs(linear * dtS)
        odometryUpdates += 1
        return updated
    }

    fun requirePose(): Pose2D =
        pose ?: throw IllegalStateException("pose is not known yet: align on a marker first")

    fun reset() {
        aligned = false
        mapFromAr = null
        pose = null
        lastMarkerId = null
        driftM = 0.0
    }
}
