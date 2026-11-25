package com.dronesim.drone_simulator

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.dronesim.drone_simulator/storage"
        private const val PREFS_NAME = "drone_sim_records"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val prefs = applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "load" -> {
                        val key = call.argument<String>("key")
                        if (key == null) {
                            result.error("INVALID_KEY", "Key ausente", null)
                        } else {
                            result.success(prefs.getString(key, null))
                        }
                    }
                    "save" -> {
                        val key = call.argument<String>("key")
                        val value = call.argument<String>("value")
                        if (key == null || value == null) {
                            result.error("INVALID_ARGS", "Key ou value ausente", null)
                        } else {
                            prefs.edit().putString(key, value).apply()
                            result.success(true)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
