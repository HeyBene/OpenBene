package io.openbene.zenoh

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.text.method.ScrollingMovementMethod
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import io.openbene.zenoh.ble.OpenBotBle
import io.openbene.zenoh.capture.CaptureController
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : Activity(), ZenohTransport.Listener {

    private lateinit var endpointInput: EditText
    private lateinit var robotIdInput: EditText
    private lateinit var statusView: TextView
    private lateinit var logView: TextView
    private lateinit var connectButton: Button
    private lateinit var disconnectButton: Button
    private lateinit var statusButton: Button
    private lateinit var sensorButton: Button
    private lateinit var videoButton: Button
    private lateinit var captureButton: Button
    private lateinit var startCaptureButton: Button
    private lateinit var captureStopButton: Button
    private lateinit var captureStatsView: TextView
    private lateinit var bleConnectButton: Button
    private lateinit var bleDisconnectButton: Button
    private lateinit var bleStatusView: TextView
    private lateinit var sessionStartButton: Button
    private lateinit var sessionStopButton: Button
    private lateinit var loopbackDriveButton: Button
    private lateinit var loopbackStopButton: Button
    private lateinit var clearButton: Button
    private val transport = ZenohTransport(this)
    private val capture by lazy { CaptureController(this, transport) }
    private val ble by lazy { OpenBotBle(this, BleListener()) }
    private var pendingAction: String? = null
    private val timeFormat = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(buildUi())
        capture.listener = object : CaptureController.Listener {
            override fun onCaptureState(message: String) {
                runOnUiThread { appendLog(message) }
            }

            override fun onCaptureStats(text: String) {
                runOnUiThread { captureStatsView.text = text }
            }
        }
        val prefs = getSharedPreferences("zenoh_transport", MODE_PRIVATE)
        endpointInput.setText(prefs.getString("endpoint", DEFAULT_ENDPOINT))
        robotIdInput.setText(prefs.getString("robot_id", DEFAULT_ROBOT_ID))
        setConnectedUi(false)
        appendLog("Standalone Zenoh transport probe. Existing OpenBene apps are untouched.")
    }

    private fun buildUi(): ScrollView {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(24), dp(20), dp(24))
        }

        root.addView(title("OpenBene Zenoh Transport"))
        root.addView(hint("Android 30+ / Zenoh Kotlin 1.10.2 / explicit PC endpoint"))
        root.addView(label("PC endpoint"))
        endpointInput = EditText(this).apply {
            hint = "tcp/192.168.1.100:7447"
            setSingleLine(true)
        }
        root.addView(endpointInput, matchWidth())
        root.addView(label("Robot ID"))
        robotIdInput = EditText(this).apply {
            hint = "rtr520"
            setSingleLine(true)
        }
        root.addView(robotIdInput, matchWidth())

        val connectRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        connectButton = button("连接") { connect() }
        disconnectButton = button("断开") { transport.disconnect() }
        connectRow.addView(connectButton, weighted())
        connectRow.addView(disconnectButton, weighted())
        root.addView(connectRow, matchWidth())

        statusView = TextView(this).apply {
            text = "Not connected"
            textSize = 15f
            setPadding(0, dp(10), 0, dp(10))
        }
        root.addView(statusView, matchWidth())

        val publishRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        statusButton = button("状态") {
            runCatching { transport.publishHeartbeat() }.onFailure { appendLog("Status failed: ${it.message}") }
        }
        sensorButton = button("传感器") {
            runCatching { transport.publishSensors() }.onFailure { appendLog("Sensors failed: ${it.message}") }
        }
        videoButton = button("二进制帧") {
            runCatching {
                transport.publishVideoFrame(ByteArray(1024) { (it % 251).toByte() })
            }.onFailure { appendLog("Video failed: ${it.message}") }
        }
        publishRow.addView(statusButton, weighted())
        publishRow.addView(sensorButton, weighted())
        publishRow.addView(videoButton, weighted())
        root.addView(publishRow, matchWidth())

        val captureRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        captureButton = button("采集帧") {
            runCatching { transport.publishCaptureFrame(syntheticCaptureFrame()) }
                .onFailure { appendLog("Capture failed: ${it.message}") }
        }
        sessionStartButton = button("开始录制") {
            runCatching { transport.publishSessionEvent(SessionEvent.Start) }
                .onFailure { appendLog("Session failed: ${it.message}") }
        }
        sessionStopButton = button("停止录制") {
            runCatching { transport.publishSessionEvent(SessionEvent.Stop) }
                .onFailure { appendLog("Session failed: ${it.message}") }
        }
        captureRow.addView(captureButton, weighted())
        captureRow.addView(sessionStartButton, weighted())
        captureRow.addView(sessionStopButton, weighted())
        root.addView(captureRow, matchWidth())
        root.addView(hint("采集帧走 .../frame（ZPKD，与 iOS 同格式）；录制按钮只发 session 事件，文件由 PC 端写 MCAP。"))

        val captureControlRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        startCaptureButton = button("开始采集") { requestCapture() }
        captureStopButton = button("停止采集") { capture.stop() }
        captureControlRow.addView(startCaptureButton, weighted())
        captureControlRow.addView(captureStopButton, weighted())
        root.addView(captureControlRow, matchWidth())
        captureStatsView = TextView(this).apply {
            text = "采集未启动（C 档：相机 + IMU，不需要 ARCore）"
            textSize = 12f
            setTextColor(0xFF374151.toInt())
            setPadding(0, dp(4), 0, dp(8))
        }
        root.addView(captureStatsView, matchWidth())

        val bleRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        bleConnectButton = button("连接底盘") { requestBle() }
        bleDisconnectButton = button("断开底盘") { ble.disconnect() }
        bleRow.addView(bleConnectButton, weighted())
        bleRow.addView(bleDisconnectButton, weighted())
        root.addView(bleRow, matchWidth())
        bleStatusView = TextView(this).apply {
            text = "底盘未连接"
            textSize = 12f
            setTextColor(0xFF374151.toInt())
            setPadding(0, dp(4), 0, dp(8))
        }
        root.addView(bleStatusView, matchWidth())
        root.addView(hint("底盘走 BLE，协议 c<左>,<右>；1.5 秒收不到新指令会自动停车。"))

        val loopbackRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        loopbackDriveButton = button("环回前进") {
            runCatching { transport.publishLoopbackDrive() }.onFailure { appendLog("Loopback failed: ${it.message}") }
        }
        loopbackStopButton = button("环回停车") {
            runCatching { transport.publishLoopbackStop() }.onFailure { appendLog("Loopback failed: ${it.message}") }
        }
        loopbackRow.addView(loopbackDriveButton, weighted())
        loopbackRow.addView(loopbackStopButton, weighted())
        root.addView(loopbackRow, matchWidth())

        root.addView(hint("环回按钮只用于没有 PC 时验证订阅链路；正式链路由 PC 发布 cmd。"))
        clearButton = button("清空日志") { logView.text = "" }
        root.addView(clearButton, matchWidth())

        logView = TextView(this).apply {
            textSize = 12f
            typeface = android.graphics.Typeface.MONOSPACE
            movementMethod = ScrollingMovementMethod()
            setTextIsSelectable(true)
            setPadding(dp(8), dp(8), dp(8), dp(8))
            setBackgroundColor(0xFFF3F3F3.toInt())
            minHeight = dp(280)
        }
        root.addView(logView, matchWidth())
        return ScrollView(this).apply { addView(root) }
    }

    private fun connect() {
        val endpoint = endpointInput.text.toString()
        val robotId = robotIdInput.text.toString()
        getSharedPreferences("zenoh_transport", MODE_PRIVATE).edit()
            .putString("endpoint", endpoint)
            .putString("robot_id", robotId)
            .apply()
        appendLog("Connecting to $endpoint as robot=$robotId")
        transport.connect(endpoint, robotId)
    }

    override fun onState(message: String) {
        runOnUiThread {
            statusView.text = message
            appendLog(message)
            setConnectedUi(transport.isConnected)
        }
    }

    override fun onCommand(command: RobotCommand, raw: String) {
        runOnUiThread {
            val summary = when (command) {
                is RobotCommand.Drive -> "DRIVE left=${command.left} right=${command.right} seq=${command.sequence} ttl=${command.ttlMs}ms"
                is RobotCommand.Stop -> "STOP seq=${command.sequence}"
                is RobotCommand.Unknown -> "UNKNOWN ${command.reason}"
            }
            when (command) {
                is RobotCommand.Drive -> if (ble.isConnected) ble.drive(command.left, command.right)
                is RobotCommand.Stop -> if (ble.isConnected) ble.stop()
                is RobotCommand.Unknown -> Unit
            }
            appendLog("CMD $summary")
        }
    }

    override fun onSample(key: String, payload: ByteArray) {
        runOnUiThread { appendLog("RX $key ${payload.size}B") }
    }

    override fun onDestroy() {
        runCatching { capture.stop() }
        runCatching { ble.disconnect() }
        transport.close()
        super.onDestroy()
    }

    private fun setConnectedUi(connected: Boolean) {
        statusButton.isEnabled = connected
        sensorButton.isEnabled = connected
        videoButton.isEnabled = connected
        captureButton.isEnabled = connected
        startCaptureButton.isEnabled = connected
        captureStopButton.isEnabled = connected
        sessionStartButton.isEnabled = connected
        sessionStopButton.isEnabled = connected
        loopbackDriveButton.isEnabled = connected
        loopbackStopButton.isEnabled = connected
        bleConnectButton.isEnabled = true
        bleDisconnectButton.isEnabled = true
        disconnectButton.isEnabled = true
        connectButton.isEnabled = true
    }

    /**
     * Synthetic capture frame for transport testing: a small valid JPEG plus an
     * identity pose. Depth and confidence planes need the real camera pipeline.
     */
    private fun syntheticCaptureFrame(): CaptureFrame {
        val width = 64
        val height = 48
        val yuv = ByteArray(width * height * 3 / 2) { index -> (index % 251).toByte() }
        val jpeg = java.io.ByteArrayOutputStream().use { out ->
            android.graphics.YuvImage(
                yuv,
                android.graphics.ImageFormat.NV21,
                width,
                height,
                null,
            ).compressToJpeg(android.graphics.Rect(0, 0, width, height), 80, out)
            out.toByteArray()
        }
        return CaptureFrame(
            frameId = System.currentTimeMillis() % Int.MAX_VALUE,
            timestampNs = System.currentTimeMillis() * 1_000_000L,
            rgbJpeg = jpeg,
            pose = floatArrayOf(
                1f, 0f, 0f, 0f,
                0f, 1f, 0f, 0f,
                0f, 0f, 1f, 0f,
                0f, 0f, 0f, 1f,
            ),
            metadata = FrameMetadata(
                width = width,
                height = height,
                trackingState = "synthetic",
                depthSource = "none",
            ),
        )
    }

    private fun appendLog(line: String) {
        val stamped = "${timeFormat.format(Date())}  $line"
        logView.append("$stamped\n")
        if (logView.lineCount > 400) {
            val text = logView.text.toString()
            logView.text = text.substring(text.indexOf('\n', text.length / 2).coerceAtLeast(0) + 1)
        }
    }

    private fun title(text: String) = TextView(this).apply {
        this.text = text
        textSize = 24f
        setPadding(0, 0, 0, dp(4))
    }

    private fun hint(text: String) = TextView(this).apply {
        this.text = text
        textSize = 12f
        setTextColor(0xFF666666.toInt())
        setPadding(0, dp(2), 0, dp(8))
    }

    private fun label(text: String) = TextView(this).apply {
        this.text = text
        textSize = 13f
        setPadding(0, dp(8), 0, dp(2))
    }

    private fun button(text: String, onClick: () -> Unit) = Button(this).apply {
        this.text = text
        setOnClickListener { onClick() }
    }

    private fun matchWidth() = LinearLayout.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.WRAP_CONTENT,
    )

    private fun weighted() = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun requestCapture() {
        if (!transport.isConnected) {
            appendLog("先连接 PC 再开始采集")
            return
        }
        val needed = arrayOf(Manifest.permission.CAMERA)
        if (needed.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) {
            startCapture()
            return
        }
        pendingAction = ACTION_CAPTURE
        requestPermissions(needed, REQUEST_CAMERA)
    }

    private fun startCapture() {
        if (capture.isRunning) return
        appendLog("启动 C 档采集：Camera2 1280x720 @15fps + IMU")
        capture.start()
    }

    private fun requestBle() {
        val needed = blePermissions()
        if (needed.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) {
            ble.connect()
            return
        }
        pendingAction = ACTION_BLE
        requestPermissions(needed, REQUEST_BLE)
    }

    private fun blePermissions(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        val action = pendingAction
        pendingAction = null
        if (!granted) {
            appendLog("权限被拒绝，请到系统设置里允许相机 / 蓝牙权限")
            return
        }
        when (action) {
            ACTION_CAPTURE -> startCapture()
            ACTION_BLE -> ble.connect()
        }
    }

    private inner class BleListener : OpenBotBle.Listener {
        override fun onBleState(message: String) {
            runOnUiThread {
                bleStatusView.text = message
                appendLog("BLE $message")
            }
        }
    }

    companion object {
        private const val DEFAULT_ENDPOINT = "tcp/192.168.1.100:7447"
        private const val DEFAULT_ROBOT_ID = "rtr520"
        private const val REQUEST_CAMERA = 11
        private const val REQUEST_BLE = 12
        private const val ACTION_CAPTURE = "capture"
        private const val ACTION_BLE = "ble"
    }
}
