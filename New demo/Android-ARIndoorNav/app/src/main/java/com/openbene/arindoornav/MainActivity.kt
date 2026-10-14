package com.openbene.arindoornav

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.material.materialswitch.MaterialSwitch
import com.openbene.arindoornav.ar.ArRouteActivity
import com.openbene.arindoornav.model.StoredRoute
import com.openbene.arindoornav.robot.OpenBotBleLink
import java.util.Locale

/**
 * The route list of the ARIndoorNav port. There is no floor map to import: a route
 * is one anchor sheet plus the chain of nodes that was recorded against it, and the
 * list below is what the routes file holds.
 */
class MainActivity : AppCompatActivity() {

    private lateinit var store: RouteStore
    private lateinit var routeList: LinearLayout
    private lateinit var emptyRoutesText: TextView
    private lateinit var storageText: TextView
    private lateinit var statusText: TextView
    private lateinit var bleSwitch: MaterialSwitch
    private lateinit var scanButton: Button

    private var bleLink: OpenBotBleLink? = null
    private val found = LinkedHashMap<String, String>()
    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        store = RouteStore(this)
        routeList = findViewById(R.id.routeList)
        emptyRoutesText = findViewById(R.id.emptyRoutesText)
        storageText = findViewById(R.id.storageText)
        statusText = findViewById(R.id.statusText)
        bleSwitch = findViewById(R.id.bleSwitch)
        scanButton = findViewById(R.id.scanButton)
        val createMapButton: Button = findViewById(R.id.createMapButton)
        val followButton: Button = findViewById(R.id.followButton)

        storageText.text = getString(R.string.storage_label) + ": " + store.location()

        createMapButton.setOnClickListener {
            startActivity(ArRouteActivity.intent(this, ArRouteActivity.MODE_CAPTURE))
        }
        followButton.setOnClickListener {
            startActivity(ArRouteActivity.intent(this, ArRouteActivity.MODE_FOLLOW))
        }

        bleSwitch.setOnCheckedChangeListener { _, checked ->
            AppState.useBle = checked
            if (checked) requestBlePermissions()
            updateScanButton()
            updateStatus()
        }
        scanButton.setOnClickListener { startBleScan() }

        updateScanButton()
        updateStatus()
    }

    override fun onResume() {
        super.onResume()
        renderRoutes()
        updateStatus()
    }

    override fun onDestroy() {
        super.onDestroy()
        bleLink?.close()
        bleLink = null
        handler.removeCallbacksAndMessages(null)
    }

    private fun renderRoutes() {
        routeList.removeAllViews()
        val routes = store.load().sortedBy { it.destination.lowercase() }
        emptyRoutesText.visibility = if (routes.isEmpty()) View.VISIBLE else View.GONE
        for (route in routes) routeList.addView(routeRow(route))
    }

    private fun routeRow(route: StoredRoute): View {
        val row = LinearLayout(this)
        row.orientation = LinearLayout.HORIZONTAL
        row.layoutParams = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )

        val info = TextView(this)
        info.layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        info.textSize = 13f
        info.text = String.format(
            Locale.US,
            "%s\nanchor %s, %d nodes, %.1f m",
            route.destination,
            route.beaconName.ifEmpty { "?" },
            route.nodeCount,
            route.pathLengthM(),
        )
        row.addView(info)

        val navigate = Button(this)
        navigate.text = getString(R.string.navigate_button)
        navigate.setOnClickListener {
            startActivity(
                ArRouteActivity.intent(this, ArRouteActivity.MODE_NAVIGATE, route.destination),
            )
        }
        row.addView(navigate)

        val delete = Button(this)
        delete.text = getString(R.string.delete_button)
        delete.setOnClickListener { confirmDelete(route) }
        row.addView(delete)

        return row
    }

    private fun confirmDelete(route: StoredRoute) {
        AlertDialog.Builder(this)
            .setTitle(R.string.delete_confirm_title)
            .setMessage(getString(R.string.delete_confirm_message, route.destination))
            .setPositiveButton(android.R.string.ok) { _, _ ->
                store.delete(route.destination)
                renderRoutes()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun updateStatus() {
        statusText.text = getString(R.string.status_idle) + "\n" + AppState.describeLink()
    }

    // ------------------------------------------------------------- Bluetooth

    private fun updateScanButton() {
        scanButton.isEnabled = AppState.useBle && hasBlePermissions()
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
        statusText.text = getString(R.string.scanning_bluetooth)
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
            statusText.text = getString(R.string.no_robot_found)
            return
        }
        val entries = found.entries.toList()
        AlertDialog.Builder(this)
            .setTitle(R.string.scan_button)
            .setItems(entries.map { it.value }.toTypedArray()) { _, which ->
                val entry = entries[which]
                AppState.bleDeviceAddress = entry.key
                AppState.bleDeviceName = entry.value.substringBefore("  ")
                AppState.useBle = true
                statusText.text = getString(R.string.connected_to, entry.value)
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_BLE) updateScanButton()
    }

    private companion object {
        const val REQUEST_BLE = 17
        const val SCAN_WINDOW_MS = 8000L
    }
}
