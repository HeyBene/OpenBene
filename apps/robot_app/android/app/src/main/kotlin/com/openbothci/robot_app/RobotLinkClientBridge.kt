package com.openbothci.robot_app

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.util.UUID
import java.util.concurrent.Executors

class RobotLinkClientBridge(
    private val context: Context,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val METHOD_CHANNEL = "com.openbothci.robot_app/robot_link/methods"
        private const val EVENT_CHANNEL = "com.openbothci.robot_app/robot_link/events"
        private const val SERVICE_NAME = "OpenBotControllerLink"
        private const val PREFS_NAME = "robot_app_robot_link"
        private const val PREF_LAST_DEVICE_ADDRESS = "last_device_address"

        private val CONTROLLER_LINK_UUID: UUID =
            UUID.fromString("9d7e5cb2-0f9e-4c45-a6e2-3f92c1cb6f1a")
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val readExecutor = Executors.newSingleThreadExecutor()
    private val bluetoothManager = context.getSystemService(BluetoothManager::class.java)
    private val preferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val adapter: BluetoothAdapter?
        get() = bluetoothManager?.adapter

    @Volatile
    private var socket: BluetoothSocket? = null

    @Volatile
    private var writer: BufferedWriter? = null

    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    fun attach(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler(this)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getBondedDevices" -> result.success(getBondedDevices())
            "connect" -> {
                val address = call.argument<String>("address")
                if (address.isNullOrBlank()) {
                    result.success(
                        mapOf(
                            "success" to false,
                            "error" to "Bluetooth device address is missing.",
                        ),
                    )
                    return
                }
                ioExecutor.execute {
                    val response = connectInternal(address)
                    mainHandler.post { result.success(response) }
                }
            }

            "disconnect" -> {
                ioExecutor.execute {
                    disconnectInternal(emitDisconnected = true)
                    mainHandler.post { result.success(true) }
                }
            }

            "sendCommand" -> {
                val raw = call.arguments as? String
                if (raw.isNullOrBlank()) {
                    result.success(false)
                    return
                }
                ioExecutor.execute {
                    val sent = sendRawToRobot(raw)
                    mainHandler.post { result.success(sent) }
                }
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    @SuppressLint("MissingPermission")
    private fun getBondedDevices(): List<Map<String, Any?>> {
        if (!hasBluetoothPermissions()) return emptyList()
        val bluetoothAdapter = adapter ?: return emptyList()
        val lastAddress = preferences.getString(PREF_LAST_DEVICE_ADDRESS, null)
        return bluetoothAdapter.bondedDevices
            .map { device ->
                mapOf(
                    "name" to (device.name ?: SERVICE_NAME),
                    "address" to device.address,
                    "lastUsed" to (device.address == lastAddress),
                )
            }
            .sortedBy { (it["name"] as? String ?: "").lowercase() }
    }

    @SuppressLint("MissingPermission")
    private fun connectInternal(address: String): Map<String, Any?> {
        if (!hasBluetoothPermissions()) {
            emitError("Bluetooth permission is missing.")
            return mapOf(
                "success" to false,
                "error" to "Bluetooth permission is missing.",
            )
        }

        val bluetoothAdapter = adapter ?: return mapOf(
            "success" to false,
            "error" to "This phone does not support Bluetooth.",
        )
        if (!bluetoothAdapter.isEnabled) {
            return mapOf(
                "success" to false,
                "error" to "Bluetooth is disabled.",
            )
        }

        return try {
            disconnectInternal(emitDisconnected = false)

            val device = bluetoothAdapter.getRemoteDevice(address)
            bluetoothAdapter.cancelDiscovery()
            val newSocket = device.createRfcommSocketToServiceRecord(CONTROLLER_LINK_UUID)
            newSocket.connect()

            socket = newSocket
            writer = BufferedWriter(OutputStreamWriter(newSocket.outputStream))
            preferences.edit()
                .putString(PREF_LAST_DEVICE_ADDRESS, address)
                .apply()

            emitLinkState(
                connected = true,
                deviceName = device.name ?: device.address,
                deviceAddress = device.address,
            )
            startReadLoop(newSocket)

            mapOf(
                "success" to true,
                "deviceName" to (device.name ?: device.address),
                "deviceAddress" to device.address,
            )
        } catch (error: Exception) {
            disconnectInternal(emitDisconnected = true)
            val message = error.message ?: "Unable to connect to robot phone."
            emitError("Bluetooth connect failed: $message")
            mapOf(
                "success" to false,
                "error" to message,
            )
        }
    }

    private fun startReadLoop(activeSocket: BluetoothSocket) {
        readExecutor.execute {
            try {
                val reader = BufferedReader(InputStreamReader(activeSocket.inputStream))
                while (socket === activeSocket) {
                    val line = reader.readLine() ?: break
                    if (line.isNotBlank()) {
                        handleIncomingLine(line)
                    }
                }
            } catch (_: Exception) {
            } finally {
                ioExecutor.execute {
                    if (socket === activeSocket) {
                        disconnectInternal(emitDisconnected = true)
                    }
                }
            }
        }
    }

    private fun handleIncomingLine(raw: String) {
        val payload = try {
            JSONObject(raw)
        } catch (_: Exception) {
            null
        }

        if (payload == null) {
            emitEvent(
                mapOf(
                    "event" to "raw",
                    "raw" to raw,
                ),
            )
            return
        }

        emitEvent(
            mapOf(
                "event" to "status",
                "raw" to payload.toString(),
                "type" to payload.optString("type"),
            ),
        )
    }

    private fun sendRawToRobot(raw: String): Boolean {
        val activeWriter = writer ?: return false
        return try {
            activeWriter.write(raw)
            activeWriter.newLine()
            activeWriter.flush()
            true
        } catch (_: Exception) {
            disconnectInternal(emitDisconnected = true)
            false
        }
    }

    private fun disconnectInternal(emitDisconnected: Boolean) {
        try {
            writer?.close()
        } catch (_: Exception) {
        }
        writer = null

        try {
            socket?.close()
        } catch (_: Exception) {
        }
        socket = null

        if (emitDisconnected) {
            emitLinkState(
                connected = false,
                deviceName = null,
                deviceAddress = null,
            )
        }
    }

    private fun emitLinkState(
        connected: Boolean,
        deviceName: String?,
        deviceAddress: String?,
    ) {
        emitEvent(
            mapOf(
                "event" to "link_state",
                "connected" to connected,
                "deviceName" to deviceName,
                "deviceAddress" to deviceAddress,
            ),
        )
    }

    private fun emitError(message: String) {
        emitEvent(
            mapOf(
                "event" to "error",
                "message" to message,
            ),
        )
    }

    private fun emitEvent(payload: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    private fun hasBluetoothPermissions(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val hasConnect = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
        val hasScan = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.BLUETOOTH_SCAN,
        ) == PackageManager.PERMISSION_GRANTED
        return hasConnect && hasScan
    }
}
