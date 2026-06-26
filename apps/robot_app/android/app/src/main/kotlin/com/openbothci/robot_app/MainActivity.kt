package com.openbothci.robot_app

import android.util.Log
import android.view.InputDevice
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "RobotGamepadMain"
    }

    private lateinit var phoneControllerLinkBridge: PhoneControllerLinkBridge
    private lateinit var robotLinkClientBridge: RobotLinkClientBridge
    private lateinit var gamepadInputBridge: GamepadInputBridge
    private lateinit var robotBackendBridge: RobotBackendBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        phoneControllerLinkBridge = PhoneControllerLinkBridge(this)
        phoneControllerLinkBridge.attach(flutterEngine)

        robotLinkClientBridge = RobotLinkClientBridge(this)
        robotLinkClientBridge.attach(flutterEngine)

        gamepadInputBridge = GamepadInputBridge()
        gamepadInputBridge.attach(flutterEngine)

        robotBackendBridge = RobotBackendBridge(this)
        robotBackendBridge.attach(flutterEngine)
    }

    override fun dispatchKeyEvent(event: android.view.KeyEvent): Boolean {
        val source = event.source
        val deviceName = event.device?.name ?: "unknown"
        val isControllerLike =
            (source and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
            (source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK ||
            (source and InputDevice.SOURCE_DPAD) == InputDevice.SOURCE_DPAD
        if (isControllerLike) {
            Log.d(TAG, "dispatchKeyEvent source=$source code=${event.keyCode} action=${event.action} device=$deviceName")
        }
        if (this::gamepadInputBridge.isInitialized && gamepadInputBridge.handleKeyEvent(event)) {
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onGenericMotionEvent(event: android.view.MotionEvent): Boolean {
        val source = event.source
        val deviceName = event.device?.name ?: "unknown"
        val isControllerLike =
            (source and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
            (source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK ||
            (source and InputDevice.SOURCE_DPAD) == InputDevice.SOURCE_DPAD
        if (isControllerLike) {
            Log.d(TAG, "onGenericMotionEvent source=$source action=${event.actionMasked} device=$deviceName")
        }
        if (this::gamepadInputBridge.isInitialized && gamepadInputBridge.handleMotionEvent(event)) {
            return true
        }
        return super.onGenericMotionEvent(event)
    }
}
