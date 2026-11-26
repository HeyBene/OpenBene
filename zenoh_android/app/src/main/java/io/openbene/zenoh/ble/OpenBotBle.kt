package io.openbene.zenoh.ble

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.util.UUID
import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.math.roundToInt

/**
 * Minimal OpenBot chassis link over BLE.
 *
 * Uses the same text protocol as `openbot-mobile-control`: `c<left>,<right>\n`
 * with wheel values in -255..255, written in 20 byte chunks.
 */
class OpenBotBle(
    private val context: Context,
    private val listener: Listener,
) {
    interface Listener {
        fun onBleState(message: String)
    }

    private val handler = Handler(Looper.getMainLooper())
    private val queue = ConcurrentLinkedQueue<ByteArray>()
    private val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    private val adapter: BluetoothAdapter? get() = manager?.adapter

    private var gatt: BluetoothGatt? = null
    private var writer: BluetoothGattCharacteristic? = null
    private var notifier: BluetoothGattCharacteristic? = null
    private var lastCommandAt = 0L
    private var writing = false
    private var lastDrive = 0 to 0

    @Volatile
    var isConnected: Boolean = false
        private set

    @Volatile
    var deviceName: String = ""
        private set

    fun connect() {
        val adapter = adapter
        if (adapter == null || !adapter.isEnabled) {
            listener.onBleState("蓝牙不可用或未开启")
            return
        }
        val scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            listener.onBleState("这台设备不支持 BLE 扫描")
            return
        }
        listener.onBleState("正在扫描 OpenBot…")
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
        runCatching {
            scanner.startScan(null, settings, scanCallback)
            handler.postDelayed({ runCatching { scanner.stopScan(scanCallback) } }, SCAN_TIMEOUT_MS)
        }.onFailure { listener.onBleState("扫描失败：${it.message}") }
    }

    fun disconnect() {
        runCatching { adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
        queue.clear()
        isConnected = false
        runCatching { gatt?.disconnect() }
        runCatching { gatt?.close() }
        gatt = null
        writer = null
        notifier = null
        listener.onBleState("底盘已断开")
    }

    /** Left and right in -1..1, same units as the Zenoh drive command. */
    fun drive(left: Double, right: Double) {
        val leftInt = (left.coerceIn(-1.0, 1.0) * 255).roundToInt()
        val rightInt = (right.coerceIn(-1.0, 1.0) * 255).roundToInt()
        lastDrive = leftInt to rightInt
        send(OpenBotFrames.control(leftInt, rightInt))
    }

    fun stop() {
        lastDrive = 0 to 0
        send(OpenBotFrames.control(0, 0))
    }

    private fun send(command: String) {
        if (!isConnected || writer == null) return
        lastCommandAt = SystemClock.elapsedRealtime()
        OpenBotFrames.chunks(command).forEach { queue.add(it) }
        drain()
    }

    private fun drain() {
        if (writing) return
        val gatt = gatt ?: return
        val characteristic = writer ?: return
        val next = queue.poll() ?: return
        writing = true
        runCatching {
            @Suppress("DEPRECATION")
            characteristic.writeType = if (
                characteristic.properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0
            ) {
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            } else {
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            }
            @Suppress("DEPRECATION")
            characteristic.value = next
            @Suppress("DEPRECATION")
            val started = gatt.writeCharacteristic(characteristic)
            if (!started) {
                writing = false
                listener.onBleState("写入被拒绝")
            }
        }.onFailure {
            writing = false
            queue.clear()
            listener.onBleState("写入失败：${it.message}")
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            if (isConnected) return
            val name = runCatching { result.device.name }.getOrNull().orEmpty()
            val services = result.scanRecord?.serviceUuids?.map { it.uuid } ?: emptyList()
            val matches = services.contains(OpenBotFrames.SERVICE_UUID) ||
                name.contains("OpenBot", ignoreCase = true) ||
                name.contains("ESP32", ignoreCase = true)
            if (!matches) return
            runCatching { adapter?.bluetoothLeScanner?.stopScan(this) }
            deviceName = name.ifBlank { result.device.address }
            listener.onBleState("发现 $deviceName，正在连接…")
            @Suppress("MissingPermission")
            gatt = result.device.connectGatt(context, false, gattCallback, BluetoothDeviceCompat.LE)
        }

        override fun onScanFailed(errorCode: Int) {
            listener.onBleState("扫描失败，错误码 $errorCode")
        }
    }

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) {
                listener.onBleState("已连接 $deviceName，发现服务…")
                runCatching { gatt.discoverServices() }
            } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                isConnected = false
                writer = null
                writing = false
                queue.clear()
                listener.onBleState("底盘连接断开")
            }
        }

        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val service = gatt.getService(OpenBotFrames.SERVICE_UUID)
                ?: gatt.services.firstOrNull { it.uuid.toString().endsWith("ffe0") }
            if (service == null) {
                listener.onBleState("没找到 OpenBot 服务")
                return
            }
            val writable = service.characteristics.firstOrNull {
                it.uuid == OpenBotFrames.RX_UUID
            } ?: service.characteristics.firstOrNull {
                it.properties and (BluetoothGattCharacteristic.PROPERTY_WRITE or
                    BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0
            }
            if (writable == null) {
                listener.onBleState("没找到可写特征值")
                return
            }
            writer = writable
            notifier = service.characteristics.firstOrNull { it.uuid == OpenBotFrames.TX_UUID }
            notifier?.let { runCatching { gatt.setCharacteristicNotification(it, true) } }
            isConnected = true
            lastCommandAt = SystemClock.elapsedRealtime()
            listener.onBleState("底盘就绪，可用键盘或 Zenoh 命令控制")
            handler.post(watchdog)
        }

        override fun onCharacteristicWrite(
            gatt: BluetoothGatt,
            characteristic: BluetoothGattCharacteristic,
            status: Int,
        ) {
            writing = false
            drain()
        }
    }

    /** Same safety rule as the phone app: stop 1.5 s after the last command. */
    private val watchdog = object : Runnable {
        override fun run() {
            if (isConnected && lastDrive != (0 to 0) &&
                SystemClock.elapsedRealtime() - lastCommandAt > COMMAND_TIMEOUT_MS
            ) {
                stop()
                listener.onBleState("1.5 秒没有新指令，已自动停车")
            }
            if (isConnected) handler.postDelayed(this, 300L)
        }
    }

    companion object {
        private const val SCAN_TIMEOUT_MS = 12_000L
        private const val COMMAND_TIMEOUT_MS = 1_500L
    }
}

/** Wire helpers kept pure so they can be unit tested without a radio. */
object OpenBotFrames {
    val SERVICE_UUID: UUID = UUID.fromString("61653dc3-4021-4d1e-ba83-8b4eec61d613")
    val RX_UUID: UUID = UUID.fromString("06386c14-86ea-4d71-811c-48f97c58f8c9")
    val TX_UUID: UUID = UUID.fromString("9bf1103b-834c-47cf-b149-c9e4bcf778a7")
    const val CHUNK_BYTES = 20

    fun control(left: Int, right: Int): String = "c$left,$right"

    fun chunks(command: String): List<ByteArray> {
        val bytes = (command + "\n").toByteArray(Charsets.UTF_8)
        return bytes.asList().chunked(CHUNK_BYTES).map { it.toByteArray() }
    }
}

private object BluetoothDeviceCompat {
    /** BluetoothDevice.TRANSPORT_LE, repeated here to keep imports minimal. */
    const val LE = 2
}
