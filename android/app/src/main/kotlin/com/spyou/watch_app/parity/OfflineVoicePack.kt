package com.spyou.watch_app.parity

/** Offline Piper/Sherpa packs are not bundled; hosted TTS is the shipped path. */
object OfflineVoicePack {
    fun isAvailable(): Boolean = false

    fun voiceIds(): List<String> = emptyList()
}
