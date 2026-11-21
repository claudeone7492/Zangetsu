package com.spyou.watch_app

import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Native Telegram streaming seam.
 *
 * Public channels are read in Dart through Telegram's web preview, so this
 * bridge exists for the path the preview cannot serve: private channels and
 * full history, which need TDLib. Until a TDLib client is linked, `available`
 * is false and the Dart service falls back to the preview. When TDLib lands,
 * `resolveChannel` should return the same list of maps the Dart layer already
 * parses: title, url, thumbnail, pageUrl, publishedAt.
 */
class TelegramBridge(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "zangetsu/telegram")

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(false)
                "resolveChannel" -> result.error(
                    "unavailable",
                    "Telegram streaming needs the TDLib native library",
                    null,
                )
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
