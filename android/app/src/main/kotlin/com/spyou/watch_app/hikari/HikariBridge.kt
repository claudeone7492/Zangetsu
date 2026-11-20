package com.spyou.watch_app.hikari

import android.content.Context
import com.hikari.ext.HikariCatalog
import com.hikari.ext.HikariEpisode
import com.hikari.ext.HikariProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * MethodChannel host for `.hiki` extensions (`zangetsu/hikari`).
 *
 * Extensions are third-party Kotlin running in-process, so every call is
 * treated as hostile: each one runs on a dedicated executor (never the platform
 * main thread), every failure is converted to a `hikari_error` result rather
 * than allowed to propagate, and no exception from an extension is ever
 * rethrown into Flutter.
 *
 * Providers are cached per extension file. A `.hiki`'s `load()` may be slow
 * (class loading + dex optimisation), so [loaded] is the single source of truth
 * and a repeat install of the same file replaces the cached instance.
 */
class HikariBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) {

    private val channel = MethodChannel(messenger, CHANNEL)

    /** Serialised because dex optimisation and provider construction are heavy. */
    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "hikari-bridge").apply { isDaemon = true }
    }

    /** extension file path → loaded provider. */
    private val loaded = ConcurrentHashMap<String, HikariLoadedExtension>()

    init {
        channel.setMethodCallHandler { call, result -> executor.execute { handle(call, result) } }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "load" -> load(call, result)
                "unload" -> {
                    val path = call.argument<String>("path").orEmpty()
                    loaded.remove(path)
                    result.success(true)
                }
                "catalogs" -> withProvider(call, result) { p, _ ->
                    HikariJson.catalogListJson(p.catalogs())
                }
                "search" -> withProvider(call, result) { p, _ ->
                    val query = call.argument<String>("query").orEmpty()
                    val page = call.argument<Int>("page") ?: 1
                    HikariJson.mediaListJson(p.search(query, page))
                }
                "catalog" -> withProvider(call, result) { p, _ ->
                    val catalog = HikariJson.catalogFromJson(
                        JSONObject(call.argument<String>("catalog").orEmpty()),
                    )
                    val page = call.argument<Int>("page") ?: 1
                    HikariJson.mediaListJson(p.getCatalog(catalog, page))
                }
                "meta" -> withProvider(call, result) { p, _ ->
                    val media = HikariJson.mediaFromJson(
                        JSONObject(call.argument<String>("media").orEmpty()),
                    )
                    HikariJson.mediaToJson(p.getMeta(media))
                }
                "episodes" -> withProvider(call, result) { p, _ ->
                    val media = HikariJson.mediaFromJson(
                        JSONObject(call.argument<String>("media").orEmpty()),
                    )
                    val eps = p.getEpisodes(media)
                    if (eps == null) {
                        org.json.JSONArray()
                    } else {
                        org.json.JSONArray().apply {
                            eps.forEach { put(HikariJson.episodeToJson(it)) }
                        }
                    }
                }
                "streams" -> withProvider(call, result) { p, _ ->
                    val media = HikariJson.mediaFromJson(
                        JSONObject(call.argument<String>("media").orEmpty()),
                    )
                    val episodeJson = call.argument<String>("episode")
                    val episode: HikariEpisode? =
                        if (episodeJson.isNullOrBlank() || episodeJson == "null") {
                            null
                        } else {
                            HikariJson.episodeFromJson(JSONObject(episodeJson))
                        }
                    val streams = p.getStreams(media, episode)
                    org.json.JSONArray().apply {
                        streams.forEach { put(HikariJson.streamToJson(it)) }
                    }
                }
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            // Includes NoClassDefFoundError / ExceptionInInitializerError from a
            // broken extension: report it, never let it reach the platform.
            result.error("hikari_error", t.message ?: t.javaClass.simpleName, null)
        }
    }

    private fun load(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("bad_args", "path required", null)
            return
        }
        val file = File(path)
        if (!file.exists()) {
            result.error("hikari_error", "No such extension file: $path", null)
            return
        }
        HikariExtensionLoader.load(context, file)
            .onSuccess { ext ->
                loaded[path] = ext
                result.success(
                    mapOf(
                        "name" to ext.manifest.name,
                        "version" to ext.manifest.version,
                        "mainClass" to ext.manifest.mainClass,
                        "providerId" to ext.provider.id,
                        "providerName" to ext.provider.name,
                        "mainUrl" to ext.provider.mainUrl,
                        "description" to ext.provider.description,
                        "iconUrl" to ext.provider.iconUrl,
                        "tvTypes" to ext.provider.tvTypes.map { it.name.lowercase() },
                    ),
                )
            }
            .onFailure { result.error("hikari_error", it.message ?: "load failed", null) }
    }

    /**
     * Runs [block] against the cached provider for the call's `path`, converting
     * a missing provider into a clear error instead of a null dereference.
     */
    private fun <T> withProvider(
        call: MethodCall,
        result: MethodChannel.Result,
        block: suspend (HikariProvider, String) -> T,
    ) {
        val path = call.argument<String>("path").orEmpty()
        val ext = loaded[path]
        if (ext == null) {
            result.error("hikari_error", "Extension not loaded: $path", null)
            return
        }
        // runBlocking is safe here: this is the bridge's own executor thread, and
        // the provider's suspend functions already dispatch their IO internally.
        val value = runBlocking { block(ext.provider, path) }
        result.success(value)
    }

    companion object {
        const val CHANNEL = "zangetsu/hikari"
    }
}
