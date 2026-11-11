package com.spyou.watch_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.media3.common.util.UnstableApi

/**
 * Foreground service that keeps [PhonePlayerActivity]'s audio alive while the
 * app is backgrounded or the video is in picture-in-picture.
 *
 * Android tears down a backgrounded process whose only claim to life is an
 * Activity, and it will not let a plain background app hold the audio focus
 * for long. A `mediaPlayback` foreground service with an ongoing notification
 * is the sanctioned way to keep playback going, and the notification doubles
 * as the transport: play/pause/stop are delivered back to the live player as
 * broadcasts, exactly like the PiP window's buttons.
 *
 * Deliberately thin: it owns no player. The Activity remains the single owner
 * of the ExoPlayer; this only keeps the process alive and relays taps.
 */
@UnstableApi
class PhonePlaybackService : Service() {

    companion object {
        private const val CHANNEL_ID = "zangetsu_playback"
        private const val NOTIFICATION_ID = 7411

        const val ACTION_START = "com.spyou.watch_app.PLAYBACK_START"
        const val ACTION_UPDATE = "com.spyou.watch_app.PLAYBACK_UPDATE"
        const val ACTION_STOP = "com.spyou.watch_app.PLAYBACK_STOP"

        /** Control requests from the notification, forwarded to the Activity. */
        const val ACTION_CONTROL = "com.spyou.watch_app.PLAYBACK_CONTROL"
        const val EXTRA_CONTROL = "control"
        const val CONTROL_PLAY = "play"
        const val CONTROL_PAUSE = "pause"
        const val CONTROL_TOGGLE = "play_pause"

        /** True while the service is up, so the Activity can skip a redundant start. */
        @Volatile
        var running = false
            private set

        fun start(context: Context, title: String, playing: Boolean) {
            val intent = Intent(context, PhonePlaybackService::class.java).apply {
                action = ACTION_START
                putExtra("title", title)
                putExtra("playing", playing)
            }
            runCatching {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            }
        }

        fun update(context: Context, title: String, playing: Boolean) {
            if (!running) return
            val intent = Intent(context, PhonePlaybackService::class.java).apply {
                action = ACTION_UPDATE
                putExtra("title", title)
                putExtra("playing", playing)
            }
            runCatching { context.startService(intent) }
        }

        fun stop(context: Context) {
            runCatching {
                context.stopService(Intent(context, PhonePlaybackService::class.java))
            }
        }
    }

    private var title = ""
    private var playing = true

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START, ACTION_UPDATE -> {
                title = intent.getStringExtra("title") ?: title
                playing = intent.getBooleanExtra("playing", playing)
                ensureChannel()
                val notification = buildNotification()
                if (Build.VERSION.SDK_INT >= 34) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
                running = true
            }
            ACTION_STOP -> {
                running = false
                stopForegroundCompat()
                stopSelf()
            }
        }
        // Not sticky: a restarted service with no Activity behind it would show
        // a notification whose buttons reach nothing.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.phone_player_bg_channel_name),
            // Low, not default: playback is a passive state and must not buzz
            // or heads-up over whatever the viewer moved on to.
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = getString(R.string.phone_player_bg_channel_desc)
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        // Tapping the notification returns to the running player rather than
        // launching a second copy — the Activity is already in the task.
        val content = packageManager.getLaunchIntentForPackage(packageName)
        val contentPending = content?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                pendingFlags(),
            )
        }
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_pip_play)
            .setContentTitle(title.ifBlank { getString(R.string.phone_player_bg_unknown_title) })
            .setOngoing(playing)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_LOW)
        if (contentPending != null) builder.setContentIntent(contentPending)

        builder.addAction(
            if (playing) R.drawable.ic_pip_pause else R.drawable.ic_pip_play,
            getString(
                if (playing) R.string.phone_player_bg_action_pause
                else R.string.phone_player_bg_action_play,
            ),
            controlIntent(CONTROL_TOGGLE),
        )
        builder.addAction(
            android.R.drawable.ic_menu_close_clear_cancel,
            getString(R.string.phone_player_bg_action_stop),
            stopPending(),
        )
        return builder.build()
    }

    private fun controlIntent(control: String): PendingIntent {
        val intent = Intent(ACTION_CONTROL)
            .setPackage(packageName)
            .putExtra(EXTRA_CONTROL, control)
        return PendingIntent.getBroadcast(this, control.hashCode(), intent, pendingFlags())
    }

    private fun stopPending(): PendingIntent {
        val intent = Intent(this, PhonePlaybackService::class.java).apply {
            action = ACTION_STOP
        }
        return PendingIntent.getService(this, 0, intent, pendingFlags())
    }

    private fun pendingFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }
}
