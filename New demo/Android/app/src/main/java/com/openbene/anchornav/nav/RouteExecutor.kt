package com.openbene.anchornav.nav

import kotlin.math.abs
import kotlin.math.max
import java.util.Locale

enum class ExecutorState(val label: String) {
    IDLE("idle"),
    NEED_ANCHOR("need_anchor"),
    SCANNING("scanning"),
    DRIVING("driving"),
    ARRIVED("arrived"),
    BLOCKED("blocked"),
    FAILED("failed"),
}

data class ExecutorConfig(
    val waypointToleranceM: Double = 0.30,
    val arrivalToleranceM: Double = 0.40,
    val headingToleranceDeg: Double = 15.0,
    val cruiseSpeed: Double = 0.35,
    val turnSpeed: Double = 0.22,
    val steerGain: Double = 1.6,
    val obstacleStopCm: Double = 35.0,
    val obstacleClearCm: Double = 50.0,
    val reanchorAtWaypoints: Boolean = true,
    val reanchorDriftM: Double = 4.0,
    val markerScanRadiusM: Double = 1.0,
    val markerScanHeadingDeg: Double = 40.0,
    val holdTimeoutS: Double = 2.5,
    val allowScanRotation: Boolean = true,
    val scanSpeed: Double = 0.25,
    val scanTimeoutS: Double = 30.0,
)

data class ExecutorStatus(
    val state: ExecutorState,
    val message: String,
    val legIndex: Int,
    val pointIndex: Int,
    val target: Pose2D?,
    val distanceToTargetM: Double,
    val distanceRemainingM: Double,
    val pose: Pose2D?,
    val driftM: Double,
    val driftWarning: Boolean,
    val expectedMarkerId: String?,
    val usedMarkers: List<String>,
)

/**
 * Route execution state machine. Drives the OpenBot along the route polyline,
 * expects a marker fix during the approach of every anchored location, and
 * stops for obstacles reported by the firmware sonar.
 *
 * This mirrors openbene_nav.executor.RouteExecutor, which is covered by the
 * Python unit tests in shared/navcore/tests.
 */
