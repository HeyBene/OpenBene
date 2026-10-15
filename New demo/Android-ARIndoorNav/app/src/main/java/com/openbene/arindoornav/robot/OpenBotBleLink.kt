package com.openbene.arindoornav.robot

import android.annotation.SuppressLint
import android.bluetooth.*
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import android.os.SystemClock
import java.util.ArrayDeque
import java.util.UUID

/** Android GATT operations are serialized; all state and callbacks run on main. */
@SuppressLint("MissingPermission")
class OpenBotBleLink(context: Context) : RobotLink {
    override val telemetry = Telemetry(sourceName = "ble")
    var lastControlFrame: String? = null; private set
    var lastError: String? = null; private set
    private val appContext = context.applicationContext
    private val handler = Handler(Looper.getMainLooper())
    private val adapter = (appContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    private var gatt: BluetoothGatt? = null
    private var rx: BluetoothGattCharacteristic? = null
    private var scanCallback: ScanCallback? = null
    private var stream = TelemetryStream()
    private var busy = false
    private var closing = false
    private var pendingControl: ByteArray? = null
    private var stopPending = false
    private var heartbeatDue = false
    private val setup = ArrayDeque<ByteArray>()
    private var lastControlAt = -1000L
    private var lastWasStop = true
    private var lastStopAt = -1000L
    private val heartbeat = object : Runnable {
        override fun run() {
            if (!telemetry.connected || closing) return
            heartbeatDue = true; drain()
            handler.postDelayed(this, 250)
        }
    }
    private val drainTask = Runnable { drain() }
    private val writeTimeout = Runnable {
        if (busy) fail("蓝牙写入超时，已断开；请重新连接。")
    }

    fun startScan(onFound: (BluetoothDevice, Int) -> Unit) {
        stopScan()
        val scanner = adapter?.takeIf { it.isEnabled }?.bluetoothLeScanner
        if (scanner == null) { lastError = "请开启手机蓝牙。"; return }
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val name = result.scanRecord?.deviceName ?: runCatching { result.device.name }.getOrNull()
                val service = ParcelUuid(UUID.fromString(OpenBotProtocol.SERVICE_UUID))
                if (isOpenBotName(name) || result.scanRecord?.serviceUuids?.contains(service) == true)
                    handler.post { onFound(result.device, result.rssi) }
            }
            override fun onScanFailed(errorCode: Int) { handler.post { lastError = "蓝牙搜索失败：$errorCode" } }
        }
        scanCallback = callback
        runCatching { scanner.startScan(null, ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), callback) }
            .onFailure { lastError = it.message }
    }

    fun stopScan() {
        scanCallback?.let { callback -> runCatching { adapter?.bluetoothLeScanner?.stopScan(callback) } }
        scanCallback = null
    }

    fun connectToAddress(address: String): Boolean {
        return runCatching {
            if (adapter?.isEnabled != true) { lastError = "请先开启蓝牙。"; return false }
            val device = adapter.getRemoteDevice(address)
            closing = false
            gatt = device.connectGatt(appContext, false, callback, BluetoothDevice.TRANSPORT_LE)
            gatt != null
        }.getOrElse { lastError = it.message; false }
    }

    override fun drive(left: Double, right: Double) {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (!telemetry.connected || closing) return
        if (!left.isFinite() || !right.isFinite() || (left == 0.0 && right == 0.0)) { stop(); return }
        pendingControl = OpenBotProtocol.ctrlCmd(left, right)
        drain()
    }

    override fun stop() {
        if (rx == null || gatt == null) return
        val now = SystemClock.elapsedRealtime()
        if (lastWasStop && pendingControl == null && !stopPending && now - lastStopAt < 250) return
        stopPending = true; pendingControl = null
        drain()
    }

    override fun close() {
        if (closing) return
        closing = true
        stopScan()
        handler.removeCallbacks(heartbeat)
        setup.clear(); heartbeatDue = false
        stop()
        telemetry.connected = false
        val previous = gatt
        handler.postDelayed({
            runCatching { previous?.disconnect(); previous?.close() }
            if (gatt === previous) { gatt = null; rx = null; busy = false }
            handler.removeCallbacks(writeTimeout)
        }, 250)
    }

    private fun ready() {
        telemetry.connected = true
        stream = TelemetryStream()
        setup.add(OpenBotProtocol.sensorStreamCmd('v', 500))
        setup.add(OpenBotProtocol.sensorStreamCmd('w', 250))
        if (SONAR_INSTALLED) setup.add(OpenBotProtocol.sensorStreamCmd('s', 250))
        setup.add(OpenBotProtocol.featureCmd())
        stopPending = true
        handler.removeCallbacks(heartbeat); heartbeat.run()
    }

    private fun drain() {
        if (busy) return
        val active = gatt ?: return
        val characteristic = rx ?: return
        val control = pendingControl
        val isStop = stopPending
        val now = SystemClock.elapsedRealtime()
        val payload = when {
            isStop -> STOP.also { stopPending = false }
            closing -> return
            heartbeatDue -> OpenBotProtocol.heartbeatCmd(750).also { heartbeatDue = false }
            setup.isNotEmpty() -> setup.removeFirst()
            control != null -> {
                val wait = 40 - (now - lastControlAt)
                if (wait > 0) {
                    handler.removeCallbacks(drainTask); handler.postDelayed(drainTask, wait); return
                }
                pendingControl = null; control
            }
            else -> return
        }
        val supportsNoResponse = characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0
        val type = if (supportsNoResponse) BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE else BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        busy = true
        val accepted = runCatching {
            if (Build.VERSION.SDK_INT >= 33) active.writeCharacteristic(characteristic, payload, type) == BluetoothStatusCodes.SUCCESS
            else {
                @Suppress("DEPRECATION")
                characteristic.writeType = type
                @Suppress("DEPRECATION")
                characteristic.value = payload
                @Suppress("DEPRECATION")
                active.writeCharacteristic(characteristic)
            }
        }.getOrDefault(false)
        if (!accepted) { fail("蓝牙写入未接受，已断开；请检查权限并重连。"); return }
        if (payload.firstOrNull()?.toInt() == 'c'.code) {
            lastControlFrame = payload.toString(Charsets.US_ASCII).trim()
            lastControlAt = now; lastWasStop = isStop
            if (isStop) lastStopAt = now
        }
        handler.removeCallbacks(writeTimeout)
        handler.postDelayed(writeTimeout, 1000)
    }

    private fun fail(reason: String) {
        lastError = reason; telemetry.connected = false
        pendingControl = null; stopPending = false; setup.clear(); heartbeatDue = false; busy = false
        handler.removeCallbacks(heartbeat); handler.removeCallbacks(writeTimeout)
        val previous = gatt; gatt = null; rx = null
        runCatching { previous?.disconnect(); previous?.close() }
    }

    private val callback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(active: BluetoothGatt, status: Int, newState: Int) {
            handler.post {
                if (gatt !== active) return@post
                if (status != BluetoothGatt.GATT_SUCCESS || newState == BluetoothProfile.STATE_DISCONNECTED) {
                    fail("底盘已断开（状态 $status）。")
                } else if (newState == BluetoothProfile.STATE_CONNECTED) active.discoverServices()
            }
        }
        override fun onServicesDiscovered(active: BluetoothGatt, status: Int) {
            handler.post {
                if (gatt !== active || closing) return@post
                val service = active.getService(UUID.fromString(OpenBotProtocol.SERVICE_UUID))
                rx = service?.getCharacteristic(UUID.fromString(OpenBotProtocol.CHAR_RX_UUID))
                val tx = service?.getCharacteristic(UUID.fromString(OpenBotProtocol.CHAR_TX_UUID))
                if (status != BluetoothGatt.GATT_SUCCESS || rx == null || tx == null ||
                    rx!!.properties and (BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) == 0) {
                    fail("OpenBot 服务或 RX/TX 特征不可用。"); return@post
                }
                active.setCharacteristicNotification(tx, true)
                val descriptor = tx.getDescriptor(CCCD)
                if (descriptor == null) { ready(); return@post }
                val accepted = if (Build.VERSION.SDK_INT >= 33)
                    active.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) == BluetoothStatusCodes.SUCCESS
                else {
                    @Suppress("DEPRECATION")
                    descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    @Suppress("DEPRECATION")
                    active.writeDescriptor(descriptor)
                }
                if (!accepted) fail("无法启用底盘遥测通知。")
            }
        }
        override fun onDescriptorWrite(active: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
            handler.post {
                if (gatt !== active || closing) return@post
                if (status == BluetoothGatt.GATT_SUCCESS) ready() else fail("底盘通知订阅失败：$status")
            }
        }
        override fun onCharacteristicWrite(active: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
            handler.post {
                if (gatt !== active) return@post
                handler.removeCallbacks(writeTimeout); busy = false
                if (status != BluetoothGatt.GATT_SUCCESS) fail("蓝牙写入错误：$status") else drain()
            }
        }
        override fun onCharacteristicChanged(active: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            handler.post { if (gatt === active) stream.receive(value, telemetry, SystemClock.elapsedRealtime() / 1000.0, SONAR_INSTALLED) }
        }
        @Deprecated("Android 12 and earlier callback")
        override fun onCharacteristicChanged(active: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION")
            val value = characteristic.value?.clone() ?: return
            handler.post { if (gatt === active) stream.receive(value, telemetry, SystemClock.elapsedRealtime() / 1000.0, SONAR_INSTALLED) }
        }
    }

    companion object {
        const val SONAR_INSTALLED = false
        private val STOP = OpenBotProtocol.ctrlCmd(0.0, 0.0)
        private val CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        fun isOpenBotName(name: String?): Boolean {
            val text = name?.lowercase() ?: return false
            return text.contains("openbot") || text.contains("rtr_520") || text.contains("rtr 520")
        }
    }
}
