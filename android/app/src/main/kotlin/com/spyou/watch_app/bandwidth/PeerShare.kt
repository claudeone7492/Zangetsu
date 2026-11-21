package com.spyou.watch_app.bandwidth

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.spyou.watch_app.BuildConfig
import com.spyou.watch_app.R
import sx.proxies.peer.ProxiesPeerSDK

/**
 * Single owner of the Proxies.sx peer SDK instance for the whole process.
 *
 * Both the Flutter bridge and [PeerShareBootReceiver] go through here, so the
 * SDK is initialised exactly once and every status change reaches whoever is
 * listening — the bridge's event channel while a Flutter engine is up, nothing
 * while the app is closed. The API key is compiled in from a gitignored file
 * (see [BuildConfig.PROXIES_API_KEY]); when it is blank the SDK never starts,
 * so a build without the key is inert rather than broken.
 */
object PeerShare {
    private const val TAG = "PeerShare"

    @Volatile private var initialized = false
    private val main = Handler(Looper.getMainLooper())

    /** The bridge's status callback, or null when no engine is attached. */
    @Volatile private var listener: ((String) -> Unit)? = null

    private fun statusName(status: ProxiesPeerSDK.Status): String = when (status) {
        ProxiesPeerSDK.Status.STOPPED -> "stopped"
        ProxiesPeerSDK.Status.CONNECTING -> "connecting"
        ProxiesPeerSDK.Status.CONNECTED -> "connected"
        ProxiesPeerSDK.Status.ERROR -> "error"
    }

    /**
     * Whether this build carries an SDK key at all. A blank key makes the SDK
     * inert, so the UI hides the feature instead of offering a switch that can
     * never come up.
     */
    fun isConfigured(): Boolean = BuildConfig.PROXIES_API_KEY.isNotBlank()

    /** Idempotent: initialises the SDK on first use, no-ops afterwards. */
    private fun ensureInit(context: Context) {
        if (initialized) return
        synchronized(this) {
            if (initialized) return
            val key = BuildConfig.PROXIES_API_KEY
            if (key.isBlank()) {
                Log.w(TAG, "PROXIES_API_KEY not set; bandwidth sharing disabled")
                return
            }
            try {
                ProxiesPeerSDK.init(
                    context.applicationContext,
                    key,
                    ProxiesPeerSDK.Config(
                        // The notification must read as this app, not the SDK
                        // vendor. A null title falls back to the app label, and
                        // the connected text replaces upstream's
                        // "Connected as <deviceId>".
                        notificationConnectedText = context.getString(
                            R.string.bandwidth_share_notification_connected,
                        ),
                        onStatusChange = { s -> broadcast(statusName(s)) },
                    ),
                )
                initialized = true
            } catch (t: Throwable) {
                Log.w(TAG, "SDK init failed: ${t.message}")
            }
        }
    }

    fun start(context: Context): Boolean {
        ensureInit(context)
        if (!initialized) return false
        // `start()` registers the device and dials the relay; calling it again
        // while that is in flight only repeats the registration, which is what
        // the resume hook would otherwise do on every foregrounding.
        val current = currentStatus(context)
        if (current == "connected" || current == "connecting") return true
        return try {
            ProxiesPeerSDK.getInstance().start()
            true
        } catch (t: Throwable) {
            Log.w(TAG, "start failed: ${t.message}")
            false
        }
    }

    /**
     * Blocks until the SDK names a terminal status or [timeoutMs] elapses.
     *
     * `start()` only launches a coroutine: it registers the device over the
     * network and then starts the foreground service, so it returns "started"
     * long before the relay answers. Without this wait, `enable` reported
     * success for a key the relay rejects and the switch showed on while
     * nothing ran. Call it off the main thread.
     */
    fun awaitSettled(context: Context, timeoutMs: Long = 5_000): String {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline) {
            val status = currentStatus(context)
            if (status == "connected" || status == "error") return status
            try {
                Thread.sleep(150)
            } catch (interrupted: InterruptedException) {
                Thread.currentThread().interrupt()
                break
            }
        }
        return currentStatus(context)
    }

    /**
     * Bring sharing back if the user opted in — the Android 15+ path, where
     * [PeerShareBootReceiver] cannot start the SDK's `dataSync` foreground
     * service from BOOT_COMPLETED. Called on Activity resume; a no-op when
     * sharing was never enabled, or is already running.
     */
    fun resumeIfOptedIn(context: Context) {
        if (!BandwidthSharePrefs.isEnabled(context)) return
        val status = currentStatus(context)
        if (status == "connected" || status == "connecting") return
        start(context)
    }

    fun stop(context: Context) {
        // init() is what makes `getInstance()` legal; stopping without it threw
        // and left a service the previous process had started running.
        ensureInit(context)
        if (!initialized) return
        try {
            ProxiesPeerSDK.getInstance().stop()
        } catch (t: Throwable) {
            Log.w(TAG, "stop failed: ${t.message}")
        }
    }

    /** Whether the SDK actually started and the device is sharing. */
    fun isRunning(context: Context): Boolean {
        ensureInit(context)
        if (!initialized) return false
        return try {
            ProxiesPeerSDK.getInstance().isRunning()
        } catch (t: Throwable) {
            false
        }
    }

    /** Current status as a lowercase name the Dart side maps back to an enum. */
    fun currentStatus(context: Context): String {
        ensureInit(context)
        if (!initialized) return "stopped"
        return try {
            statusName(ProxiesPeerSDK.getInstance().getStatus())
        } catch (t: Throwable) {
            "stopped"
        }
    }

    fun setListener(cb: ((String) -> Unit)?) {
        listener = cb
    }

    private fun broadcast(name: String) {
        val cb = listener ?: return
        main.post { cb(name) }
    }
}
