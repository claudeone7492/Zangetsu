package com.spyou.watch_app

import android.content.Context
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * System text-to-speech behind AI Dub.
 *
 * Owned by the app rather than a plugin so the whole dub feature is four
 * methods on one channel, and so a voice the platform exposes can be chosen by
 * name. Android's engine takes a moment to initialise, so calls made before
 * that finish are queued rather than dropped — otherwise the first line of the
 * first episode would silently never be spoken.
 */
class DubTtsBridge(context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "zangetsu/dub_tts")
    private val appContext = context.applicationContext

    private var tts: TextToSpeech? = null
    private var ready = false
    private var failed = false
    private val pending = ArrayDeque<(TextToSpeech) -> Unit>()

    init {
        tts = TextToSpeech(appContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                ready = true
                tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                    override fun onStart(utteranceId: String?) = Unit
                    override fun onDone(utteranceId: String?) = Unit
                    @Deprecated("Deprecated in Java")
                    override fun onError(utteranceId: String?) = Unit
                })
                // Draining here keeps ordering: a "speak" issued during startup
                // is spoken once the engine is actually usable.
                while (pending.isNotEmpty()) pending.removeFirst()(tts!!)
            } else {
                failed = true
                pending.clear()
            }
        }

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(!failed)
                "voices" -> result.success(voices())
                "speak" -> {
                    speak(
                        text = call.argument<String>("text") ?: "",
                        voice = call.argument<String>("voice"),
                        rate = (call.argument<Double>("rate") ?: 1.0).toFloat(),
                        pitch = (call.argument<Double>("pitch") ?: 1.0).toFloat(),
                        volume = (call.argument<Double>("volume") ?: 1.0).toFloat(),
                    )
                    result.success(null)
                }
                "stop" -> {
                    run { tts?.stop() }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun voices(): List<Map<String, Any>> {
        val engine = tts ?: return emptyList()
        val out = ArrayList<Map<String, Any>>()
        val seen = HashSet<String>()
        for (v in engine.voices.orEmpty()) {
            // A device can expose dozens of near-duplicate voices; one per
            // (name, locale) is enough for a picker and keeps it readable.
            val key = "${v.name}|${v.locale.toLanguageTag()}"
            if (!seen.add(key)) continue
            out.add(
                mapOf(
                    "name" to v.name,
                    "locale" to v.locale.toLanguageTag(),
                    "network" to v.isNetworkConnectionRequired,
                )
            )
        }
        // Offline voices first: they work on a plane and start faster.
        out.sortWith(compareBy({ it["network"] == true }, { it["name"] as String }))
        return out
    }

    private fun speak(text: String, voice: String?, rate: Float, pitch: Float, volume: Float) {
        if (text.isBlank() || failed) return
        val action: (TextToSpeech) -> Unit = { engine ->
            val v: Voice? = voice?.let { wanted ->
                engine.voices?.firstOrNull { it.name == wanted }
            }
            if (v != null) {
                engine.voice = v
            } else if (voice != null) {
                // The saved voice is gone (engine update, different device).
                // Fall back to the language it named rather than going silent.
                runCatching { engine.language = Locale.forLanguageTag(voice) }
            }
            engine.setSpeechRate(rate)
            engine.setPitch(pitch)
            // QUEUE_FLUSH: a dub line replaces the previous one. Overlapping
            // narration is worse than a cut-off line.
            engine.speak(text, TextToSpeech.QUEUE_FLUSH, null, "dub")
        }
        val engine = tts
        if (ready && engine != null) action(engine) else pending.addLast(action)
    }

    fun dispose() {
        pending.clear()
        tts?.stop()
        tts?.shutdown()
        tts = null
    }
}
