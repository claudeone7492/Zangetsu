package com.spyou.watch_app.bandwidth

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart side of bandwidth sharing. Two channels:
 *
 * - `zangetsu/bandwidth_share` — commands + a snapshot. `enable` records the
 *   opt-in flag and starts the SDK, then waits for the relay's answer before
 *   reporting; `disable` clears the flag and stops it; `markAnswered` records
 *   that the consent sheet was dismissed without enabling; `snapshot` returns
 *   {enabled, answeredConsent, running, available, status}.
 * - `zangetsu/bandwidth_share/status` — the SDK's status stream, pushed on
 *   every change.
 *
 * Kept deliberately thin: the flag write and the SDK call both live in
 * [BandwidthSharePrefs] / [PeerShare], so the boot receiver follows the exact
 * same path with no Flutter engine present.
 */
class BandwidthShareBridge(context: Context) : MethodChannel.MethodCallHandler {
    private val appContext = context.applicationContext

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "enable" -> {
                // The answer and the opt-in are recorded before anything is
                // started, so a slow or refused relay — or a crash — cannot
                // bring the consent sheet back on the next launch. The opt-in
                // stays set even if this attempt fails; resume retries it.
                BandwidthSharePrefs.setAnswered(appContext, true)
                BandwidthSharePrefs.setEnabled(appContext, true)
                // `start()` returns as soon as it has launched the registration
                // coroutine, so the reply waits for a terminal status. Settings
                // uses that to show Failed/Connected; the opt-in is separate.
                Thread {
                    val configured = PeerShare.isConfigured()
                    val requested = configured && PeerShare.start(appContext)
                    val status = if (configured) {
                        PeerShare.awaitSettled(appContext)
                    } else {
                        "unsupported"
                    }
                    val started = requested && status != "error"
                    result.success(
                        mapOf(
                            "started" to started,
                            "enabled" to BandwidthSharePrefs.isEnabled(appContext),
                            "running" to PeerShare.isRunning(appContext),
                            "available" to configured,
                            "status" to status,
                            "batteryExempt" to batteryExempt(),
                        ),
                    )
                }.start()
            }
            "disable" -> {
                BandwidthSharePrefs.setEnabled(appContext, false)
                PeerShare.stop(appContext)
                result.success(
                    mapOf(
                        "enabled" to false,
                        "status" to PeerShare.currentStatus(appContext),
                    ),
                )
            }
            "markAnswered" -> {
                BandwidthSharePrefs.setAnswered(appContext, true)
                result.success(null)
            }
            // Android will refuse to restart a background service for an app it
            // has put to sleep, so the reboot restart is only dependable once the
            // user exempts the app. The dialog is the system's own; we never
            // grant anything ourselves.
            "requestBatteryExemption" -> result.success(openBatteryExemptionDialog())
            "snapshot" -> result.success(
                mapOf(
                    "enabled" to BandwidthSharePrefs.isEnabled(appContext),
                    "answeredConsent" to BandwidthSharePrefs.isAnswered(appContext),
                    "running" to PeerShare.isRunning(appContext),
                    "available" to PeerShare.isConfigured(),
                    "status" to PeerShare.currentStatus(appContext),
                    "batteryExempt" to batteryExempt(),
                ),
            )
            else -> result.notImplemented()
        }
    }

    private fun batteryExempt(): Boolean =
        appContext.getSystemService(PowerManager::class.java)
            ?.isIgnoringBatteryOptimizations(appContext.packageName) == true

    /**
     * Opens the system's "don't optimise this app" dialog, falling back to the
     * optimiser's app list on devices that do not handle the direct request
     * (some OEM builds). Returns whether a screen was actually opened, so the UI
     * can say "no" instead of pretending.
     */
    @SuppressLint("BatteryLife")
    private fun openBatteryExemptionDialog(): Boolean {
        val direct = Intent(
            Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:${appContext.packageName}"),
        )
        val list = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        return listOf(direct, list).any { intent ->
            runCatching {
                appContext.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                true
            }.getOrDefault(false)
        }
    }
}

/** Streams the SDK's status to Dart as lowercase names. */
class BandwidthStatusStreamHandler : EventChannel.StreamHandler {
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        PeerShare.setListener { name -> events.success(name) }
    }

    override fun onCancel(arguments: Any?) {
        PeerShare.setListener(null)
    }
}
