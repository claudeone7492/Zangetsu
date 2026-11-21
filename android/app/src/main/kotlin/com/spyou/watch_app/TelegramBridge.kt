package com.spyou.watch_app

import android.content.Context
import com.spyou.watch_app.telegram.TelegramStreamServer
import com.spyou.watch_app.telegram.TelegramTd
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.time.Instant

/**
 * The native Telegram path, backed by TDLib.
 *
 * Public channels are also readable in Dart through Telegram's web preview; this
 * is the path the preview cannot serve (private channels, full history, and a
 * player that does not depend on the preview's markup). Dart falls back to the
 * preview whenever `available` is false or a call fails, so this bridge is
 * additive.
 *
 * Streaming: the player needs a URL, so [resolveChannel] hands out
 * `http://127.0.0.1:<port>/stream?...` links served by [TelegramStreamServer]
 * straight out of TDLib's file cache.
 */
class TelegramBridge(messenger: BinaryMessenger, context: Context) {
    private val channel = MethodChannel(messenger, "zangetsu/telegram")
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    init {
        TelegramTd.init(appContext)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(TelegramTd.linked)
                "auth" -> result.success(TelegramTd.authMap())
                "setCredentials" -> {
                    val apiId = TelegramTd.apiIdOf(call.argument<String>("apiId").orEmpty())
                    val apiHash = TelegramTd.apiHashOf(call.argument<String>("apiHash").orEmpty())
                    if (apiId == null || apiHash == null) {
                        result.error(
                            "credentials",
                            "An api_id is a number and an api_hash is 32 hex characters",
                            null,
                        )
                    } else {
                        TelegramTd.setCredentials(appContext, apiId, apiHash)
                        result.success(TelegramTd.authMap())
                    }
                }
                "submitPhone" -> login(result) {
                    TelegramTd.submitPhone(call.argument<String>("phone").orEmpty())
                }
                "submitCode" -> login(result) {
                    TelegramTd.submitCode(call.argument<String>("code").orEmpty())
                }
                "submitPassword" -> login(result) {
                    TelegramTd.submitPassword(call.argument<String>("password").orEmpty())
                }
                "submitRegistration" -> login(result) {
                    TelegramTd.submitRegistration(
                        call.argument<String>("firstName").orEmpty(),
                        call.argument<String>("lastName").orEmpty(),
                    )
                }
                "signOut" -> {
                    TelegramTd.signOut()
                    result.success(true)
                }
                "resolveChannel" -> {
                    val name = call.argument<String>("channel").orEmpty()
                    val limit = call.argument<Int>("limit") ?: 60
                    val messageId = (call.argument<Number>("messageId") ?: 0).toLong()
                    scope.launch {
                        try {
                            val videos = TelegramTd.channelVideos(name, limit, messageId)
                            result.success(
                                videos.map { video ->
                                    mapOf(
                                        "title" to video.title,
                                        "url" to TelegramStreamServer.streamUrl(
                                            video.fileId,
                                            video.chatId,
                                            video.messageId,
                                        ),
                                        "thumbnail" to TelegramStreamServer.thumbUrl(
                                            video.thumbFileId,
                                        ),
                                        "pageUrl" to
                                            "https://t.me/${video.channel}/${video.messageId}",
                                        "publishedAt" to Instant.ofEpochSecond(
                                            video.date.toLong(),
                                        ).toString(),
                                        "duration" to video.duration,
                                        "size" to video.size,
                                    )
                                },
                            )
                        } catch (e: Exception) {
                            result.error("telegram", e.message ?: "Telegram failed", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Login steps answer with the state that follows, which the screen paints. */
    private fun login(result: MethodChannel.Result, step: () -> Unit) {
        try {
            step()
            result.success(TelegramTd.authMap())
        } catch (e: Exception) {
            result.error("telegram", e.message ?: "Telegram is not connected", null)
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
