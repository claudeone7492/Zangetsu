package com.spyou.watch_app.hikari

import com.hikari.ext.HikariCatalog
import com.hikari.ext.HikariEpisode
import com.hikari.ext.HikariMedia
import com.hikari.ext.HikariMediaType
import com.hikari.ext.HikariStream
import org.json.JSONArray
import org.json.JSONObject

/**
 * Converts Hikari SDK models into the JSON shapes the Dart layer consumes.
 *
 * Keys are the contract with `lib/core/hikari/hikari_mapping.dart` — renaming
 * one without the other silently drops a field rather than failing loudly, so
 * both sides are covered by tests.
 */
object HikariJson {

    private fun HikariMediaType.wire(): String = when (this) {
        HikariMediaType.MOVIE -> "movie"
        HikariMediaType.SERIES -> "series"
        HikariMediaType.UNKNOWN -> "unknown"
    }

    fun mediaTypeFromWire(raw: String?): HikariMediaType = when (raw?.lowercase()) {
        "movie" -> HikariMediaType.MOVIE
        "series", "tv", "anime" -> HikariMediaType.SERIES
        else -> HikariMediaType.UNKNOWN
    }

    fun catalogToJson(catalog: HikariCatalog): JSONObject = JSONObject().apply {
        put("id", catalog.id)
        put("name", catalog.name)
        put("type", catalog.type.wire())
        put("rawType", catalog.rawType)
    }

    fun mediaToJson(media: HikariMedia): JSONObject = JSONObject().apply {
        put("id", media.id)
        put("title", media.title)
        put("type", media.type.wire())
        put("rawType", media.rawType)
        put("posterUrl", media.posterUrl ?: JSONObject.NULL)
        put("backdropUrl", media.backdropUrl ?: JSONObject.NULL)
        put("overview", media.overview ?: JSONObject.NULL)
        put("year", media.year ?: JSONObject.NULL)
        put("genres", JSONArray(media.genres))
    }

    fun episodeToJson(episode: HikariEpisode): JSONObject = JSONObject().apply {
        put("number", episode.number)
        put("id", episode.id)
        put("name", episode.name ?: JSONObject.NULL)
        put("image", episode.image ?: JSONObject.NULL)
        put("season", episode.season)
    }

    fun streamToJson(stream: HikariStream): JSONObject = JSONObject().apply {
        put("name", stream.name)
        put("url", stream.url)
        put("headers", JSONObject(stream.headers as Map<*, *>))
        put("isM3u8", stream.isM3u8)
        put("isMpd", stream.isMpd)
        put("isTorrent", stream.isTorrent)
        put("infoHash", stream.infoHash ?: JSONObject.NULL)
        put("fileIdx", stream.fileIdx ?: JSONObject.NULL)
        put("trackers", JSONArray(stream.trackers))
        put("ytId", stream.ytId ?: JSONObject.NULL)
        put("externalUrl", stream.externalUrl)
        put(
            "subtitles",
            JSONArray().apply {
                stream.subtitles.forEach {
                    put(JSONObject().put("lang", it.lang).put("url", it.url))
                }
            },
        )
    }

    fun mediaListJson(list: List<HikariMedia>): JSONArray =
        JSONArray().apply { list.forEach { put(mediaToJson(it)) } }

    fun catalogListJson(list: List<HikariCatalog>): JSONArray =
        JSONArray().apply { list.forEach { put(catalogToJson(it)) } }

    /** Rebuilds the [HikariMedia] an extension expects as input. */
    fun mediaFromJson(json: JSONObject): HikariMedia = HikariMedia(
        id = json.optString("id"),
        title = json.optString("title"),
        type = mediaTypeFromWire(json.optString("type")),
        posterUrl = json.optStringOrNull("posterUrl"),
        year = if (json.isNull("year")) null else json.optInt("year"),
        overview = json.optStringOrNull("overview"),
        genres = json.optJSONArray("genres")?.let { arr ->
            (0 until arr.length()).map { arr.optString(it) }
        } ?: emptyList(),
        backdropUrl = json.optStringOrNull("backdropUrl"),
        rawType = json.optString("rawType"),
    )

    fun catalogFromJson(json: JSONObject): HikariCatalog = HikariCatalog(
        id = json.optString("id"),
        name = json.optString("name"),
        type = mediaTypeFromWire(json.optString("type")),
        rawType = json.optString("rawType"),
    )

    fun episodeFromJson(json: JSONObject): HikariEpisode = HikariEpisode(
        number = json.optInt("number"),
        id = json.optString("id"),
        name = json.optStringOrNull("name"),
        image = json.optStringOrNull("image"),
        season = json.optInt("season", 1),
    )

    /** `null`-safe string read: `optString` returns "null" for JSON null. */
    private fun JSONObject.optStringOrNull(key: String): String? =
        if (isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }
}
