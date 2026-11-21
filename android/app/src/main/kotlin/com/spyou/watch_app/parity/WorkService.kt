package com.spyou.watch_app.parity

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

/** Keeps long downloads alive while the app is in the background. */
class WorkService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createChannel()
        val label = intent?.getStringExtra(EXTRA_LABEL) ?: "Working"
        val notification = Notification.Builder(this, CHANNEL)
            .setContentTitle("Zangetsu")
            .setContentText(label)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .build()
        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW),
        )
    }

    companion object {
        const val CHANNEL = "zangetsu.work"
        const val NOTIFICATION_ID = 4711
        const val EXTRA_LABEL = "zangetsu.work.label"
    }
}
