package com.openbene.arindoornav

import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.ViewGroup
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import com.openbene.arindoornav.nav.*
import com.openbene.arindoornav.robot.OpenBotBleLink
import com.openbene.arindoornav.robot.RobotLink

/** Saved navigation values and explicitly requested, one-second motor tests. */
class PwmActivity : AppCompatActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private var link: RobotLink? = null
    private var tester: PwmPulseTester? = null
    private lateinit var status: TextView
    private val sliders = ArrayList<SeekBar>()
    private val testButtons = ArrayList<Button>()
    private val tick = object : Runnable {
        override fun run() {
            tester?.tick(SystemClock.elapsedRealtime() / 1000.0)
            val ble = link as? OpenBotBleLink
            val connected = link?.telemetry?.connected == true
            testButtons.forEach { it.isEnabled = connected }
            status.text = if (link == null) "保存后返回导航，在起点重新开始。" else
                "${if (connected) "已连接" else "未连接"} · ${AppState.describeLink()}\n" +
                "电压：${link?.telemetry?.voltage?.let { "%.2f V".format(it) } ?: "暂无读数"}\n" +
                "最近发送：${ble?.lastControlFrame ?: tester?.lastFrame ?: "c0,0"}\n${ble?.lastError ?: ""}"
            handler.postDelayed(this, 40)
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = "PWM 调节与测试"
        val body = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(32, 24, 32, 24) }
        setContentView(ScrollView(this).apply { addView(body) })
        fun text(value: String) = TextView(this).apply { text = value; textSize = 17f; body.addView(this) }
        text("分别设置直行、左转和右转 PWM（0–255）。保存后导航使用新值。测试前请将底盘架空。")
        val saved = PwmStore(this).load()
        for ((name, value) in listOf("直行" to saved.drive, "左转" to saved.leftTurn, "右转" to saved.rightTurn)) {
            val label = text("$name PWM：$value")
            val slider = SeekBar(this).apply { max = 255; progress = value }
            sliders.add(slider); body.addView(slider)
            slider.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: SeekBar, progress: Int, fromUser: Boolean) {
                    if (fromUser) tester?.stop()
                    label.text = "$name PWM：$progress"
                }
                override fun onStartTrackingTouch(s: SeekBar) { tester?.stop() }
                override fun onStopTrackingTouch(s: SeekBar) {}
            })
            val row = LinearLayout(this)
            for (delta in listOf(-1, 1)) row.addView(Button(this).apply {
                text = if (delta < 0) "−1" else "+1"
                setOnClickListener { tester?.stop(); slider.progress = (slider.progress + delta).coerceIn(0, 255) }
            }, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
            body.addView(row)
        }
        body.addView(Button(this).apply {
            text = "保存并应用"
            setOnClickListener {
                tester?.stop()
                runCatching { PwmStore(this@PwmActivity).save(values()) }
                    .onSuccess { Toast.makeText(this@PwmActivity, "PWM 已保存", Toast.LENGTH_SHORT).show() }
                    .onFailure { Toast.makeText(this@PwmActivity, "保存失败：${it.message}", Toast.LENGTH_LONG).show() }
            }
        })
        if (!intent.getBooleanExtra("settingsOnly", false)) {
            link = AppState.createLink(this); tester = PwmPulseTester(requireNotNull(link))
            for ((name, action) in listOf("前进 1 秒" to PwmTestAction.FORWARD, "左转 1 秒" to PwmTestAction.LEFT, "右转 1 秒" to PwmTestAction.RIGHT)) {
                val button = Button(this).apply {
                    text = name; isEnabled = false
                    setOnClickListener { tester?.start(action, values(), SystemClock.elapsedRealtime() / 1000.0) }
                }
                testButtons.add(button); body.addView(button)
            }
            body.addView(Button(this).apply { text = "立即停车"; setOnClickListener { tester?.stop() } })
        }
        status = text("")
        body.addView(Button(this).apply { text = "返回"; setOnClickListener { finish() } })
    }
    private fun values() = PwmSettings(sliders[0].progress, sliders[1].progress, sliders[2].progress)
    override fun onResume() { super.onResume(); handler.post(tick) }
    override fun onPause() { tester?.stop(); handler.removeCallbacks(tick); super.onPause() }
    override fun onDestroy() { tester?.stop(); link?.close(); super.onDestroy() }
}
