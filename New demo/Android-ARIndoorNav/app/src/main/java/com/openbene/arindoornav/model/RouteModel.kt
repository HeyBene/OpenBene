package com.openbene.arindoornav.model

import org.json.JSONArray
import org.json.JSONObject

/** The three node types of the original ARIndoorNav chain. */
const val TYPE_START = "start"
const val TYPE_INTERMEDIATE = "intermediate"
const val TYPE_DESTINATION = "destination"

/**
 * One node of a recorded chain, exactly as the original ARIndoorNav stored it:
 * the offset is the displacement from the previous node (or from the anchor sheet
 * for the first node) in the frame the AR session had while the node was
 * recorded. The original never stored an orientation, an image or a timestamp.
 */
data class RouteNode(
    val type: String,
    val xOffset: Double,
    val yOffset: Double,
    val zOffset: Double,
)

/** One route: the destination name, the sheet it was recorded on, and its chain. */
data class StoredRoute(
    val destination: String,
    val beaconName: String,
    val nodes: List<RouteNode>,
) {
    val nodeCount: Int get() = nodes.size

    /** Horizontal length of the chain, shown in the route list. */
    fun pathLengthM(): Double {
        var total = 0.0
        for (node in nodes) total += Math.hypot(node.xOffset, node.zOffset)
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
                    .put("z_offset", node.zOffset),
            )
        }
        return JSONObject()
            .put("beacon_name", beaconName)
            .put("destination", destination)
            .put("node_count", nodes.size)
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
                    ),
                )
            }
            return StoredRoute(
                destination = json.optString("destination", name),
                beaconName = json.optString("beacon_name", ""),
                nodes = nodes,
            )
        }
    }
}

/**
 * Reads and writes the JSON the original app kept in Firebase, so a record
 * exported from the original database can be dropped into this app unchanged.
 */
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
