package com.spyou.watch_app.parity

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech

/**
 * Offline narration voices.
 *
 * No neural model is bundled — a Piper/Sherpa pack is 60–200 MB per voice and
 * would dominate the APK for a feature most installs never turn on. The
 * offline path instead uses the voices the platform's own speech engine has
 * downloaded: Android's speech service ships offline packs, the user picks
 * them in system settings, and `TextToSpeech` then speaks with no network at
 * all. This reports what is actually installed, so the UI can say "3 offline
 * voices" instead of guessing, and offers the screen where more can be
 * downloaded.
 */
object OfflineVoicePack {

    /**
     * Names of the installed voices that need no network. Empty when the
     * engine is missing or has no offline pack downloaded. Answers exactly
     * once, on the main thread, even when the engine never initialises.
     */
    fun offlineVoiceIds(context: Context, onResult: (List<String>) -> Unit) {
        val holder = arrayOfNulls<TextToSpeech>(1)
        var answered = false
        fun answer(ids: List<String>) {
            if (answered) return
            answered = true
            runCatching { holder[0]?.shutdown() }
            holder[0] = null
            onResult(ids)
        }
        val engine = TextToSpeech(context) { status ->
            if (status != TextToSpeech.SUCCESS) {
                answer(emptyList())
            } else {
                val ids = runCatching {
                    holder[0]?.voices
                        ?.filter { !it.isNetworkConnectionRequired }
                        ?.map { it.name }
                        ?.sorted()
                        .orEmpty()
                }.getOrDefault(emptyList())
                answer(ids)
            }
        }
        holder[0] = engine
        // A device with no engine never calls the listener; do not leave the
        // caller waiting for one.
        Handler(Looper.getMainLooper()).postDelayed({ answer(emptyList()) }, 2000)
    }

    /** System screen where offline voice packs are downloaded. */
    fun openSettings(context: Context) {
        val intent = Intent("com.android.settings.TTS_SETTINGS")
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
    }
}
