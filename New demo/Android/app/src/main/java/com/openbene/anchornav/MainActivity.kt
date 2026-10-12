package com.openbene.anchornav

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.material.materialswitch.MaterialSwitch
import com.openbene.anchornav.ar.ArNavigationActivity
import com.openbene.anchornav.nav.GuidanceBuilder
import com.openbene.anchornav.nav.MapData
import com.openbene.anchornav.nav.Router
import com.openbene.anchornav.robot.OpenBotBleLink
import java.util.Locale

/**
 * Picks a destination and the robot link, then hands over to the AR activity.
 * The same map is used by the Python demo, so the routes and distances printed
 * here match run_demo.py.
 */
class MainActivity : AppCompatActivity() {

    private var mapData: MapData? = null
    private var bleLink: OpenBotBleLink? = null
    private val found = LinkedHashMap<String, String>()
    private val handler = Handler(Looper.getMainLooper())

    private lateinit var spinner: Spinner
    private lateinit var summary: TextView
    private lateinit var status: TextView
    private lateinit var bleSwitch: MaterialSwitch
    private lateinit var scanButton: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        spinner = findViewById(R.id.destinationSpinner)
        summary = findViewById(R.id.routeSummaryText)
        status = findViewById(R.id.statusText)
        bleSwitch = findViewById(R.id.bleSwitch)
        scanButton = findViewById(R.id.scanButton)
        val startButton: Button = findViewById(R.id.startButton)

        val map = try {
            DemoState.map(this)
        } catch (error: Exception) {
            status.text = getString(R.string.map_load_failed, error.message ?: "unknown error")
            startButton.isEnabled = false
            return
        }
        mapData = map

        val rooms = map.roomNames()
        spinner.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, rooms)
        spinner.setSelection(rooms.indexOf(DemoState.selectedRoomName).coerceAtLeast(0))
        spinner.onItemSelectedListener = SimpleItemSelectedListener { position ->
            rooms.getOrNull(position)?.let { room ->
                DemoState.selectedRoomName = room
                updateSummary(room)
            }
        }

        bleSwitch.setOnCheckedChangeListener { _, checked ->
            DemoState.useBle = checked
            if (checked) {
                requestBlePermissions()
            }
            updateScanButton()
            updateStatus()
        }

        scanButton.setOnClickListener { startBleScan() }
        startButton.setOnClickListener { startNavigation() }

        updateSummary(rooms.firstOrNull() ?: "")
        updateStatus()
    }

    override fun onDestroy() {
        super.onDestroy()
        bleLink?.close()
        bleLink = null
        handler.removeCallbacksAndMessages(null)
    }

    private fun updateSummary(roomName: String) {
        val map = mapData ?: return
        val route = Router(map).routeToRoom(DemoState.START_LOCATION_ID, roomName)
        if (route == null) {
            summary.text = getString(R.string.route_summary_placeholder)
            return
        }
        val builder = StringBuilder()
        builder.append(
            String.format(
                Locale.US,
                "%-14s %5.1f m\n",
                demoRouteStartName(route.startLocationId),
                route.totalDistanceM,
            ),
        )
        GuidanceBuilder(map).build(route).forEach { step ->
            builder.append("  - ").append(step.message).append('\n')
        }
        builder.append("markers on the way: ").append(
            route.locationSequence().joinToString(" -> ") { id -> id.removePrefix("loc_") },
        )
        summary.text = builder.toString()
    }

    private fun demoRouteStartName(locationId: String): String =
        mapData?.let { map ->
            if (map.hasLocation(locationId)) map.location(locationId).name else locationId
        } ?: locationId

    private fun updateStatus() {
        status.text = getString(R.string.status_idle) + "\n" + DemoState.describeLink()
    }

    private fun updateScanButton() {
        scanButton.isEnabled = DemoState.useBle && hasBlePermissions()
    }

    private fun hasBlePermissions(): Boolean = blePermissions().all {
        ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun blePermissions(): Array<String> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
    } else {
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }

    private fun requestBlePermissions() {
        val missing = blePermissions().filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), REQUEST_BLE)
        }
    }

    private fun startBleScan() {
        if (!hasBlePermissions()) {
            requestBlePermissions()
            return
        }
        found.clear()
        status.text = getString(R.string.scanning_bluetooth)
        val link = OpenBotBleLink(this)
        bleLink?.close()
        bleLink = link
        link.startScan { device, rssi ->
            val name = runCatching { device.name }.getOrNull() ?: "OpenBot"
            found[device.address] = name + "  " + rssi + " dBm  " + device.address
        }
        handler.postDelayed({ showScanResults() }, SCAN_WINDOW_MS)
    }

    private fun showScanResults() {
        if (isFinishing) return
        if (found.isEmpty()) {
            status.text = getString(R.string.no_robot_found)
            return
        }
        val entries = found.entries.toList()
        AlertDialog.Builder(this)
            .setTitle(R.string.scan_button)
            .setItems(entries.map { it.value }.toTypedArray()) { _, which ->
                val entry = entries[which]
                DemoState.bleDeviceAddress = entry.key
                DemoState.bleDeviceName = entry.value.substringBefore("  ")
                DemoState.useBle = true
                status.text = getString(R.string.connected_to, entry.value)
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun startNavigation() {
        if (DemoState.useBle && DemoState.bleDeviceAddress == null) {
            Toast.makeText(this, R.string.no_robot_found, Toast.LENGTH_SHORT).show()
            return
        }
        startActivity(Intent(this, ArNavigationActivity::class.java))
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_BLE) updateScanButton()
    }

    private class SimpleItemSelectedListener(
        private val onSelected: (Int) -> Unit,
    ) : android.widget.AdapterView.OnItemSelectedListener {
        override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: android.view.View?, position: Int, id: Long) {
            onSelected(position)
        }

        override fun onNothingSelected(parent: android.widget.AdapterView<*>?) = Unit
    }

    private companion object {
        const val REQUEST_BLE = 17
        const val SCAN_WINDOW_MS = 8000L
    }
}
