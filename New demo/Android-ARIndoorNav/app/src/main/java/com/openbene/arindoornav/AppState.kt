package com.openbene.arindoornav

import android.content.Context
import android.util.Log
import com.openbene.arindoornav.robot.MockRobotLink
import com.openbene.arindoornav.robot.OpenBotBleLink
import com.openbene.arindoornav.robot.RobotLink

/** The Bluetooth choice shared by the main screen and the AR screen. */
object AppState {

    var useBle: Boolean = false
    var bleDeviceAddress: String? = null
    var bleDeviceName: String? = null

    /** Builds the link the AR screen drives, falling back to the bench mock. */
    fun createLink(context: Context): RobotLink {
        val address = bleDeviceAddress
        if (!useBle || address == null) return MockRobotLink()
        val link = OpenBotBleLink(context)
        if (!link.connectToAddress(address)) {
            Log.w(TAG, "no Bluetooth adapter or unknown address, using the mock link")
            link.close()
            return MockRobotLink()
        }
        return link
    }

    fun describeLink(): String = when {
        !useBle -> "mock link (commands are only shown on screen)"
        bleDeviceAddress == null -> "mock link (no OpenBot selected)"
        else -> "OpenBot " + (bleDeviceName ?: bleDeviceAddress)
    }

    private const val TAG = "AppState"
}
