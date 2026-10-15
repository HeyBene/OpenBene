package com.openbene.arindoornav.nav

import com.openbene.arindoornav.robot.OpenBotProtocol
import com.openbene.arindoornav.robot.RobotLink

enum class PwmTestAction { FORWARD, LEFT, RIGHT }

class PwmPulseTester(private val link: RobotLink) {
    var active = false; private set
    var lastFrame = "c0,0"; private set
    private var deadline = 0.0
    private var left = 0.0
    private var right = 0.0
    fun start(action: PwmTestAction, pwm: PwmSettings, nowS: Double): Boolean {
        stop()
        if (!pwm.valid || !nowS.isFinite() || !link.telemetry.connected || link.telemetry.bumper != null) return false
        when (action) {
            PwmTestAction.FORWARD -> { left = pwm.drive / 255.0; right = left }
            PwmTestAction.LEFT -> { left = -pwm.leftTurn / 255.0; right = -left }
            PwmTestAction.RIGHT -> { left = pwm.rightTurn / 255.0; right = -left }
        }
        deadline = nowS + 1; active = true; tick(nowS)
        return true
    }
    fun tick(nowS: Double) {
        if (!active) return
        if (!nowS.isFinite() || nowS >= deadline || !link.telemetry.connected || link.telemetry.bumper != null) { stop(); return }
        link.drive(left, right)
        lastFrame = OpenBotProtocol.ctrlCmd(left, right).toString(Charsets.US_ASCII).trim()
    }
    fun stop() { active = false; link.stop(); lastFrame = "c0,0" }
}
