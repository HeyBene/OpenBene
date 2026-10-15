package com.openbene.openbene_arcore

import android.content.Intent
import com.openbene.arindoornav.MainActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class FlutterEntryActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.openbene/navigation")
            .setMethodCallHandler { call, result ->
                if (call.method != "openNavigation") { result.notImplemented(); return@setMethodCallHandler }
                try {
                    startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
                    result.success(null)
                } catch (error: Exception) { result.error("navigation_launch", error.message, null) }
            }
    }
}
