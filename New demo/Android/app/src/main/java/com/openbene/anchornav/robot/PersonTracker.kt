package com.openbene.anchornav.robot

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context

/**
 * Optional companion tracker. The OpenBot tracking workflow follows a wearable;
 * here the same BLE RSSI stream is used as a coarse "is the operator in front of
 * the robot" signal for the UI, and as the sensor a follow mode can build on.
 *
 * The distance model is the usual log-distance path loss with a calibrated RSSI
 * at one metre. It is only accurate to about a metre, which is exactly why the
 * route executor localises against the printed markers instead.
 */
class PersonTracker(
    context: Context,
    private val targetNamePrefix: String,
    private val rssiAtOneMeter: Double = -59.0,
) {
    private val adapter =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    var lastRssi: Int? = null
        private set
    var distanceEstimateM: Double? = null
        private set
    var lastSeenS: Double = 0.0
        private set

    val present: Boolean
        get() {
            val seen = lastSeenS
            return seen > 0.0 && (System.currentTimeMillis() / 1000.0 - seen) < PRESENCE_TIMEOUT_S
        }

    @SuppressLint("MissingPermission")
    fun start() {
        val scanner = adapter?.bluetoothLeScanner ?: return
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        scanner.startScan(null, settings, callback)
    }

    @SuppressLint("MissingPermission")
    fun stop() {
        adapter?.bluetoothLeScanner?.stopScan(callback)
    }

    private val callback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val name = runCatching { result.device?.name }.getOrNull() ?: return
            if (!name.lowercase().startsWith(targetNamePrefix.lowercase())) return
            lastRssi = result.rssi
            distanceEstimateM = Math.pow(10.0, (rssiAtOneMeter - result.rssi) / (10.0 * PATH_LOSS_EXPONENT))
            lastSeenS = System.currentTimeMillis() / 1000.0
        }
    }

    companion object {
        private const val PRESENCE_TIMEOUT_S = 3.0
        private const val PATH_LOSS_EXPONENT = 2.2
    }
}
