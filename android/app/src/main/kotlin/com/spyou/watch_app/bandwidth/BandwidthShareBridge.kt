package com.spyou.watch_app.bandwidth

import android.content.Context
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Dart side of bandwidth sharing. Two channels:
 *
 * - `zangetsu/bandwidth_share` — commands + a snapshot. `enable` records the
 *   opt-in flag and starts the SDK; `disable` clears the flag and stops it;
 *   `markAnswered` records that the consent sheet was dismissed without
 *   enabling; `snapshot` returns {enabled, answeredConsent, status}.
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
                BandwidthSharePrefs.setAnswered(appContext, true)
                BandwidthSharePrefs.setEnabled(appContext, true)
                // Report whether the SDK actually came up. If it did not (no key
                // compiled in, relay refused), the flag is rolled back so the
                // switch does not lie and the boot receiver does not try to
                // resurrect a service that never started.
                val started = PeerShare.start(appContext)
                if (!started) BandwidthSharePrefs.setEnabled(appContext, false)
                result.success(
                    mapOf(
                        "started" to started,
                        "enabled" to BandwidthSharePrefs.isEnabled(appContext),
                        "status" to PeerShare.currentStatus(appContext),
                    ),
                )
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
            "snapshot" -> result.success(
                mapOf(
                    "enabled" to BandwidthSharePrefs.isEnabled(appContext),
                    "answeredConsent" to BandwidthSharePrefs.isAnswered(appContext),
                    "running" to PeerShare.isRunning(appContext),
                    "status" to PeerShare.currentStatus(appContext),
                ),
            )
            else -> result.notImplemented()
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
