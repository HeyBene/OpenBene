package com.openbene.arindoornav.ar

import android.content.Context
import android.graphics.BitmapFactory
import com.google.ar.core.AugmentedImageDatabase
import com.google.ar.core.Session

data class AnchorSheet(val name: String, val asset: String, val widthM: Float)

object AnchorSheets {
    val ALL = listOf(
        AnchorSheet("entrance", "anchors/openbene_mk_entrance.png", .2f),
        AnchorSheet("junction", "anchors/openbene_mk_junction.png", .2f),
        AnchorSheet("room101", "anchors/openbene_mk_room101.png", .2f),
        AnchorSheet("room102", "anchors/openbene_mk_room102.png", .2f),
        AnchorSheet("pi", "anchors/pi.jpg", .0762f),
        AnchorSheet("1", "anchors/1.jpeg", .127f),
    )
    fun sheet(name: String) = ALL.firstOrNull { it.name == name }
    fun buildDatabase(context: Context, session: Session, name: String, widthM: Float): AugmentedImageDatabase {
        require(widthM.isFinite() && widthM in .01f..2f) { "锚点纸张宽度无效" }
        val selected = requireNotNull(sheet(name)) { "未知锚点图片：$name" }
        val bitmap = context.assets.open(selected.asset).use { requireNotNull(BitmapFactory.decodeStream(it)) }
        return try {
            AugmentedImageDatabase(session).apply { addImage(selected.name, bitmap, widthM) }
        } finally { bitmap.recycle() }
    }
}
