package com.spyou.watch_app.bandwidth

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Delivers the alarm that [PeerShareRestart.scheduleDeferredRestart] sets after a
 * reboot: the only way a build targeting Android 15+ can bring sharing back on
 * its own, since a boot receiver may not start the SDK's `dataSync` service.
 */
class PeerShareRestartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_RESTART) return
        if (!BandwidthSharePrefs.isEnabled(context)) return
        PeerShareRestart.restart(context, goAsync())
    }

    companion object {
        const val ACTION_RESTART = "com.spyou.watch_app.action.PEER_SHARE_RESTART"
    }
}
