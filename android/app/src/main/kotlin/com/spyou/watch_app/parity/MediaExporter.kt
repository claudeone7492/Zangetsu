package com.spyou.watch_app.parity

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.IOException

/** Copies a finished download into the public Downloads/Zangetsu folder. */
object MediaExporter {
    const val FOLDER = "Zangetsu"

    fun save(context: Context, source: File, displayName: String, mime: String): Result<String> {
        if (!source.exists() || source.length() == 0L) {
            return Result.failure(IOException("the file is empty"))
        }
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                saveModern(context, source, displayName, mime)
            } else {
                saveLegacy(source, displayName)
            }
        }
    }

    private fun saveModern(context: Context, source: File, displayName: String, mime: String): String {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/$FOLDER")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw IOException("MediaStore refused the insert")
        resolver.openOutputStream(uri)?.use { out ->
            source.inputStream().use { it.copyTo(out) }
        } ?: throw IOException("no output stream")
        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return "Downloads/$FOLDER/$displayName"
    }

    private fun saveLegacy(source: File, displayName: String): String {
        val dir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            FOLDER,
        )
        if (!dir.exists()) dir.mkdirs()
        val target = File(dir, displayName)
        source.copyTo(target, overwrite = true)
        return "Downloads/$FOLDER/$displayName"
    }
}
