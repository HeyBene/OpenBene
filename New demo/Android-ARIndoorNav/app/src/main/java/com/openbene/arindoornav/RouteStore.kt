package com.openbene.arindoornav

import android.content.Context
import com.openbene.arindoornav.model.RouteCodec
import com.openbene.arindoornav.model.StoredRoute
import java.io.File
import android.util.AtomicFile

/** Local-only storage; AtomicFile preserves the previous capture on failed writes. */
class RouteStore(private val context: Context) {

    private val file: File get() = File(context.filesDir, FILE_NAME)

    fun location(): String = file.absolutePath

    fun load(): List<StoredRoute> {
        val atomic = AtomicFile(file)
        if (!atomic.baseFile.exists() && !File(file.path + ".bak").exists()) return emptyList()
        return atomic.openRead().bufferedReader().use { RouteCodec.decode(it.readText()) }
    }

    fun save(routes: List<StoredRoute>) {
        val bytes = RouteCodec.encode(routes).toByteArray(Charsets.UTF_8)
        val atomic = AtomicFile(file)
        val stream = atomic.startWrite()
        try { stream.write(bytes); atomic.finishWrite(stream) }
        catch (error: Exception) { atomic.failWrite(stream); throw error }
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
