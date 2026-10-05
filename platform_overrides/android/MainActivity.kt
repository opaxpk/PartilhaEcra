package __PACKAGE__

import android.app.ActivityManager
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter

/** Guarda o erro num ficheiro antes de a app fechar, para o mostrar no próximo arranque. */
class CrashHandler(
    private val context: Context,
    private val previous: Thread.UncaughtExceptionHandler?,
) : Thread.UncaughtExceptionHandler {
    override fun uncaughtException(thread: Thread, error: Throwable) {
        try {
            val sw = StringWriter()
            error.printStackTrace(PrintWriter(sw))
            File(context.filesDir, "last_crash.txt").writeText("Thread: ${thread.name}\n$sw")
        } catch (_: Throwable) {
        }
        previous?.uncaughtException(thread, error)
    }
}

class MainActivity : FlutterActivity() {
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        val current = Thread.getDefaultUncaughtExceptionHandler()
        if (current !is CrashHandler) {
            Thread.setDefaultUncaughtExceptionHandler(CrashHandler(applicationContext, current))
        }
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "partilhaecra/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCaptureService" -> {
                        val intent = Intent(this, ScreenCaptureService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stopCaptureService" -> {
                        stopService(Intent(this, ScreenCaptureService::class.java))
                        result.success(true)
                    }
                    "acquireMulticastLock" -> {
                        if (multicastLock == null) {
                            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                            multicastLock = wifi.createMulticastLock("PartilhaEcraDiscovery").apply {
                                setReferenceCounted(false)
                                acquire()
                            }
                        }
                        result.success(true)
                    }
                    "releaseMulticastLock" -> {
                        multicastLock?.let { if (it.isHeld) it.release() }
                        multicastLock = null
                        result.success(true)
                    }
                    "deviceInfo" -> {
                        val uiMode = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                        val isTv = uiMode.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
                            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
                            !packageManager.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
                        result.success(
                            mapOf(
                                "manufacturer" to Build.MANUFACTURER,
                                "model" to Build.MODEL,
                                "hardware" to Build.HARDWARE,
                                "board" to Build.BOARD,
                                "isTv" to isTv,
                            )
                        )
                    }
                    "crashReport" -> {
                        try {
                            result.success(collectCrashReport())
                        } catch (e: Throwable) {
                            result.error("crashReport", e.toString(), null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun collectCrashReport(): Map<String, Any?> {
        val crashFile = File(filesDir, "last_crash.txt")
        val javaCrash = if (crashFile.exists()) crashFile.readText().take(8000) else null
        crashFile.delete()

        val exits = mutableListOf<Map<String, Any?>>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            for (info in am.getHistoricalProcessExitReasons(packageName, 0, 5)) {
                var trace: String? = null
                if (info.reason == android.app.ApplicationExitInfo.REASON_ANR) {
                    trace = try {
                        info.traceInputStream?.bufferedReader()?.use { it.readText().take(6000) }
                    } catch (_: Throwable) {
                        null
                    }
                }
                exits.add(
                    mapOf(
                        "reason" to info.reason,
                        "description" to (info.description ?: ""),
                        "timestamp" to info.timestamp,
                        "status" to info.status,
                        "importance" to info.importance,
                        "pssKb" to info.pss,
                        "trace" to trace,
                    )
                )
            }
        }
        return mapOf(
            "javaCrash" to javaCrash,
            "exits" to exits,
            "device" to "${Build.MANUFACTURER} ${Build.MODEL}",
            "android" to "${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
        )
    }

    override fun onDestroy() {
        multicastLock?.let { if (it.isHeld) it.release() }
        multicastLock = null
        super.onDestroy()
    }
}
