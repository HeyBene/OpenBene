package com.openbene.arindoornav.ar

import android.content.Context
import android.hardware.display.DisplayManager
import android.view.Display
import android.view.WindowManager
import com.google.ar.core.Session

/**
 * Keeps the AR viewport in step with the display rotation, following the helper
 * shipped with the ARCore samples.
 */
class DisplayRotationHelper(context: Context) : DisplayManager.DisplayListener {

    private val display: Display =
        (context.getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay
    private val displayManager =
        context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager

    private var viewportChanged = false
    private var viewportWidth = 0
    private var viewportHeight = 0

    fun onResume() {
        displayManager.registerDisplayListener(this, null)
    }

    fun onPause() {
        displayManager.unregisterDisplayListener(this)
    }

    fun onSurfaceChanged(width: Int, height: Int) {
        viewportWidth = width
        viewportHeight = height
        viewportChanged = true
    }

    /** Push the new viewport into the session before the next frame is rendered. */
    fun updateSessionIfNeeded(session: Session) {
        if (viewportChanged) {
            session.setDisplayGeometry(display.rotation, viewportWidth, viewportHeight)
            viewportChanged = false
        }
    }

    val rotation: Int get() = display.rotation

    /**
     * Rotation to pass to the barcode scanner so that it sees the camera image
     * the way the user does. The sensor is mounted 90 degrees off on most
     * phones, and the activity is locked to portrait.
     */
    fun cameraImageRotationDegrees(sensorOrientationDegrees: Int, frontFacing: Boolean = false): Int {
        var rotation = (sensorOrientationDegrees - display.rotation + 360) % 360
        if (frontFacing) rotation = (360 - rotation + 360) % 360
        return rotation
    }

    fun viewportAspectRatio(): Double =
        if (viewportHeight == 0) 0.0 else viewportWidth.toDouble() / viewportHeight

    override fun onDisplayAdded(displayId: Int) = Unit

    override fun onDisplayRemoved(displayId: Int) = Unit

    override fun onDisplayChanged(displayId: Int) {
        if (displayId == display.displayId) viewportChanged = true
    }
}
