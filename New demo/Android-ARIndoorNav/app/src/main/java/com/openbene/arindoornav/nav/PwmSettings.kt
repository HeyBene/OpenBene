package com.openbene.arindoornav.nav

data class PwmSettings(val drive: Int = 160, val leftTurn: Int = 160, val rightTurn: Int = 160) {
    val valid: Boolean get() = listOf(drive, leftTurn, rightTurn).all { it in 0..255 }
}
