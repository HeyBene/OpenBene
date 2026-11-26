package io.openbene.zenoh.capture

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager

/**
 * Accelerometer and gyroscope sampling.
 *
 * [Sample.timestampNs] uses the same clock as the camera timestamps
 * (SystemClock.elapsedRealtimeNanos), which is what the PC recorder expects.
 */
class ImuReader(context: Context) : SensorEventListener {
    data class Sample(
        val accelerometer: Triple<Double, Double, Double>?,
        val gyroscope: Triple<Double, Double, Double>?,
        val timestampNs: Long,
    )

    private val manager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val accelerometer = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
    private val gyroscope = manager.getDefaultSensor(Sensor.TYPE_GYROSCOPE)

    @Volatile
    var latest: Sample? = null
        private set

    val available: Boolean get() = accelerometer != null || gyroscope != null

    fun start() {
        accelerometer?.let { manager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
        gyroscope?.let { manager.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
    }

    fun stop() {
        runCatching { manager.unregisterListener(this) }
    }

    override fun onSensorChanged(event: SensorEvent) {
        val values = event.values
        if (values.size < 3) return
        val sample = Triple(values[0].toDouble(), values[1].toDouble(), values[2].toDouble())
        val previous = latest
        latest = when (event.sensor.type) {
            Sensor.TYPE_ACCELEROMETER -> Sample(sample, previous?.gyroscope, event.timestamp)
            Sensor.TYPE_GYROSCOPE -> Sample(previous?.accelerometer, sample, event.timestamp)
            else -> previous
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
}
