package com.foxlations.manga_reader

import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import com.foxlations.manga_reader.ext.ExtensionHost
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Volume-button page navigation: the manga/novel readers enable capture while open
    // (and disable it on exit), so ONLY there do we intercept the hardware volume keys —
    // tell Flutter which way to page and swallow the event so system volume doesn't
    // change. Everywhere else (incl. the video player) the buttons control volume normally.
    private var volumeKeyCapture = false
    private var volumeChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Same "foxlations/jvm" channel the app uses on iOS/desktop, but backed by the
        // Mihon-style ART loader (ExtensionHost) instead of an embedded JVM. Work runs on a
        // worker thread; the reply is posted to the main thread.
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "foxlations/jvm")
        val main = Handler(Looper.getMainLooper())
        val ctx = applicationContext

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "probe" -> result.success(true)
                "warmup" -> Thread {
                    runCatching { ExtensionHost.init(ctx) }
                    main.post { result.success("{\"ok\":true}") }
                }.start()
                "invoke" -> {
                    val req = call.arguments as? String
                    if (req == null) {
                        result.error("bad_args", "invoke expects a single String argument", null)
                    } else {
                        Thread {
                            val resp = ExtensionHost.invoke(ctx, req)
                            main.post { result.success(resp) }
                        }.start()
                    }
                }
                else -> result.notImplemented()
            }
        }

        val volume = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, "foxlations/volume_keys")
        volumeChannel = volume
        volume.setMethodCallHandler { call, result ->
            when (call.method) {
                "setCapture" -> {
                    volumeKeyCapture = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (volumeKeyCapture &&
            (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)) {
            val dir = if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down"
            // Report the press PHASE so Flutter can tell a tap from a hold: the first
            // ACTION_DOWN (repeatCount 0) is "down", the release is "up". Auto-repeat
            // downs are ignored — the hold is driven by the down→up interval in Dart.
            // Swallow every one so the system volume overlay never appears.
            when (event.action) {
                KeyEvent.ACTION_DOWN ->
                    if (event.repeatCount == 0) {
                        volumeChannel?.invokeMethod(
                            "onKey", mapOf("dir" to dir, "phase" to "down"))
                    }
                KeyEvent.ACTION_UP ->
                    volumeChannel?.invokeMethod(
                        "onKey", mapOf("dir" to dir, "phase" to "up"))
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
