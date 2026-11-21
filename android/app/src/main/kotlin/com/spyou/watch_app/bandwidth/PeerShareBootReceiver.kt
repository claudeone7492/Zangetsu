package com.spyou.watch_app.bandwidth

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restarts bandwidth sharing after a reboot or an app update — but ONLY when the
 * user previously opted in ([BandwidthSharePrefs.ENABLED]). The SDK runs its own
 * foreground service with a visible notification, so a restart here restores the
 * user's own choice; it never turns sharing on for someone who declined or never
 * answered.
 *
 * Two things decide whether the restart can happen here, and both live in
 * [PeerShareRestart]: whether the platform allows a `dataSync` service to be
 * started from this broadcast, and keeping the process alive long enough for the
 * SDK's network registration to finish.
 */
class PeerShareBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action !in ACTIONS) return
        if (!BandwidthSharePrefs.isEnabled(context)) return

        if (PeerShareRestart.blockedFromBoot(context)) {
            PeerShareRestart.scheduleDeferredRestart(context)
            return
        }
        PeerShareRestart.restart(context, goAsync())
    }

    companion object {
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
