package com.spyou.watch_app.bandwidth

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Restarts bandwidth sharing after a reboot or an app update — but ONLY when the
 * user previously opted in ([BandwidthSharePrefs.ENABLED]). The SDK runs its own
 * foreground service with a visible notification, so a restart here restores the
 * user's own choice; it never turns sharing on for someone who declined or never
 * answered.
 *
 * BOOT_COMPLETED / MY_PACKAGE_REPLACED are on Android's temporary allowlist, so
 * starting a foreground service from them is permitted on Android 12+.
 */
class PeerShareBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != Intent.ACTION_LOCKED_BOOT_COMPLETED
        ) {
            return
        }
        if (!BandwidthSharePrefs.isEnabled(context)) return
        try {
            PeerShare.start(context)
        } catch (t: Throwable) {
            Log.w("PeerShareBootReceiver", "restart failed: ${t.message}")
        }
    }
}
