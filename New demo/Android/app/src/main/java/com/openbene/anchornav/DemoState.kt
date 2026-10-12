package com.openbene.anchornav

import android.content.Context
import android.util.Log
import com.openbene.anchornav.nav.MapData
import com.openbene.anchornav.nav.RobotLink
import com.openbene.anchornav.robot.MockRobotLink
import com.openbene.anchornav.robot.OpenBotBleLink

/**
 * Everything the two activities share: the parsed demo map and the choice of
 * robot link. The map JSON and the marker sheets are copies of shared/maps and
 * shared/markers so that the Python, Android and iOS implementations agree.
 */
object DemoState {

    const val MAP_ASSET = "demo_floor.json"

    /** Start of every demo route: the marker at the entrance. */
    const val START_LOCATION_ID = "loc_entrance"

    @Volatile
    var mapData: MapData? = null

    var selectedRoomName: String = "Room 101"

    var useBle: Boolean = false
    var bleDeviceAddress: String? = null
    var bleDeviceName: String? = null

    fun map(context: Context): MapData {
        mapData?.let { return it }
        val text = context.assets.open(MAP_ASSET).bufferedReader().use { it.readText() }
        val parsed = MapData.parse(text)
        mapData = parsed
        return parsed
    }

    /** Builds the link the route executor drives, falling back to the bench mock. */
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

    fun clearRobotSelection() {
        useBle = false
        bleDeviceAddress = null
        bleDeviceName = null
    }

    private const val TAG = "DemoState"
}
