package com.spyou.watch_app.bandwidth

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Delivers the single retry alarm that [PeerShareRestart.scheduleRetry] arms when
 * a boot-time restart did not take. Not a boot receiver, so no foreground-service
 * type restriction applies; it only runs when the app is battery-exempt.
 */
class PeerShareRestartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_RETRY) return
        if (!BandwidthSharePrefs.isEnabled(context)) return
        PeerShareRestart.restart(context, goAsync(), allowRetry = false)
    }

    companion object {
        const val ACTION_RETRY = "com.spyou.watch_app.action.PEER_SHARE_RETRY"
    }
}
