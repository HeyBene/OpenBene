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

    /** Creates a real link when selected; a connection failure never enables preview. */
    fun createLink(context: Context): RobotLink {
        val address = bleDeviceAddress
        if (!useBle || address == null) return MockRobotLink()
        val link = OpenBotBleLink(context)
        if (!link.connectToAddress(address)) {
            Log.w(TAG, "Bluetooth is not ready; keep the real link disconnected")
        }
        return link
    }

    fun describeLink(): String = when {
        !useBle -> "仅预览，不驱动底盘"
        bleDeviceAddress == null -> "尚未选择底盘"
        else -> "OpenBot " + (bleDeviceName ?: bleDeviceAddress)
    }

    private const val TAG = "AppState"
}
