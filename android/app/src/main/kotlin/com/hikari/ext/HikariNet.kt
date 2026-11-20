/*
 * Real host implementation of `com.hikari.ext.HikariNet`.
 *
 * Vendored signatures from the Hikari extension SDK (GPL-3.0, same licence as
 * this app). Extensions are dexed against these exact method descriptors, so
 * names, parameters, defaults and return types are ABI — do not "tidy" them.
 *
 * The SDK file in the extension repo is compile-only: every interesting body
 * there is a stub that forwards to `com.hikari.app.net.Http`, because upstream
 * relies on parent-first classloading to substitute its own implementation at
 * runtime. We are the host, so this is the implementation.
 */
package com.hikari.ext

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request
import org.json.JSONObject

/** A request the page fired that matched the capture regex. */
data class HikariWebViewResult(
    val url: String,
    val headers: Map<String, String> = emptyMap(),
)

/** Full HTTP response summary (for callers that must inspect errors). */
data class HikariResponse(
    val status: Int,
    val url: String,
    val body: String? = null,
)

object HikariNet {

    /** Browser-like headers for scraping (desktop Chrome fingerprint). */
    val browserHeaders: Map<String, String> = mapOf(
        "User-Agent" to com.hikari.app.net.Http.UA,
        "Accept" to "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language" to "en-US,en;q=0.9",
    )

    suspend fun getString(url: String, headers: Map<String, String> = emptyMap()): String? =
        withContext(Dispatchers.IO) {
            com.hikari.app.net.Http.getString(url, headers)
        }

    suspend fun postString(
        url: String,
        body: String,
        headers: Map<String, String> = emptyMap(),
        contentType: String = "application/json; charset=utf-8",
    ): String? = withContext(Dispatchers.IO) {
        com.hikari.app.net.Http.postString(url, body, headers, contentType)
    }

    suspend fun postJson(
        url: String,
        body: JSONObject,
        headers: Map<String, String> = emptyMap(),
    ): JSONObject? = withContext(Dispatchers.IO) {
        postString(
            url,
            body.toString(),
            headers + mapOf("Content-Type" to "application/json; charset=utf-8"),
        )?.let { runCatching { JSONObject(it) }.getOrNull() }
    }

    fun base64Decode(s: String): ByteArray? = runCatching {
        java.util.Base64.getDecoder().decode(s)
    }.getOrNull()

    fun base64Encode(bytes: ByteArray): String =
        java.util.Base64.getEncoder().encodeToString(bytes)

    suspend fun getStringSmart(
        url: String,
        headers: Map<String, String> = emptyMap(),
    ): String? = withContext(Dispatchers.IO) {
        com.hikari.app.net.Http.getStringSmart(url, headers)
    }

    suspend fun getStringRendered(url: String, timeoutMs: Long = 25_000): String? =
        withContext(Dispatchers.IO) {
            com.hikari.app.net.Http.getStringRendered(url, timeoutMs)
        }

    suspend fun getJson(url: String, headers: Map<String, String> = emptyMap()): JSONObject? =
        withContext(Dispatchers.IO) {
            getString(url, headers)?.let { runCatching { JSONObject(it) }.getOrNull() }
        }

    suspend fun getBytes(url: String, headers: Map<String, String> = emptyMap()): ByteArray? =
        withContext(Dispatchers.IO) {
            com.hikari.app.net.Http.getBytes(url, headers)
        }

    /** Full response (status + body) for callers that must see error codes. */
    suspend fun fetch(url: String, headers: Map<String, String> = emptyMap()): HikariResponse? =
        withContext(Dispatchers.IO) {
            try {
                com.hikari.app.net.Http.get(url, headers).use { r ->
                    HikariResponse(r.code, r.request.url.toString(), r.body?.string())
                }
            } catch (t: Throwable) {
                null
            }
        }

    /**
     * Runs [url] in a real Android WebView and returns every request the page
     * fired whose URL matches [capture] (or [additional]). This is what makes
     * embed players work: the player page's own JS runs in a browser and the
     * m3u8 it requests comes back here, headers included, ready for the player.
     */
    suspend fun resolveWithWebView(
        url: String,
        capture: Regex,
        additional: List<Regex> = emptyList(),
        timeoutMs: Long = 60_000,
        script: String? = null,
    ): List<HikariWebViewResult> = withContext(Dispatchers.IO) {
        val resolver = com.lagradost.cloudstream3.network.WebViewResolver(
            interceptUrl = capture,
            additionalUrls = additional,
            timeout = timeoutMs,
            script = script,
        )
        runCatching {
            val (fixed, extra) = resolver.resolveUsingWebView(url)
            buildList {
                fixed?.let { add(it.toResult()) }
                extra.forEach { add(it.toResult()) }
            }
        }.getOrDefault(emptyList())
    }

    private fun Request.toResult() =
        HikariWebViewResult(url.toString(), headers.toMap().filterValues { it.isNotBlank() })
}
