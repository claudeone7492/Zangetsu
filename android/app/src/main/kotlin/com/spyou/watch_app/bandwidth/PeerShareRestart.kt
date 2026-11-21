package com.spyou.watch_app.bandwidth

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log

/**
 * The one restart path shared by [PeerShareBootReceiver] and
 * [PeerShareRestartReceiver].
 *
 * `ProxiesPeerSDK.start()` registers the device over the network before its
 * service exists, on a coroutine the SDK owns. A receiver that calls it and
 * returns lets the process become cacheable straight away, and the registration
 * is dropped — the restart looked wired up but never brought sharing back. So
 * callers pass the `goAsync()` result in and this keeps the process alive until
 * the SDK reaches a terminal status.
 */
internal object PeerShareRestart {
    private const val TAG = "PeerShareRestart"
    private const val SETTLE_TIMEOUT_MS = 8_000L
    private const val RETRY_DELAY_MS = 60_000L

    /**
     * Starts sharing and blocks a worker thread until the SDK settles.
     *
     * `allowRetry` arms one alarm retry when the attempt does not take. The
     * alarm receiver passes `false`, so a device that keeps failing gets one
     * extra attempt per boot instead of an endless chain.
     */
    fun restart(
        context: Context,
        pending: BroadcastReceiver.PendingResult?,
        allowRetry: Boolean = true,
    ) {
        val app = context.applicationContext
        Thread {
            var settled = false
            try {
                settled = PeerShare.start(app) &&
                    PeerShare.awaitSettled(app, SETTLE_TIMEOUT_MS)
                        .let { it == "connected" || it == "connecting" }
            } catch (t: Throwable) {
                Log.w(TAG, "restart failed: ${t.message}")
            } finally {
                pending?.finish()
            }
            if (!settled && allowRetry) scheduleRetry(app)
        }.start()
    }

    /**
     * One retry, a minute later, for when the first attempt did not take.
     *
     * Only armed when the app is exempt from battery optimisation. That exemption
     * is what lets an alarm start a foreground service from the background at
     * all, so without it the alarm would be refused and the retry would be
     * theatre. [PeerShareBootReceiver] itself needs no exemption: BOOT_COMPLETED
     * is on the platform's allowlist, and the service is `specialUse`, which the
     * boot restriction does not cover.
     */
    fun scheduleRetry(context: Context) {
        val app = context.applicationContext
        val power = app.getSystemService(PowerManager::class.java) ?: return
        if (!power.isIgnoringBatteryOptimizations(app.packageName)) {
            Log.i(
                TAG,
                "no retry: app is battery-optimised, so a background start would be refused",
            )
            return
        }
        val alarm = app.getSystemService(AlarmManager::class.java) ?: return
        val pending = PendingIntent.getBroadcast(
            app,
            0,
            Intent(app, PeerShareRestartReceiver::class.java)
                .setAction(PeerShareRestartReceiver.ACTION_RETRY),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        alarm.set(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + RETRY_DELAY_MS,
            pending,
        )
        Log.i(TAG, "retry scheduled in ${RETRY_DELAY_MS}ms")
    }
}
