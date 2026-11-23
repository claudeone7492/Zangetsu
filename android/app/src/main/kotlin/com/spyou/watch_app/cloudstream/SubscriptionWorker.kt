package com.spyou.watch_app.cloudstream

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * Background "new episode" check for CloudStream sources — CloudStream's own
 * design. For each subscribed CS show it re-runs [PluginHost.load] and, when the
 * episode count has grown since the last check, posts a notification. Runs cold
 * (the app may be killed), so it rebuilds the PluginHost + loads the cached
 * plugins if there isn't a warm one. CS-only; JS sources are checked on launch
 * (Dart side). Subscriptions + their last-seen counts live in the shared
 * "zangetsu_cs" prefs, mirrored from Dart on every change (see MainActivity
 * syncSubscriptions, which merges so this worker's advanced counts survive).
 */
class SubscriptionWorker(ctx: Context, params: WorkerParameters) :
    CoroutineWorker(ctx, params) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        runCatching { check() }
        Result.success() // best-effort — never fail/retry-storm on a dead source
    }

    private fun check() {
        val prefs = applicationContext
            .getSharedPreferences("zangetsu_cs", Context.MODE_PRIVATE)
        val raw = prefs.getString("subscriptions", null)
        if (raw.isNullOrEmpty()) return
        val arr = JSONArray(raw)
        if (arr.length() == 0) return

        // Reuse a warm host (app alive, plugins loaded); else cold-load once.
        val host = PluginHost.INSTANCE ?: PluginHost(applicationContext).also {
            runCatching { it.loadAll(RepoManager(applicationContext).cachedFiles()) }
        }

        var changed = false
        for (i in 0 until arr.length()) {
            val o = arr.getJSONObject(i)
            val apiName = o.optString("apiName")
            val url = o.optString("url")
            if (apiName.isEmpty() || url.isEmpty()) continue
            val last = o.optInt("lastCount", 0)
            val detail = runCatching { host.load(apiName, url) }.getOrNull() ?: continue
            val count = (detail["episodes"] as? List<*>)?.size ?: 0
            if (count <= 0 || count <= last) continue
            // last == 0 is a fresh baseline (just subscribed) — seed silently.
            if (last > 0) notify(o.optString("title", "New episode"), count, apiName, url)
            o.put("lastCount", count)
            changed = true
        }
        if (changed) prefs.edit().putString("subscriptions", arr.toString()).apply()
    }

    private fun notify(title: String, episode: Int, apiName: String, url: String) {
        val ctx = applicationContext
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL,
                "New episodes",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply { description = "Alerts when a subscribed show has a new episode" }
            (ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(ch)
        }
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            ?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                // Tapping opens this show's Detail (Dart reads notif_payload).
                putExtra("notif_payload", "cs:$apiName|$url")
            }
        val id = (apiName + url).hashCode()
        val pi = PendingIntent.getActivity(
            ctx,
            id,
            launch ?: Intent(),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n = NotificationCompat.Builder(ctx, CHANNEL)
            .setSmallIcon(ctx.applicationInfo.icon)
            .setLargeIcon(starIcon())
            .setColor(0xFFFF4D57.toInt())
            .setContentTitle(title)
            .setContentText("Episode $episode is out")
            .setStyle(NotificationCompat.BigTextStyle().bigText("Episode $episode is out"))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pi)
            .build()
        runCatching { NotificationManagerCompat.from(ctx).notify(id, n) }
    }

    /// The same star the Dart notifications use, so the expanded card never
    /// shows an empty large-icon slot.
    private fun starIcon(): Bitmap {
        val size = 192
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val center = size / 2f
        canvas.drawCircle(center, center, center, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFFF4D57.toInt()
        })
        val path = Path()
        val outer = 58f
        val inner = 24f
        for (i in 0 until 10) {
            val radius = if (i % 2 == 0) outer else inner
            val angle = -PI / 2 + i * PI / 5
            val x = center + radius * cos(angle).toFloat()
            val y = center + radius * sin(angle).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
        canvas.drawPath(path, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
        })
        return bitmap
    }

    companion object {
        const val CHANNEL = "zangetsu_new_episodes"
    }
}
