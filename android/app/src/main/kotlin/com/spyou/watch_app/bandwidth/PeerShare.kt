package com.spyou.watch_app.bandwidth

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.spyou.watch_app.BuildConfig
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
        return try {
            ProxiesPeerSDK.getInstance().start()
            true
        } catch (t: Throwable) {
            Log.w(TAG, "start failed: ${t.message}")
            false
        }
    }

    fun stop(context: Context) {
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
