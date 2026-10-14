package com.openbene.arindoornav

import android.content.Context
import com.openbene.arindoornav.model.RouteCodec
import com.openbene.arindoornav.model.StoredRoute
import java.io.File

/**
 * Routes live in one JSON file inside the app sandbox. The file uses the schema of
 * the original ARIndoorNav Firebase database; the original asked a Node service
 * for it, which this demo does not need.
 */
class RouteStore(private val context: Context) {

    private val file: File get() = File(context.filesDir, FILE_NAME)

    fun location(): String = file.absolutePath

    fun load(): List<StoredRoute> {
        if (!file.exists()) return emptyList()
        return try {
            RouteCodec.decode(file.readText())
        } catch (error: Exception) {
            emptyList()
        }
    }

    fun save(routes: List<StoredRoute>) {
        file.writeText(RouteCodec.encode(routes))
    }

    fun find(destination: String): StoredRoute? =
        load().firstOrNull { it.destination.equals(destination, ignoreCase = true) }

    /** Adds the route, replacing a route that carries the same name. */
    fun upsert(route: StoredRoute): List<StoredRoute> {
        val kept = load().filterNot { it.destination.equals(route.destination, ignoreCase = true) }
        val updated = kept + route
        save(updated)
        return updated
    }

    fun delete(destination: String): List<StoredRoute> {
        val updated = load().filterNot { it.destination.equals(destination, ignoreCase = true) }
        save(updated)
        return updated
    }

    companion object {
        const val FILE_NAME = "routes.json"
    }
}
