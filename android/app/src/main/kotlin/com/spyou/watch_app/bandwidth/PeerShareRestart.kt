package com.spyou.watch_app.bandwidth

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
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
    private const val ALARM_DELAY_MS = 10_000L

    /**
     * Whether the platform forbids starting the SDK's service from a boot
     * broadcast.
     *
     * Android 15 blocks `dataSync` foreground services from BOOT_COMPLETED, and
     * the SDK's `PeerProxyService` is `dataSync`. The rule keys off the app's
     * targetSdkVersion, not the OS version, so gating on `SDK_INT` alone (as
     * this did) switched the restart off on every Android 15 device, including
     * builds that target 34 and are still allowed to do it.
     */
    fun blockedFromBoot(context: Context): Boolean =
        context.applicationInfo.targetSdkVersion >= Build.VERSION_CODES.VANILLA_ICE_CREAM &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM

    /** Starts sharing, then blocks a worker thread until the SDK settles. */
    fun restart(context: Context, pending: BroadcastReceiver.PendingResult? = null) {
        val app = context.applicationContext
        Thread {
            try {
                if (PeerShare.start(app)) PeerShare.awaitSettled(app, SETTLE_TIMEOUT_MS)
            } catch (t: Throwable) {
                Log.w(TAG, "restart failed: ${t.message}")
            } finally {
                pending?.finish()
            }
        }.start()
    }

    /**
     * Re-arms the restart through an alarm, which is not a boot broadcast and is
     * therefore allowed to start the service.
     *
     * It only lands when the user exempted the app from battery optimisation,
     * because that exemption is what permits a foreground-service start from the
     * background at all. Without it there is no way to restart automatically on
     * a build targeting 35+, so this defers to the next launch, where
     * [PeerShare.resumeIfOptedIn] picks the opt-in up.
     */
    fun scheduleDeferredRestart(context: Context) {
        val app = context.applicationContext
        val power = app.getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (power?.isIgnoringBatteryOptimizations(app.packageName) != true) {
            Log.i(
                TAG,
                "restart deferred to next launch: Android 15+ blocks dataSync at " +
                    "boot and the app is still battery-optimised",
            )
            return
        }
        val alarm = app.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(app, PeerShareRestartReceiver::class.java)
            .setAction(PeerShareRestartReceiver.ACTION_RESTART)
        val pending = PendingIntent.getBroadcast(
            app,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        alarm.set(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + ALARM_DELAY_MS,
            pending,
        )
        Log.i(TAG, "scheduled restart ${ALARM_DELAY_MS}ms after boot")
    }
}
