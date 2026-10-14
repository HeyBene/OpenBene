package com.openbene.anchornav.robot

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.ParcelUuid
import android.util.Log
import java.util.UUID

/**
 * The 520 chassis in this demo has no ultrasonic module fitted, but the
 * firmware keeps pinging anyway: the echo pin is left floating, picks up the
 * trigger pulse and reports 1-3 cm, which the obstacle guard reads as a wall
 * and refuses to drive through. Subscribe to the sonar stream only when the
 * module is actually installed.
 */
private const val SONAR_INSTALLED = false

/**
 * BLE link to the OpenBot ESP32 firmware, matching the UUIDs used by
 * openbene_sdk/src/openbene/esp32_ble.py: one service, an RX characteristic for
 * commands and a TX characteristic for telemetry notifications.
 */
class OpenBotBleLink(private val context: Context) : com.openbene.anchornav.nav.RobotLink {
    override val telemetry = Telemetry(sourceName = "ble")

    private val adapter: BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private var gatt: BluetoothGatt? = null
    private var rxCharacteristic: BluetoothGattCharacteristic? = null
    private var txCharacteristic: BluetoothGattCharacteristic? = null
    private val lineBuffer = StringBuilder()

    @SuppressLint("MissingPermission")
    fun startScan(onFound: (BluetoothDevice, Int) -> Unit) {
        val scanner = adapter?.bluetoothLeScanner ?: return
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        // The ESP32 firmware advertises its name rather than the GATT service, so
        // results are matched the same way openbene_sdk does: by device name, with
        // the advertised service UUID accepted as a second signal.
        val serviceUuid = ParcelUuid(UUID.fromString(OpenBotProtocol.SERVICE_UUID))
        scanner.startScan(null, settings, object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val device = result.device ?: return
                val name = runCatching { device.name }.getOrNull()
                val advertisesService = result.scanRecord?.serviceUuids?.contains(serviceUuid) == true
                if (isOpenBotName(name) || advertisesService) onFound(device, result.rssi)
            }
        })
    }

    @SuppressLint("MissingPermission")
    fun connect(device: BluetoothDevice) {
        gatt = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
    }

    /** Connect to a device picked from [startScan] by MAC address. */
    @SuppressLint("MissingPermission")
    fun connectToAddress(address: String): Boolean {
        val device = runCatching { adapter?.getRemoteDevice(address) }.getOrNull() ?: return false
        connect(device)
        return true
    }

    override fun drive(left: Double, right: Double) {
        write(OpenBotProtocol.ctrlCmd(left, right))
    }

    override fun stop() = drive(0.0, 0.0)

    @SuppressLint("MissingPermission")
    override fun close() {
        runCatching { gatt?.disconnect() }
        runCatching { gatt?.close() }
        gatt = null
        telemetry.connected = false
    }

    @SuppressLint("MissingPermission")
    private fun write(payload: ByteArray) {
        val characteristic = rxCharacteristic ?: return
        val activeGatt = gatt ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activeGatt.writeCharacteristic(
                characteristic,
                payload,
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE,
            )
        } else {
            @Suppress("DEPRECATION")
            characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            @Suppress("DEPRECATION")
            characteristic.value = payload
            @Suppress("DEPRECATION")
            activeGatt.writeCharacteristic(characteristic)
        }
    }

    @SuppressLint("MissingPermission")
    private fun enableTelemetry() {
        val activeGatt = gatt ?: return
        val tx = txCharacteristic ?: return
        activeGatt.setCharacteristicNotification(tx, true)
        val descriptor = tx.getDescriptor(DESCRIPTOR_CONFIG_UUID)
        if (descriptor != null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activeGatt.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
            } else {
                @Suppress("DEPRECATION")
                descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                @Suppress("DEPRECATION")
                activeGatt.writeDescriptor(descriptor)
            }
        }
        write(OpenBotProtocol.heartbeatCmd(500))
        write(OpenBotProtocol.sensorStreamCmd('v', 500))
        write(OpenBotProtocol.sensorStreamCmd('w', 250))
        if (SONAR_INSTALLED) write(OpenBotProtocol.sensorStreamCmd('s', 250))
        write(OpenBotProtocol.featureCmd())
    }

    private val callback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    telemetry.connected = true
                    gatt.discoverServices()
                }
                BluetoothProfile.STATE_DISCONNECTED -> {
                    telemetry.connected = false
                    Log.i(TAG, "OpenBot disconnected, status=" + status)
                }
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val service = gatt.getService(UUID.fromString(OpenBotProtocol.SERVICE_UUID)) ?: return
            rxCharacteristic = service.getCharacteristic(UUID.fromString(OpenBotProtocol.CHAR_RX_UUID))
            txCharacteristic = service.getCharacteristic(UUID.fromString(OpenBotProtocol.CHAR_TX_UUID))
            enableTelemetry()
        }

        override fun onCharacteristicChanged(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            value: ByteArray,
        ) {
            handlePayload(value)
        }

        @Deprecated("Deprecated in Android 13, kept for older devices")
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION")
            val value = characteristic.value ?: return
            handlePayload(value)
        }
    }

    private fun handlePayload(value: ByteArray) {
        val text = String(value, Charsets.UTF_8).replace("\u0000", "")
        lineBuffer.append(text)
        val now = System.currentTimeMillis() / 1000.0
        while (true) {
            val index = lineBuffer.indexOf("\n")
            if (index < 0) break
            val line = lineBuffer.substring(0, index)
            lineBuffer.delete(0, index + 1)
            OpenBotProtocol.applyLine(telemetry, line, now)
        }
        // Firmware notifications arrive as complete payloads without a trailing
        // newline, so flush whatever is buffered as one message.
        if (lineBuffer.isNotEmpty()) {
            OpenBotProtocol.applyLine(telemetry, lineBuffer.toString(), now)
            lineBuffer.setLength(0)
        }
    }

    companion object {
        private const val TAG = "OpenBotBleLink"
        private val DESCRIPTOR_CONFIG_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        fun isOpenBotName(name: String?): Boolean {
            val lowered = name?.lowercase() ?: return false
            return lowered.contains("openbot") || lowered.contains("rtr_520") || lowered.contains("rtr 520")
        }
    }
}
