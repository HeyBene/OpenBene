package com.openbene.arindoornav

import android.content.Context
import com.openbene.arindoornav.nav.PwmSettings

class PwmStore(context: Context) {
    private val prefs = context.getSharedPreferences("navigation_pwm", Context.MODE_PRIVATE)
    fun load(): PwmSettings = runCatching {
        val legacy = prefs.getInt("turn", 160)
        PwmSettings(prefs.getInt("drive", 160), prefs.getInt("left", legacy), prefs.getInt("right", legacy))
            .takeIf { it.valid } ?: PwmSettings()
    }.getOrDefault(PwmSettings())
    fun save(pwm: PwmSettings) {
        require(pwm.valid) { "PWM 必须在 0～255 之间。" }
        check(prefs.edit().putInt("drive", pwm.drive).putInt("left", pwm.leftTurn)
            .putInt("right", pwm.rightTurn).commit()) { "参数保存失败。" }
    }
}
