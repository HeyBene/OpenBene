package com.openbene.anchornav.nav

import java.util.PriorityQueue

data class RouteLeg(
    val edge: Edge,
    val fromId: String,
    val toId: String,
    val path: List<Pose2D>,
) {
    val distanceM: Double
        get() {
            var total = 0.0
            for (index in 0 until path.size - 1) {
                total += path[index].distanceTo(path[index + 1])
            }
            return total
        }
}

data class Route(
    val startLocationId: String,
    val destinationLocationId: String,
    val room: Room,
    val legs: List<RouteLeg>,
    val polyline: List<Pose2D>,
    val totalDistanceM: Double,
) {
    fun locationSequence(): List<String> = listOf(startLocationId) + legs.map { it.toId }
}

/** Dijkstra routing over the demo map graph, mirroring the Python router. */
class Router(private val mapData: MapData) {

    fun routeToRoom(startLocationId: String, roomName: String): Route? =
        mapData.roomsNamed(roomName)
            .mapNotNull { routeToLocation(startLocationId, it.locationId, it) }
            .minByOrNull { it.totalDistanceM }

    fun routeToLocation(startLocationId: String, destinationLocationId: String, room: Room? = null): Route? {
        require(mapData.hasLocation(startLocationId)) { "unknown start location " + startLocationId }
        require(mapData.hasLocation(destinationLocationId)) { "unknown destination " + destinationLocationId }

        val resolvedRoom = room ?: Room(
            id = destinationLocationId,
            name = mapData.location(destinationLocationId).name,
            locationId = destinationLocationId,
        )
        if (startLocationId == destinationLocationId) {
            return Route(
                startLocationId = startLocationId,
                destinationLocationId = destinationLocationId,
                room = resolvedRoom,
                legs = emptyList(),
                polyline = listOf(mapData.location(startLocationId).pose),
                totalDistanceM = 0.0,
            )
        }

        val dijkstra = dijkstra(startLocationId)
        val previous = dijkstra.first
        val distance = dijkstra.second
        if (!distance.containsKey(destinationLocationId)) return null

        val locationIds = ArrayDeque<String>()
        var cursor = destinationLocationId
        locationIds.addFirst(cursor)
        while (cursor != startLocationId) {
            cursor = previous[cursor] ?: return null
            locationIds.addFirst(cursor)
        }
        val ordered = locationIds.toList()

        val legs = ordered.zipWithNext().map { pair ->
            val fromId = pair.first
            val toId = pair.second
            val edge = edgeBetween(fromId, toId) ?: error("no edge between " + fromId + " and " + toId)
            RouteLeg(edge = edge, fromId = fromId, toId = toId, path = edge.pathFrom(fromId))
        }

        val polyline = joinPolyline(legs)
        var total = 0.0
        for (index in 0 until polyline.size - 1) {
            total += polyline[index].distanceTo(polyline[index + 1])
        }
        return Route(
            startLocationId = startLocationId,
            destinationLocationId = destinationLocationId,
            room = resolvedRoom,
            legs = legs,
            polyline = polyline,
            totalDistanceM = total,
        )
    }

    private fun dijkstra(startLocationId: String): Pair<Map<String, String>, Map<String, Double>> {
        val distance = mutableMapOf(startLocationId to 0.0)
        val previous = mutableMapOf<String, String>()
        val queue = PriorityQueue(compareBy<Pair<Double, String>> { it.first })
        queue.add(0.0 to startLocationId)
        while (queue.isNotEmpty()) {
            val entry = queue.poll()
            val currentDistance = entry.first
            val current = entry.second
            if (currentDistance > (distance[current] ?: Double.MAX_VALUE)) continue
            mapData.edgesFrom(current).forEach { edge ->
                val neighbour = edge.otherEnd(current)
                val candidate = currentDistance + edge.distanceM()
                if (candidate < (distance[neighbour] ?: Double.MAX_VALUE)) {
                    distance[neighbour] = candidate
                    previous[neighbour] = current
                    queue.add(candidate to neighbour)
                }
            }
        }
        return previous to distance
    }

    private fun edgeBetween(fromId: String, toId: String): Edge? =
        mapData.edgesFrom(fromId).firstOrNull { it.otherEnd(fromId) == toId }

    private fun joinPolyline(legs: List<RouteLeg>): List<Pose2D> {
        val points = mutableListOf<Pose2D>()
        legs.forEach { leg ->
            var legPoints = leg.path
            if (points.isNotEmpty() && points.last().distanceTo(legPoints.first()) < 1e-6) {
                legPoints = legPoints.drop(1)
            }
            points.addAll(legPoints)
        }
        return points
    }
}
