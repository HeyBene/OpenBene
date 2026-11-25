package io.openbene.zenoh

import android.app.Activity
import android.os.Bundle
import android.text.method.ScrollingMovementMethod
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.EditText
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
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
    private lateinit var loopbackDriveButton: Button
    private lateinit var loopbackStopButton: Button
    private lateinit var clearButton: Button
    private val transport = ZenohTransport(this)
    private val timeFormat = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(buildUi())
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
            appendLog("CMD $summary")
        }
    }

    override fun onSample(key: String, payload: ByteArray) {
        runOnUiThread { appendLog("RX $key ${payload.size}B") }
    }

    override fun onDestroy() {
        transport.close()
        super.onDestroy()
    }

    private fun setConnectedUi(connected: Boolean) {
        statusButton.isEnabled = connected
        sensorButton.isEnabled = connected
        videoButton.isEnabled = connected
        loopbackDriveButton.isEnabled = connected
        loopbackStopButton.isEnabled = connected
        disconnectButton.isEnabled = true
        connectButton.isEnabled = true
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

    companion object {
        private const val DEFAULT_ENDPOINT = "tcp/192.168.1.100:7447"
        private const val DEFAULT_ROBOT_ID = "rtr520"
    }
}
