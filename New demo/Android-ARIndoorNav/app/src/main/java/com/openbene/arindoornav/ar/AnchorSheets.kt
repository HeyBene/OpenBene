package com.openbene.arindoornav.ar

import android.content.Context
import android.graphics.BitmapFactory
import android.util.Log
import com.google.ar.core.AugmentedImageDatabase
import com.google.ar.core.Session

/** One printed reference sheet, with the physical width ARKit used to know. */
data class AnchorSheet(val name: String, val asset: String, val widthM: Float)

/**
 * The two sheets the original ARIndoorNav ships in ARResources.arresourcegroup,
 * with the same physical widths: pi is 3 in wide and 1 is 5 in wide. ARKit read
 * the width from the asset catalog; ARCore wants metres, so the numbers below are
 * the only thing that has to match the paper. Everything else about the sheets is
 * unchanged, including the file names, so the same print works on both phones.
 */
object AnchorSheets {

    val ALL = listOf(
        AnchorSheet("pi", "anchors/pi.jpg", 0.0762f),
        AnchorSheet("1", "anchors/1.jpeg", 0.127f),
    )

    fun names(): String = ALL.joinToString(", ") { it.name }

    fun describe(): String = ALL.joinToString(", ") { it.name + " " + it.widthM + " m" }

    fun isAnchor(name: String?): Boolean = ALL.any { it.name == name }

    /** Builds the runtime database from the bundled sheets; no arcoreimg step. */
    fun buildDatabase(context: Context, session: Session): AugmentedImageDatabase? {
        val database = AugmentedImageDatabase(session)
        var added = 0
        for (sheet in ALL) {
            val bitmap = try {
                context.assets.open(sheet.asset).use { stream -> BitmapFactory.decodeStream(stream) }
            } catch (error: Exception) {
                Log.w(TAG, "anchor sheet missing: " + sheet.asset, error)
                null
            } ?: continue
            database.addImage(sheet.name, bitmap, sheet.widthM)
            added += 1
        }
        if (added == 0) return null
        Log.i(TAG, "augmented image database holds " + added + " anchor sheets")
        return database
    }

    private const val TAG = "AnchorSheets"
}
