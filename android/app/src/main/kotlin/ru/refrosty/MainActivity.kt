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
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.media3.common.util.UnstableApi
import cl.puntito.simple_pip_mode.PipCallbackHelperActivityWrapper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import ru.refrosty.player.NativePlayerFactory

class MainActivity : PipCallbackHelperActivityWrapper() {

    private var pipEventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /// One-shot lifecycle observer that waits for the next ON_RESUME or ON_STOP
    /// after exiting PiP, used to distinguish "expanded" from "dismissed".
    private var pipExitLifecycleObserver: LifecycleEventObserver? = null

    /// Fallback timeout to guarantee we emit a pip-exit event even if the next
    /// lifecycle transition never arrives (e.g., activity is destroyed or
    /// the main thread is stalled longer than the timeout).
    private val pipExitTimeoutRunnable = Runnable {
        val observer = pipExitLifecycleObserver ?: return@Runnable
        pipExitLifecycleObserver = null
        lifecycle.removeObserver(observer)

        // Inspect the current state at timeout as a best-effort guess.
        // If we're at least STARTED, likely expanded; otherwise dismissed.
        val state = lifecycle.currentState
        val event = if (state.isAtLeast(Lifecycle.State.RESUMED)) "expanded" else "dismissed"
        Log.d(TAG, "pip exited: timeout fallback -> $event (state=$state)")
        pipEventSink?.success(event)
    }

    override fun onPictureInPictureModeChanged(active: Boolean, newConfig: Configuration?) {
        Log.d(TAG, "onPictureInPictureModeChanged: active=$active (pip ${if (active) "entered" else "exited"})")
        if (!active) {
            resolvePipExitOutcome()
        }
        super.onPictureInPictureModeChanged(active, newConfig)
    }

    /// Determines whether PiP exit was "expanded" (user returned to fullscreen)
    /// or "dismissed" (PiP swiped away / closed) by inspecting lifecycle.
    ///
    /// The previous implementation used a fixed 150ms delay and checked
    /// `lifecycle.currentState` — that is unreliable on slow devices / when
    /// the main thread is stalled (e.g., Samsung One UI with heavy webview
    /// work), because the ON_RESUME transition may arrive later than 150ms,
    /// causing expanded-PiP to be misreported as dismissed.
    ///
    /// Here we instead wait for the actual next lifecycle event:
    ///   - ON_RESUME  -> "expanded"
    ///   - ON_STOP    -> "dismissed"
    /// with a generous timeout fallback as a safety net.
    private fun resolvePipExitOutcome() {
        // Cancel any in-flight observer from a previous PiP cycle.
        pipExitLifecycleObserver?.let { lifecycle.removeObserver(it) }
        pipExitLifecycleObserver = null
        mainHandler.removeCallbacks(pipExitTimeoutRunnable)

        val currentState = lifecycle.currentState

        // Fast path: already at the terminal state when the callback fires.
        if (currentState == Lifecycle.State.RESUMED) {
            Log.d(TAG, "pip exited: expanded (already RESUMED)")
            pipEventSink?.success("expanded")
            return
        }
        if (!currentState.isAtLeast(Lifecycle.State.STARTED)) {
            // CREATED / DESTROYED / INITIALIZED: activity is effectively gone.
            Log.d(TAG, "pip exited: dismissed (state=$currentState)")
            pipEventSink?.success("dismissed")
            return
        }

        // STARTED: waiting for the next ON_RESUME or ON_STOP.
        val observer = object : LifecycleEventObserver {
            override fun onStateChanged(source: LifecycleOwner, event: Lifecycle.Event) {
                when (event) {
                    Lifecycle.Event.ON_RESUME -> {
                        finishPipExit("expanded", "ON_RESUME")
                    }
                    Lifecycle.Event.ON_STOP,
                    Lifecycle.Event.ON_DESTROY -> {
                        finishPipExit("dismissed", event.name)
                    }
                    else -> Unit
                }
            }
        }
        pipExitLifecycleObserver = observer
        lifecycle.addObserver(observer)

        // Safety: if neither event arrives in ~3s, fall back to a best guess.
        mainHandler.postDelayed(pipExitTimeoutRunnable, 3000)
    }

    private fun finishPipExit(event: String, reason: String) {
        val observer = pipExitLifecycleObserver ?: return
        pipExitLifecycleObserver = null
        lifecycle.removeObserver(observer)
        mainHandler.removeCallbacks(pipExitTimeoutRunnable)
        Log.d(TAG, "pip exited: $event ($reason)")
        pipEventSink?.success(event)
    }

    @androidx.annotation.OptIn(UnstableApi::class)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Register the native ExoPlayer-backed PlatformView used by Flutter's
        // NativePlayerView for low-latency Twitch live playback. View type id
        // is referenced from Dart via const `_viewType` in native_player_view.dart.
        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "ru.refrosty/native_player",
                NativePlayerFactory(flutterEngine.dartExecutor.binaryMessenger),
            )

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


