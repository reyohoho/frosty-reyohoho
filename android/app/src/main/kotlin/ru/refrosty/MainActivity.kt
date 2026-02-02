package ru.refrosty

import android.content.res.Configuration
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import androidx.lifecycle.Lifecycle
import cl.puntito.simple_pip_mode.PipCallbackHelperActivityWrapper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : PipCallbackHelperActivityWrapper() {

    private var pipEventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onPictureInPictureModeChanged(active: Boolean, newConfig: Configuration?) {
        Log.d(TAG, "onPictureInPictureModeChanged: active=$active (pip ${if (active) "entered" else "exited"})")
        if (!active) {
            // Distinguish "expanded back to app" vs "dismissed (swiped away)":
            // after a short delay, if activity is resumed we're full screen (expanded); else dismissed.
            mainHandler.postDelayed({
                val resumed = lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
                val event = if (resumed) "expanded" else "dismissed"
                Log.d(TAG, "pip exited: $event (resumed=$resumed)")
                pipEventSink?.success(event)
            }, 150)
        }
        super.onPictureInPictureModeChanged(active, newConfig)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "ru.refrosty/pip").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    pipEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    pipEventSink = null
                }
            }
        )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ru.refrosty/display_cutout",
        ).setMethodCallHandler { call, result ->
            if (call.method == "setDisplayUnderCutout") {
                val enabled = call.arguments as? Boolean ?: false
                setDisplayUnderCutout(enabled)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun setDisplayUnderCutout(enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode = if (enabled) {
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
                } else {
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_NEVER
                }
            }
        }
    }

    companion object {
        private const val TAG = "RefrostyPIP"
    }
}