class RouteExecutor(
    private val mapData: MapData,
    private val estimator: PoseEstimator,
    private val link: RobotLink,
    private val config: ExecutorConfig = ExecutorConfig(),
) {
    var route: Route? = null
        private set
    var state: ExecutorState = ExecutorState.IDLE
        private set
    var message: String = "idle"
        private set
    var legIndex: Int = 0
        private set
    var pointIndex: Int = 0
        private set
    var expectedMarkerId: String? = null
        private set
    val usedMarkers = mutableListOf<String>()

    private var legArrivalMarkerId: String? = null
    private var legMarkerFixed = false
    private var driftWarning = false
    private var scanStartedS: Double? = null
    private var lastOdometryS: Double? = null

    fun start(route: Route, startLocationId: String? = null) {
        this.route = route
        legIndex = 0
        pointIndex = 0
        usedMarkers.clear()
        scanStartedS = null
        lastOdometryS = null
        driftWarning = false
        beginLeg()
        if (estimator.aligned) {
            state = ExecutorState.DRIVING
            message = "route accepted"
            return
        }
        val location = mapData.location(startLocationId ?: route.startLocationId)
        requestAnchor(location.markerId, "scan marker of " + location.name)
    }

    fun stop() {
        link.stop()
        state = ExecutorState.IDLE
        message = "stopped"
    }

    fun tick(nowS: Double, dtS: Double): ExecutorStatus {
        val activeRoute = route
        if (activeRoute == null) {
            link.stop()
            return status()
        }

        integrateOdometry(nowS)

        if (link.telemetry.bumper != null) {
            link.stop()
            state = ExecutorState.FAILED
            message = "bumper collision: clear the robot and restart the route"
            return status()
        }

        if (obstacleAhead()) {
            link.stop()
            state = ExecutorState.BLOCKED
            message = String.format(Locale.US, "obstacle at %.0f cm", link.telemetry.sonarCm ?: 0.0)
            return status()
        }

        if (state == ExecutorState.BLOCKED) {
            message = "path clear, resuming"
            state = if (estimator.aligned) ExecutorState.DRIVING else ExecutorState.NEED_ANCHOR
        }

        if (state == ExecutorState.ARRIVED || state == ExecutorState.FAILED) {
            link.stop()
            return status()
        }

        if (!estimator.aligned || state == ExecutorState.NEED_ANCHOR || state == ExecutorState.SCANNING) {
            handleAnchorWait(nowS)
            return status()
        }

        if (estimator.driftM > config.reanchorDriftM) {
            val nearby = reachableMarker()
            if (nearby != null) {
                requestAnchor(
                    nearby.id,
                    String.format(
                        Locale.US,
                        "dead-reckoning drift %.1f m: re-localise on %s",
                        estimator.driftM,
                        nearby.id,
                    ),
                )
                handleAnchorWait(nowS)
                return status()
            }
            driftWarning = true
        }

        driveRoute(activeRoute)
        return status()
    }

    /** Called by the AR layer right after a successful marker alignment. */
    fun noteMarker(markerId: String) {
        if (!usedMarkers.contains(markerId)) usedMarkers.add(markerId)
        if (markerId == legArrivalMarkerId) legMarkerFixed = true

        if (state == ExecutorState.SCANNING) {
            if (markerId == expectedMarkerId) {
                legIndex += 1
                pointIndex = 0
                beginLeg()
                state = ExecutorState.DRIVING
                message = "re-localised on " + markerId
                scanStartedS = null
            }
            return
        }
        if (state == ExecutorState.NEED_ANCHOR) {
            state = ExecutorState.DRIVING
            message = "localised on " + markerId
            scanStartedS = null
        }
    }

    private fun beginLeg() {
        val activeRoute = route
        if (activeRoute == null || legIndex >= activeRoute.legs.size) {
            legArrivalMarkerId = null
            legMarkerFixed = false
            return
        }
        legArrivalMarkerId = mapData.location(activeRoute.legs[legIndex].toId).markerId
        legMarkerFixed = false
    }

    private fun driveRoute(activeRoute: Route) {
        if (legIndex >= activeRoute.legs.size) {
            finish(activeRoute)
            return
        }
        val leg = activeRoute.legs[legIndex]
        val target = leg.path[pointIndex]
        val pose = estimator.pose
        if (pose == null) {
            state = ExecutorState.NEED_ANCHOR
            return
        }
        val distance = pose.distanceTo(target)
        val lastPoint = pointIndex == leg.path.size - 1
        val lastLeg = legIndex == activeRoute.legs.size - 1
        val tolerance = if (lastPoint && lastLeg) config.arrivalToleranceM else config.waypointToleranceM

        if (distance <= tolerance) {
            if (!lastPoint) {
                pointIndex += 1
                return
            }
            if (!lastLeg) {
                advanceLeg(activeRoute)
                return
            }
            finish(activeRoute)
            return
        }

        state = ExecutorState.DRIVING
        message = String.format(Locale.US, "driving to waypoint %d, %.1f m", pointIndex, distance)
        steerTowards(target, pose)
    }

    private fun advanceLeg(activeRoute: Route) {
        val arrival = mapData.location(activeRoute.legs[legIndex].toId)
        if (config.reanchorAtWaypoints && arrival.markerId != null && !legMarkerFixed) {
            requestAnchor(arrival.markerId, "re-localise on marker of " + arrival.name)
            state = ExecutorState.SCANNING
            return
        }
        legIndex += 1
        pointIndex = 0
        beginLeg()
        state = ExecutorState.DRIVING
    }

    private fun finish(activeRoute: Route) {
        link.stop()
        state = ExecutorState.ARRIVED
        message = "arrived at " + activeRoute.room.name
    }

    private fun requestAnchor(markerId: String?, text: String) {
        link.stop()
        state = ExecutorState.NEED_ANCHOR
        expectedMarkerId = markerId
        message = text
        scanStartedS = null
    }

    private fun handleAnchorWait(nowS: Double) {
        if (expectedMarkerId == null) expectedMarkerId = nearestMarkerId()
        val wanted = expectedMarkerId
        if (wanted == null) {
            link.stop()
            state = ExecutorState.FAILED
            message = "no marker available to localise"
            return
        }
        if (scanStartedS == null) scanStartedS = nowS
        val elapsed = nowS - (scanStartedS ?: nowS)
        if (elapsed > config.scanTimeoutS) {
            link.stop()
            state = ExecutorState.FAILED
            message = String.format(Locale.US, "marker %s not found within %.0f s", wanted, config.scanTimeoutS)
            return
        }
        val holding = facingWantedMarker() && elapsed < config.holdTimeoutS
        when {
            holding -> {
                link.stop()
                message = "hold position, looking for marker " + wanted
            }
            config.allowScanRotation -> {
                link.drive(-config.scanSpeed, config.scanSpeed)
                message = "rotating to find marker " + wanted
            }
            else -> {
                link.stop()
                message = "waiting for marker " + wanted
            }
        }
    }

    private fun steerTowards(target: Pose2D, pose: Pose2D) {
        val error = pose.headingErrorTo(target)
        if (abs(error) > Math.toRadians(config.headingToleranceDeg)) {
            if (error > 0) link.drive(-config.turnSpeed, config.turnSpeed)
            else link.drive(config.turnSpeed, -config.turnSpeed)
            return
        }
        val steer = (config.steerGain * error).coerceIn(-1.0, 1.0)
        var left = config.cruiseSpeed * (1.0 - steer)
        var right = config.cruiseSpeed * (1.0 + steer)
        val scale = max(max(abs(left), abs(right)), 1e-6)
        if (scale > 1.0) {
            left /= scale
            right /= scale
        }
        link.drive(left, right)
    }

    private fun integrateOdometry(nowS: Double) {
        val last = lastOdometryS
        if (last == null) {
            lastOdometryS = nowS
            return
        }
        val elapsed = max(0.0, nowS - last)
        lastOdometryS = nowS
        estimator.integrateOdometry(link.telemetry.rpmLeft, link.telemetry.rpmRight, elapsed)
    }

    private fun obstacleAhead(): Boolean {
        val sonar = link.telemetry.sonarCm ?: return false
        return if (state == ExecutorState.BLOCKED) sonar <= config.obstacleClearCm
        else sonar <= config.obstacleStopCm
    }

    private fun markerPose(markerId: String?): Pose2D? {
        if (markerId == null) return null
        return mapData.markers.firstOrNull { it.id == markerId }?.pose
    }

    private fun facingWantedMarker(): Boolean {
        val pose = estimator.pose ?: return false
        val marker = markerPose(expectedMarkerId) ?: return false
        return abs(pose.headingErrorTo(marker)) <= Math.toRadians(config.markerScanHeadingDeg)
    }

    private fun reachableMarker(): Marker? {
        val pose = estimator.pose ?: return null
        return mapData.markers
            .filter { pose.distanceTo(it.pose) <= config.markerScanRadiusM }
            .minByOrNull { pose.distanceTo(it.pose) }
    }

    private fun nearestMarkerId(): String? {
        val pose = estimator.pose
        if (pose == null) return route?.let { mapData.location(it.startLocationId).markerId }
        return mapData.nearestLocation(pose).markerId
    }

    private fun remainingDistance(): Double {
        val activeRoute = route ?: return 0.0
        val pose = estimator.pose ?: return 0.0
        if (state == ExecutorState.ARRIVED) return 0.0
        var remaining = 0.0
        for (index in legIndex until activeRoute.legs.size) {
            val leg = activeRoute.legs[index]
            val startIndex = if (index == legIndex) pointIndex else 0
            var previous = if (index == legIndex) pose else leg.path[0]
            for (indexInLeg in startIndex until leg.path.size) {
                val point = leg.path[indexInLeg]
                remaining += previous.distanceTo(point)
                previous = point
            }
        }
        return remaining
    }

    private fun status(): ExecutorStatus {
        val pose = estimator.pose
        var target: Pose2D? = null
        var distanceToTarget = 0.0
        val activeRoute = route
        if (activeRoute != null && legIndex < activeRoute.legs.size) {
            val leg = activeRoute.legs[legIndex]
            if (pointIndex < leg.path.size) {
                target = leg.path[pointIndex]
                if (pose != null) distanceToTarget = pose.distanceTo(target)
            }
        }
        return ExecutorStatus(
            state = state,
            message = message,
            legIndex = legIndex,
            pointIndex = pointIndex,
            target = target,
            distanceToTargetM = distanceToTarget,
            distanceRemainingM = remainingDistance(),
            pose = pose,
            driftM = estimator.driftM,
            driftWarning = driftWarning,
            expectedMarkerId = expectedMarkerId,
            usedMarkers = usedMarkers.toList(),
        )
    }
}
