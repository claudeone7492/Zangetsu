package com.spyou.watch_app.download

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.util.Log
import java.io.File
import java.nio.ByteBuffer

/**
 * Muxes a DASH episode's separately-downloaded fMP4 tracks (one video-only, one
 * audio-only) into a single playable MP4, via [MediaExtractor] → [MediaMuxer].
 * No re-encode.
 *
 * DASH typically serves the video and audio as two independent fragmented-MP4
 * files; each plays on its own but neither is the episode. [remux] already
 * handles a single file that carries both; this handles the two-file case.
 *
 * [videoPath] is required; [audioPath] may be null (a muxed-A/V manifest, or a
 * source with no audio track) in which case the video file alone is rewritten.
 *
 * Returns true on success; on any failure the partial output is deleted and
 * false is returned so the caller can fall back.
 */
object DashMuxer {

    private const val TAG = "DashMuxer"

    fun mux(videoPath: String, audioPath: String?, outputPath: String): Boolean {
        var videoEx: MediaExtractor? = null
        var audioEx: MediaExtractor? = null
        var muxer: MediaMuxer? = null
        var started = false
        var ok = false
        var samples = 0
        try {
            videoEx = MediaExtractor().apply { setDataSource(videoPath) }
            if (audioPath != null && File(audioPath).exists()) {
                audioEx = MediaExtractor().apply { setDataSource(audioPath) }
            }

            val vTrack = firstTrack(videoEx, "video/")
            if (vTrack < 0) { Log.w(TAG, "no video track in $videoPath"); return false }
            videoEx.selectTrack(vTrack)

            var aTrack = -1
            if (audioEx != null) {
                aTrack = firstTrack(audioEx, "audio/")
                if (aTrack >= 0) audioEx.selectTrack(aTrack)
            }

            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            val vOut = muxer.addTrack(videoEx.getTrackFormat(vTrack))
            val aOut = if (audioEx != null && aTrack >= 0) {
                muxer.addTrack(audioEx.getTrackFormat(aTrack))
            } else {
                -1
            }

            muxer.start()
            started = true

            val buffer = ByteBuffer.allocate(8 * 1024 * 1024)
            val info = MediaCodec.BufferInfo()

            samples += copyTrack(videoEx, vOut, muxer, buffer, info)
            if (audioEx != null && aOut >= 0) {
                samples += copyTrack(audioEx, aOut, muxer, buffer, info)
            }

            ok = samples > 0
        } catch (e: Throwable) {
            Log.w(TAG, "mux threw after samples=$samples: ${e.javaClass.simpleName}: ${e.message}")
            ok = false
        } finally {
            if (started) {
                try { muxer?.stop() } catch (e: Throwable) {
                    Log.w(TAG, "muxer.stop threw: ${e.message}"); ok = false
                }
            }
            try { muxer?.release() } catch (_: Throwable) {}
            try { videoEx?.release() } catch (_: Throwable) {}
            try { audioEx?.release() } catch (_: Throwable) {}
            if (!ok) { try { File(outputPath).delete() } catch (_: Throwable) {} }
        }
        Log.i(TAG, "mux ok=$ok samples=$samples out=${File(outputPath).length()} B")
        return ok
    }

    private fun firstTrack(ex: MediaExtractor, mimePrefix: String): Int {
        for (i in 0 until ex.trackCount) {
            val mime = ex.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: ""
            if (mime.startsWith(mimePrefix)) return i
        }
        return -1
    }

    /** Copies every sample of [ex] (already selected) into [muxTrack]. */
    private fun copyTrack(
        ex: MediaExtractor,
        muxTrack: Int,
        muxer: MediaMuxer,
        buffer: ByteBuffer,
        info: MediaCodec.BufferInfo,
    ): Int {
        var count = 0
        while (true) {
            val size = ex.readSampleData(buffer, 0)
            if (size < 0) break
            info.offset = 0
            info.size = size
            info.presentationTimeUs = ex.sampleTime.coerceAtLeast(0L)
            info.flags =
                if (ex.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0) {
                    MediaCodec.BUFFER_FLAG_KEY_FRAME
                } else {
                    0
                }
            muxer.writeSampleData(muxTrack, buffer, info)
            ex.advance()
            count++
        }
        return count
    }
}
