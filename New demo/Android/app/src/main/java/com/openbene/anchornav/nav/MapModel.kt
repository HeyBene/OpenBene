package com.openbene.anchornav.nav

import org.json.JSONObject

/** A printed anchor sheet lying on the floor. */
data class Marker(
    val id: String,
    val kind: String,
    val payload: String,
    val arImage: String,
    val sizeM: Double,
    val pose: Pose2D,
)

data class NavLocation(
    val id: String,
    val name: String,
    val pose: Pose2D,
    val markerId: String?,
)

data class Edge(
    val id: String,
    val fromId: String,
    val toId: String,
    val path: List<Pose2D>,
    val bidirectional: Boolean,
    val direction: String,
) {
    fun distanceM(): Double {
        var total = 0.0
        for (index in 0 until path.size - 1) {
            total += path[index].distanceTo(path[index + 1])
        }
        return total
    }

    fun pathFrom(startLocationId: String): List<Pose2D> = when (startLocationId) {
        fromId -> path
        toId -> path.reversed()
        else -> throw IllegalArgumentException("$startLocationId is not part of edge $id")
    }

    fun otherEnd(locationId: String): String = when (locationId) {
        fromId -> toId
        toId -> fromId
        else -> throw IllegalArgumentException("$locationId is not part of edge $id")
    }
}

data class Room(val id: String, val name: String, val locationId: String)

/** Parsed demo map: markers, locations, edges and rooms. */
class MapData(
    val mapId: String,
    val name: String,
    val markers: List<Marker>,
    val locations: List<NavLocation>,
    val edges: List<Edge>,
    val rooms: List<Room>,
) {
    private val markersById = markers.associateBy { it.id }
    private val markersByPayload = markers.associateBy { it.payload }
    private val locationsById = locations.associateBy { it.id }
    private val roomsById = rooms.associateBy { it.id }
    private val adjacency: Map<String, List<Edge>> = mutableMapOf<String, MutableList<Edge>>().apply {
        locations.forEach { location -> put(location.id, mutableListOf()) }
        edges.forEach { edge ->
            getOrPut(edge.fromId) { mutableListOf() }.add(edge)
            if (edge.bidirectional) {
                getOrPut(edge.toId) { mutableListOf() }.add(edge)
            }
        }
    }

    fun marker(markerId: String): Marker =
        markersById[markerId] ?: throw IllegalArgumentException("unknown marker $markerId")

    fun markerForPayload(payload: String): Marker? = markersByPayload[payload.trim()]

    fun location(locationId: String): NavLocation =
        locationsById[locationId] ?: throw IllegalArgumentException("unknown location $locationId")

    fun room(roomId: String): Room =
        roomsById[roomId] ?: throw IllegalArgumentException("unknown room $roomId")

    fun roomsNamed(name: String): List<Room> =
        rooms.filter { it.name.equals(name.trim(), ignoreCase = true) }

    fun roomNames(): List<String> = rooms.map { it.name }.distinct().sorted()

    fun edgesFrom(locationId: String): List<Edge> = adjacency[locationId] ?: emptyList()

    fun hasLocation(locationId: String): Boolean = locationsById.containsKey(locationId)

    fun nearestLocation(pose: Pose2D): NavLocation =
        locations.minByOrNull { it.pose.distanceTo(pose) }
            ?: throw IllegalStateException("map has no locations")

    companion object {
        fun parse(json: String): MapData {
            val root = JSONObject(json)
            val markers = markersOf(root)
            val locations = locationsOf(root)
            val edges = edgesOf(root)
            val rooms = roomsOf(root)
            return MapData(
                mapId = root.optString("map_id", "map"),
                name = root.optString("name", root.optString("map_id", "map")),
                markers = markers,
                locations = locations,
                edges = edges,
                rooms = rooms,
            )
        }

        private fun markersOf(root: JSONObject): List<Marker> {
            val array = root.optJSONArray("markers") ?: return emptyList()
            return (0 until array.length()).map { index ->
                val item = array.getJSONObject(index)
                val id = item.getString("id")
                Marker(
                    id = id,
                    kind = item.optString("kind", "qr"),
                    payload = item.optString("payload", "openbene:" + id),
                    arImage = item.optString("ar_image", id),
                    sizeM = item.optDouble("size_m", 0.2),
                    pose = poseOf(item.getJSONObject("pose")),
                )
            }
        }

        private fun locationsOf(root: JSONObject): List<NavLocation> {
            val array = root.optJSONArray("locations") ?: return emptyList()
            return (0 until array.length()).map { index ->
                val item = array.getJSONObject(index)
                val id = item.getString("id")
                NavLocation(
                    id = id,
                    name = item.optString("name", id),
                    pose = poseOf(item.getJSONObject("pose")),
                    markerId = if (item.isNull("marker_id")) null else item.optString("marker_id"),
                )
            }
        }

        private fun edgesOf(root: JSONObject): List<Edge> {
            val array = root.optJSONArray("edges") ?: return emptyList()
            return (0 until array.length()).map { index ->
                val item = array.getJSONObject(index)
                val pathArray = item.getJSONArray("path")
                val path = (0 until pathArray.length()).map { pointIndex ->
                    poseOf(pathArray.getJSONObject(pointIndex))
                }
                val id = item.getString("id")
                require(path.size >= 2) { "edge " + id + " needs two path points" }
                Edge(
                    id = id,
                    fromId = item.getString("from"),
                    toId = item.getString("to"),
                    path = path,
                    bidirectional = item.optBoolean("bidirectional", true),
                    direction = item.optString("direction", "forward"),
                )
            }
        }

        private fun roomsOf(root: JSONObject): List<Room> {
            val array = root.optJSONArray("rooms") ?: return emptyList()
            return (0 until array.length()).map { index ->
                val item = array.getJSONObject(index)
                Room(
                    id = item.getString("id"),
                    name = item.getString("name"),
                    locationId = item.getString("location_id"),
                )
            }
        }

        private fun poseOf(json: JSONObject): Pose2D =
            Pose2D.fromDeg(json.optDouble("x", 0.0), json.optDouble("y", 0.0), json.optDouble("yaw_deg", 0.0))
    }
}
