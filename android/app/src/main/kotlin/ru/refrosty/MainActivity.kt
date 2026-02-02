package ru.refrosty

import android.os.Build
import android.view.WindowManager
import cl.puntito.simple_pip_mode.PipCallbackHelperActivityWrapper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : PipCallbackHelperActivityWrapper() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
}


