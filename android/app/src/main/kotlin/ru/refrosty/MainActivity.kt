package ru.refrosty

import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
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
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "ru.refrosty/browser",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasChromiumBrowser" -> result.success(hasChromiumBrowserInstalled())
                "launchUrlInChromeOrChooser" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrEmpty()) {
                        result.error("INVALID_ARGUMENT", "url is required", null)
                    } else {
                        result.success(launchUrlInChromeOrChooser(url))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasChromiumBrowserInstalled(): Boolean {
        val pm = packageManager
        for (pkg in CHROMIUM_PACKAGES) {
            if (isPackageInstalled(pm, pkg)) return true
        }
        return false
    }

    @Suppress("DEPRECATION")
    private fun isPackageInstalled(pm: PackageManager, packageName: String): Boolean = try {
        pm.getPackageInfo(packageName, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private fun launchUrlInChromeOrChooser(url: String): Boolean {
        val uri = try {
            Uri.parse(url)
        } catch (e: Exception) {
            Log.w(TAG, "launchUrlInChromeOrChooser: failed to parse url", e)
            return false
        }

        for (pkg in CHROMIUM_PACKAGES) {
            if (!isPackageInstalled(packageManager, pkg)) continue
            val chromeIntent = Intent(Intent.ACTION_VIEW, uri)
                .setPackage(pkg)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(chromeIntent)
                return true
            } catch (e: Exception) {
                Log.w(TAG, "launchUrlInChromeOrChooser: failed to start $pkg", e)
            }
        }

        val viewIntent = Intent(Intent.ACTION_VIEW, uri)
        val chooser = Intent.createChooser(viewIntent, "Выберите браузер")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            startActivity(chooser)
            true
        } catch (e: Exception) {
            Log.w(TAG, "launchUrlInChromeOrChooser: no activity to handle view intent", e)
            false
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

        private val CHROMIUM_PACKAGES = arrayOf(
            "com.android.chrome",
            "com.chrome.beta",
            "com.chrome.dev",
            "com.chrome.canary",
            "org.chromium.chrome",
        )
    }
}


