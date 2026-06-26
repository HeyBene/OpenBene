package com.openbothci.robot_app

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
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
import java.io.InputStreamReader
import java.util.UUID

class PhoneControllerLinkBridge(
    private val context: Context,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        private const val METHOD_CHANNEL = "com.openbothci.robot_app/controller_link/methods"
        private const val EVENT_CHANNEL = "com.openbothci.robot_app/controller_link/events"
        private const val SERVICE_NAME = "OpenBotControllerLink"

        private val CONTROLLER_LINK_UUID: UUID =
            UUID.fromString("9d7e5cb2-0f9e-4c45-a6e2-3f92c1cb6f1a")
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val bluetoothManager = context.getSystemService(BluetoothManager::class.java)
    private val adapter: BluetoothAdapter?
        get() = bluetoothManager?.adapter

    @Volatile
    private var serverSocket: BluetoothServerSocket? = null

    @Volatile
    private var clientSocket: BluetoothSocket? = null

    @Volatile
    private var isRunning = false

    @Volatile
    private var activeClientGeneration = 0

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

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "startServer" -> result.success(startServer())
            "stopServer" -> {
                stopServer()
                result.success(null)
            }

            "sendStatus" -> {
                val raw = call.arguments as? String
                if (raw.isNullOrBlank()) {
                    result.success(false)
                } else {
                    result.success(sendRawToClient(raw))
                }
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(
        arguments: Any?,
        events: EventChannel.EventSink?,
    ) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun startServer(): Map<String, Any?> {
        if (!hasConnectPermission()) {
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
        if (isRunning) {
            return mapOf("success" to true)
        }

        return try {
            serverSocket =
                bluetoothAdapter.listenUsingInsecureRfcommWithServiceRecord(
                    SERVICE_NAME,
                    CONTROLLER_LINK_UUID,
                )
            isRunning = true
            startAcceptLoop()
            mapOf("success" to true)
        } catch (error: Exception) {
            isRunning = false
            serverSocket = null
            mapOf(
                "success" to false,
                "error" to (error.message ?: "Unable to start Bluetooth link."),
            )
        }
    }

    private fun startAcceptLoop() {
        Thread {
            while (isRunning) {
                val acceptedSocket = try {
                    serverSocket?.accept()
                } catch (_: Exception) {
                    null
                } ?: break

                attachClient(acceptedSocket)
            }
        }.apply {
            name = "robot-bt-accept"
            isDaemon = true
            start()
        }
    }

    private fun attachClient(socket: BluetoothSocket) {
        detachClient(emitDisconnected = false)
        clientSocket = socket
        activeClientGeneration += 1
        emitEvent(
            mapOf(
                "event" to "link_state",
                "connected" to true,
                "deviceName" to (socket.remoteDevice?.name ?: socket.remoteDevice?.address ?: "Controller"),
                "deviceAddress" to (socket.remoteDevice?.address ?: ""),
            ),
        )
        startClientReadLoop(socket, activeClientGeneration)
    }

    private fun startClientReadLoop(
        socket: BluetoothSocket,
        generation: Int,
    ) {
        Thread {
            try {
                val reader = BufferedReader(InputStreamReader(socket.inputStream))
                while (generation == activeClientGeneration) {
                    val line = reader.readLine() ?: break
                    handleIncomingLine(line)
                }
            } catch (_: Exception) {
            } finally {
                if (generation == activeClientGeneration) {
                    detachClient(emitDisconnected = true)
                }
            }
        }.apply {
            name = "robot-bt-client-$generation"
            isDaemon = true
            start()
        }
    }

    private fun handleIncomingLine(raw: String) {
        val json = try {
            JSONObject(raw)
        } catch (_: Exception) {
            return
        }

        when (json.optString("type")) {
            "ping" -> {
                sendRawToClient(
                    JSONObject()
                        .put("type", "pong")
                        .put("timestamp", json.optLong("timestamp"))
                        .toString(),
                )
            }

            "hello" -> {
                emitEvent(
                    mapOf(
                        "event" to "client_hello",
                        "raw" to raw,
                    ),
                )
            }
        }

        if (json.has("cmd")) {
            emitEvent(
                mapOf(
                    "event" to "command",
                    "raw" to raw,
                ),
            )
        }
    }

    private fun sendRawToClient(raw: String): Boolean {
        val socket = clientSocket ?: return false
        return try {
            socket.outputStream.write((raw + "\n").toByteArray())
            socket.outputStream.flush()
            true
        } catch (_: Exception) {
            detachClient(emitDisconnected = true)
            false
        }
    }

    private fun stopServer() {
        isRunning = false
        detachClient(emitDisconnected = true)
        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        serverSocket = null
    }

    private fun detachClient(emitDisconnected: Boolean) {
        activeClientGeneration += 1
        try {
            clientSocket?.close()
        } catch (_: Exception) {
        }
        clientSocket = null
        if (emitDisconnected) {
            emitEvent(
                mapOf(
                    "event" to "link_state",
                    "connected" to false,
                    "deviceName" to null,
                    "deviceAddress" to null,
                ),
            )
        }
    }

    private fun emitEvent(payload: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    private fun hasConnectPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
    }
}
