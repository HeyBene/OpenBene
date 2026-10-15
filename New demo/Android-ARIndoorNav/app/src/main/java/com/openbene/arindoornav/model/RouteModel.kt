package com.openbene.arindoornav.model

import org.json.JSONArray
import org.json.JSONObject
import com.openbene.arindoornav.ar.Planar
import com.openbene.arindoornav.nav.NavPoint
import kotlin.math.atan2

/** The three node types of the original ARIndoorNav chain. */
const val TYPE_START = "start"
const val TYPE_INTERMEDIATE = "intermediate"
const val TYPE_DESTINATION = "destination"

/** Anchor-local incremental position, captured camera yaw and display name. */
data class RouteNode(
    val type: String,
    val xOffset: Double,
    val yOffset: Double,
    val zOffset: Double,
    val yawRad: Double? = null,
    val name: String = "",
)

/** One route: the destination name, the sheet it was recorded on, and its chain. */
data class StoredRoute(
    val destination: String,
    val beaconName: String,
    val nodes: List<RouteNode>,
    val anchorWidthM: Float = 0.2f,
) {
    val nodeCount: Int get() = nodes.size

    fun navPoints(): List<NavPoint> {
        var x = 0.0; var z = 0.0
        val positions = nodes.map { x += it.xOffset; z += it.zOffset; Planar(x, -z, 0.0) }
        return nodes.mapIndexed { index, node ->
            val current = positions[index]
            val from = if (index < nodes.lastIndex) current else positions.getOrElse(index - 1) { current }
            val to = positions.getOrElse(index + 1) { current }
            val yaw = node.yawRad ?: atan2(to.y - from.y, to.x - from.x)
            NavPoint(node.name.ifBlank { if (index == 0) "起点" else "节点 $index" }, current.copy(yawRad = yaw))
        }
    }

    /** Horizontal length of the chain, shown in the route list. */
    fun pathLengthM(): Double {
        var total = 0.0
        for (node in nodes.drop(1)) total += Math.hypot(node.xOffset, node.zOffset)
        return total
    }

    fun toJson(): JSONObject {
        val index = JSONArray()
        for (node in nodes) {
            index.put(
                JSONObject()
                    .put("type", node.type)
                    .put("x_offset", node.xOffset)
                    .put("y_offset", node.yOffset)
                    .put("z_offset", node.zOffset)
                    .put("yaw_rad", node.yawRad)
                    .put("name", node.name),
            )
        }
        return JSONObject()
            .put("beacon_name", beaconName)
            .put("destination", destination)
            .put("node_count", nodes.size)
            .put("anchor_width_m", anchorWidthM.toDouble())
            .put("version", 2)
            .put("nodes", JSONObject().put("index", index))
    }

    companion object {
        fun fromJson(name: String, json: JSONObject): StoredRoute {
            val index = json.optJSONObject("nodes")?.optJSONArray("index") ?: JSONArray()
            val nodes = ArrayList<RouteNode>(index.length())
            for (position in 0 until index.length()) {
                val item = index.optJSONObject(position) ?: continue
                nodes.add(
                    RouteNode(
                        type = item.optString("type", TYPE_INTERMEDIATE),
                        xOffset = item.optDouble("x_offset", 0.0),
                        yOffset = item.optDouble("y_offset", 0.0),
                        zOffset = item.optDouble("z_offset", 0.0),
                        yawRad = if (item.has("yaw_rad") && !item.isNull("yaw_rad")) item.getDouble("yaw_rad") else null,
                        name = item.optString("name", ""),
                    ),
                )
            }
            return StoredRoute(
                destination = json.optString("destination", name),
                beaconName = json.optString("beacon_name", ""),
                nodes = nodes,
                anchorWidthM = json.optDouble("anchor_width_m",
                    when (json.optString("beacon_name")) { "pi" -> 0.0762; "1" -> 0.127; else -> 0.2 }).toFloat(),
            )
        }
    }
}

/** Version 2 local JSON, with compatibility for older position-only captures. */
object RouteCodec {

    fun encode(routes: List<StoredRoute>): String {
        val destinations = JSONObject()
        for (route in routes) destinations.put(route.destination, route.toJson())
        return JSONObject().put("destination", destinations).toString(2)
    }

    fun decode(text: String): List<StoredRoute> {
        if (text.isBlank()) return emptyList()
        val root = JSONObject(text)
        // The original export nests the routes under "destination"; a bare map of
        // name to record is accepted too, which is easier to write by hand.
        val destinations = root.optJSONObject("destination") ?: root
        return destinations.keys().asSequence().mapNotNull { name ->
            val json = destinations.optJSONObject(name) ?: return@mapNotNull null
            StoredRoute.fromJson(name, json)
        }.toList()
    }
}
