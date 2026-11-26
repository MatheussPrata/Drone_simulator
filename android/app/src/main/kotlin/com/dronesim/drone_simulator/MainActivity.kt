package com.dronesim.drone_simulator

import android.content.Context
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.dronesim.drone_simulator/storage"
        private const val GAMEPAD_CHANNEL = "com.dronesim.drone_simulator/gamepad"
        private const val PREFS_NAME = "drone_sim_records"
    }

    private var gamepadChannel: MethodChannel? = null

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

        gamepadChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GAMEPAD_CHANNEL)
    }

    override fun onGenericMotionEvent(event: MotionEvent): Boolean {
        val isJoystick = (event.source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
        if (isJoystick && event.action == MotionEvent.ACTION_MOVE) {
            val device = event.device
            val leftX = event.getAxisValue(MotionEvent.AXIS_X).toDouble()
            val leftY = event.getAxisValue(MotionEvent.AXIS_Y).toDouble()

            val rightXAxis = if (device?.getMotionRange(MotionEvent.AXIS_Z, event.source) != null) {
                MotionEvent.AXIS_Z
            } else {
                MotionEvent.AXIS_RX
            }
            val rightYAxis = if (device?.getMotionRange(MotionEvent.AXIS_RZ, event.source) != null) {
                MotionEvent.AXIS_RZ
            } else {
                MotionEvent.AXIS_RY
            }

            val rightX = event.getAxisValue(rightXAxis).toDouble()
            val rightY = event.getAxisValue(rightYAxis).toDouble()

            gamepadChannel?.invokeMethod(
                "axes",
                mapOf(
                    "leftX" to leftX,
                    "leftY" to leftY,
                    "rightX" to rightX,
                    "rightY" to rightY,
                    "device" to (device?.name ?: "Gamepad"),
                ),
            )
            return true
        }
        return super.onGenericMotionEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        val isGamepad = (event.source and InputDevice.SOURCE_GAMEPAD) == InputDevice.SOURCE_GAMEPAD ||
            (event.source and InputDevice.SOURCE_JOYSTICK) == InputDevice.SOURCE_JOYSTICK
        if (isGamepad && event.repeatCount == 0) {
            val action = when (keyCode) {
                KeyEvent.KEYCODE_BUTTON_A -> "arm_takeoff"
                KeyEvent.KEYCODE_BUTTON_B -> "land"
                KeyEvent.KEYCODE_BUTTON_X -> "cycle_flight_mode"
                KeyEvent.KEYCODE_BUTTON_Y -> "toggle_camera"
                KeyEvent.KEYCODE_BUTTON_R1 -> "rth"
                KeyEvent.KEYCODE_BUTTON_START, KeyEvent.KEYCODE_BUTTON_SELECT -> "reset"
                else -> null
            }
            if (action != null) {
                gamepadChannel?.invokeMethod("button", mapOf("action" to action))
                return true
            }
        }
        return super.onKeyDown(keyCode, event)
    }
}
