package com.spyou.watch_app.parity

import android.graphics.Bitmap
import android.view.PixelCopy
import android.view.SurfaceView
import android.view.Window

/** Captures a player frame so a burned-in subtitle can be overlaid and saved. */
object HardSubBurner {
    fun capture(window: Window, view: SurfaceView, onFrame: (Bitmap?) -> Unit) {
        val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        PixelCopy.request(window, bitmap, { result ->
            onFrame(if (result == PixelCopy.SUCCESS) bitmap else null)
        }, view.handler ?: android.os.Handler(android.os.Looper.getMainLooper()))
    }
}
