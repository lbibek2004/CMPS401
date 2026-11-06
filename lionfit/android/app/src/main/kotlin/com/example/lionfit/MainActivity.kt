package com.example.lionfit

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity, not FlutterActivity: the `health` plugin requests
// Health Connect permissions with registerForActivityResult, which needs a
// FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // The rest timer's "time's up" buzz. Flutter's HapticFeedback only
        // does short taps; this is a single long pulse (lib/core/platform/).
        MethodChannel(messenger, "lionfit/vibration")
            .setMethodCallHandler { call, result ->
                if (call.method != "vibrate") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val millis = (call.argument<Int>("milliseconds") ?: 3000).toLong()
                vibrator()?.let { v ->
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        v.vibrate(
                            VibrationEffect.createOneShot(millis, VibrationEffect.DEFAULT_AMPLITUDE)
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        v.vibrate(millis)
                    }
                }
                result.success(null)
            }

        // "Manage access" on the Home health card. The plugin can request
        // permissions but cannot open Health Connect's settings, which is
        // the only way back in after the user has declined twice.
        MethodChannel(messenger, "lionfit/health_connect")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openSettings" -> result.success(openHealthConnectSettings())
                    else -> result.notImplemented()
                }
            }
    }

    // Health Connect opens LionFit with a "show your privacy policy" intent
    // from its permission screen. Start Flutter on that page instead of home.
    override fun getInitialRoute(): String? =
        if (intent.isHealthPrivacyRequest()) HEALTH_PRIVACY_ROUTE else super.getInitialRoute()

    // Same, when LionFit is already running.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.isHealthPrivacyRequest()) {
            flutterEngine?.navigationChannel?.pushRouteInformation(HEALTH_PRIVACY_ROUTE)
        }
    }

    private fun openHealthConnectSettings(): Boolean {
        for (action in HEALTH_CONNECT_SETTINGS_ACTIONS) {
            try {
                startActivity(Intent(action))
                return true
            } catch (_: ActivityNotFoundException) {
                // Try the next one.
            }
        }
        return false
    }

    private fun vibrator(): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }

    private fun Intent?.isHealthPrivacyRequest(): Boolean =
        this?.action in HEALTH_PRIVACY_ACTIONS

    private companion object {
        /// Must match Routes.healthPrivacy in lib/core/router/routes.dart.
        const val HEALTH_PRIVACY_ROUTE = "/health-privacy"

        val HEALTH_PRIVACY_ACTIONS = setOf(
            // Android 13 and older (Health Connect as a Play Store app).
            "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE",
            // Android 14+, through the ViewPermissionUsageActivity alias.
            "android.intent.action.VIEW_PERMISSION_USAGE",
        )

        // HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS works on every
        // version; the framework action is the Android 14+ fallback.
        val HEALTH_CONNECT_SETTINGS_ACTIONS = listOf(
            "androidx.health.ACTION_HEALTH_CONNECT_SETTINGS",
            "android.health.connect.action.HEALTH_HOME_SETTINGS",
        )
    }
}
