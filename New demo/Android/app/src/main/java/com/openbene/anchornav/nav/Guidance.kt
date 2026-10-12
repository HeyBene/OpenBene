package com.openbene.anchornav.nav

import java.util.Locale

enum class StepKind { FORWARD, TURN_LEFT, TURN_RIGHT, TURN_BACK, ARRIVE }

data class GuidanceStep(
    val kind: StepKind,
    val distanceM: Double,
    val atLocationId: String?,
    val atLocationName: String?,
    val message: String,
)

/** Turn-by-turn instructions derived from the route geometry. */
class GuidanceBuilder(private val mapData: MapData, private val turnThresholdDeg: Double = 25.0) {

    fun build(route: Route): List<GuidanceStep> {
        val polyline = route.polyline
        if (polyline.size < 2) {
            val destination = mapData.location(route.destinationLocationId)
            return listOf(
                GuidanceStep(
                    kind = StepKind.ARRIVE,
                    distanceM = 0.0,
                    atLocationId = destination.id,
                    atLocationName = destination.name,
                    message = "Already at " + route.room.name,
                )
            )
        }

        val steps = mutableListOf<GuidanceStep>()
        var pendingDistance = 0.0
        var heading: Double? = null

        for (index in 0 until polyline.size - 1) {
            val start = polyline[index]
            val end = polyline[index + 1]
            val segmentHeading = start.bearingTo(end)
            val segmentLength = start.distanceTo(end)
            val previousHeading = heading
            if (previousHeading != null) {
                val turn = Pose2D.wrapDeg(Math.toDegrees(segmentHeading - previousHeading))
                if (Math.abs(turn) >= turnThresholdDeg) {
                    val kind = turnKind(turn)
                    val location = closestLocation(start)
                    steps.add(
                        GuidanceStep(
                            kind = kind,
                            distanceM = pendingDistance,
                            atLocationId = location?.id,
                            atLocationName = location?.name,
                            message = turnMessage(kind, location?.name, pendingDistance),
                        )
                    )
                    pendingDistance = 0.0
                }
            }
            pendingDistance += segmentLength
            heading = segmentHeading
        }

        val destination = mapData.location(route.destinationLocationId)
        steps.add(
            GuidanceStep(
                kind = StepKind.ARRIVE,
                distanceM = pendingDistance,
                atLocationId = destination.id,
                atLocationName = destination.name,
                message = String.format(
                    Locale.US,
                    "Forward %.1f m, then arrive at %s",
                    pendingDistance,
                    route.room.name,
                ),
            )
        )
        return steps
    }

    private fun turnKind(turnDeg: Double): StepKind = when {
        Math.abs(turnDeg) >= 150.0 -> StepKind.TURN_BACK
        turnDeg > 0 -> StepKind.TURN_LEFT
        else -> StepKind.TURN_RIGHT
    }

    private fun turnMessage(kind: StepKind, locationName: String?, distanceM: Double): String {
        val where = if (locationName != null) " at " + locationName else ""
        return when (kind) {
            StepKind.TURN_LEFT -> String.format(Locale.US, "Forward %.1f m, then turn left%s", distanceM, where)
            StepKind.TURN_RIGHT -> String.format(Locale.US, "Forward %.1f m, then turn right%s", distanceM, where)
            StepKind.TURN_BACK -> String.format(Locale.US, "Forward %.1f m, then turn back%s", distanceM, where)
            StepKind.FORWARD -> String.format(Locale.US, "Forward %.1f m", distanceM)
            StepKind.ARRIVE -> "Arrive"
        }
    }

    private fun closestLocation(pose: Pose2D): NavLocation? {
        val nearest = mapData.locations.minByOrNull { it.pose.distanceTo(pose) } ?: return null
        return if (nearest.pose.distanceTo(pose) > 1.5) null else nearest
    }
}
