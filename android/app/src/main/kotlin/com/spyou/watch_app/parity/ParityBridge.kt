package com.spyou.watch_app.parity

import android.app.Activity
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.view.PixelCopy
import java.io.File
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * The small native seams the parity pass needed: a frame grab that includes
 * the Flutter subtitle overlay, and a foreground keeper for long in-process
 * jobs (muxing a finished download).
 *
 * The frame grab uses [PixelCopy] on the window rather than mpv's screenshot:
 * subtitles are drawn by Flutter, so only a window capture has them in it.
 */
object ParityBridge {

    /** Pictures/Zangetsu subfolder for saved frames. */
    const val PICTURES_FOLDER = "Zangetsu"

    /**
     * Copies the current window (video frame + Flutter subtitle overlay) into
     * Pictures/Zangetsu. Blocks until the copy completes, so call it off the
     * main thread.
     */
    fun captureWindow(activity: Activity, name: String): Result<String> {
        val view = activity.window.decorView
        if (view.width <= 0 || view.height <= 0) {
            return Result.failure(IOException("no window to capture"))
        }
        val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        val latch = CountDownLatch(1)
        var resultCode = PixelCopy.ERROR_UNKNOWN
        val handler = Handler(Looper.getMainLooper())
        activity.runOnUiThread {
            PixelCopy.request(activity.window, bitmap, { code ->
                resultCode = code
                latch.countDown()
            }, handler)
        }
        if (!latch.await(3, TimeUnit.SECONDS)) {
            bitmap.recycle()
            return Result.failure(IOException("frame capture timed out"))
        }
        if (resultCode != PixelCopy.SUCCESS) {
            bitmap.recycle()
            return Result.failure(IOException("frame capture failed ($resultCode)"))
        }
        return runCatching { savePicture(activity, bitmap, name) }
            .also { bitmap.recycle() }
    }

    private fun savePicture(context: Context, bitmap: Bitmap, name: String): String {
        val displayName = if (name.endsWith(".png")) name else "$name.png"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, "image/png")
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    "${Environment.DIRECTORY_PICTURES}/$PICTURES_FOLDER",
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("MediaStore refused the insert")
            resolver.openOutputStream(uri)?.use { out ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            } ?: throw IOException("no output stream")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "Pictures/$PICTURES_FOLDER/$displayName"
        }
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
            PICTURES_FOLDER,
        )
        if (!dir.exists()) dir.mkdirs()
        val target = File(dir, displayName)
        target.outputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        }
        return "Pictures/$PICTURES_FOLDER/$displayName"
    }

    fun startWork(context: Context, label: String) {
        val intent = Intent(context, WorkService::class.java)
            .putExtra(WorkService.EXTRA_LABEL, label)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    }

    fun stopWork(context: Context) {
        context.stopService(Intent(context, WorkService::class.java))
    }
}
