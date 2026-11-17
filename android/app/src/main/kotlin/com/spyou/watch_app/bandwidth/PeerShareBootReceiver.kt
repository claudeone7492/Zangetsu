package com.spyou.watch_app.bandwidth

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Restarts bandwidth sharing after a reboot or an app update — but ONLY when the
 * user previously opted in ([BandwidthSharePrefs.ENABLED]). The SDK runs its own
 * foreground service with a visible notification, so a restart here restores the
 * user's own choice; it never turns sharing on for someone who declined or never
 * answered.
 *
 * BOOT_COMPLETED / MY_PACKAGE_REPLACED are on Android's temporary allowlist, so
 * starting a foreground service from them is permitted on Android 12+ — but NOT
 * a `dataSync` one. On Android 15+ (API 35) the SDK's `PeerProxyService`
 * (`foregroundServiceType="dataSync"`) cannot be started from BOOT_COMPLETED at
 * all: the system throws `ForegroundServiceStartNotAllowedException`, so the
 * restart failed and sharing never came back. Those versions defer to the next
 * app launch, where starting the service is allowed; [PeerShare.resumeIfOptedIn]
 * honours the opt-in from the Activity instead.
 */
class PeerShareBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action !in ACTIONS) {
            return
        }
        if (!BandwidthSharePrefs.isEnabled(context)) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            Log.i(
                TAG,
                "deferring restart to next launch (Android 15+ blocks dataSync " +
                    "foreground services from BOOT_COMPLETED)",
            )
            return
        }

        // start() reports success and logs its own failures, so a device whose
        // key is missing or relay refuses just stays off rather than crashing.
        PeerShare.start(context)
    }

    companion object {
        private const val TAG = "PeerShareBootReceiver"

        /**
         * Must match the <intent-filter> in AndroidManifest.xml. QUICKBOOT_POWERON
         * is the HTC/Xiaomi "fast boot" reboot action — some OEMs send it instead
         * of BOOT_COMPLETED — and it was declared in the manifest but dropped
         * here, so the receiver fired and then did nothing on those devices.
         */
        private val ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON",
        )
    }
}
