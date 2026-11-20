/*
 * Real host implementation of the app-internal surface the Hikari SDK calls.
 *
 * The extension repo ships `stubs/HttpStub.kt` purely so *extensions* compile;
 * at runtime the real classes in the host APK win because PathClassLoader is
 * parent-first. We are the host, so these are the real ones.
 *
 * Everything here delegates to CloudStream's `app.baseClient` rather than a
 * private OkHttpClient. That client already carries the pieces a scraper needs
 * and that this app has tuned: Conscrypt TLS, the opt-in DoH resolver, the
 * Cloudflare-clearing interceptor and a browser UA. A second, separately
 * configured client would drift from it and fail on exactly the CDNs the
 * CloudStream path already solves.
 */
package com.hikari.app.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response

object Http {

    /** Desktop Chrome fingerprint, as upstream Hikari uses for scraping. */
    const val UA =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    /**
     * Resolved lazily, never cached in a val: `PluginHost` replaces
     * `app.baseClient` at boot (to install the DoH DNS), and a cached client
     * would silently keep the pre-DoH one.
     */
    private fun client(): OkHttpClient = com.lagradost.cloudstream3.app.baseClient

    private fun Request.Builder.withHeaders(headers: Map<String, String>): Request.Builder {
        if (!headers.keys.any { it.equals("User-Agent", ignoreCase = true) }) {
            header("User-Agent", UA)
        }
        headers.forEach { (k, v) -> header(k, v) }
        return this
    }

    /** Blocking GET. Callers are the suspend wrappers below, on IO. */
    fun get(url: String, headers: Map<String, String> = emptyMap()): Response {
        val request = Request.Builder().url(url).withHeaders(headers).build()
        return client().newCall(request).execute()
    }

    fun getString(url: String, headers: Map<String, String> = emptyMap()): String? =
        runCatching { get(url, headers).use { it.body?.string() } }.getOrNull()

    fun postString(
        url: String,
        body: String,
        headers: Map<String, String> = emptyMap(),
        contentType: String = "application/json; charset=utf-8",
    ): String? = runCatching {
        val request = Request.Builder()
            .url(url)
            .withHeaders(headers)
            .post(body.toRequestBody(contentType.toMediaType()))
            .build()
        client().newCall(request).execute().use { it.body?.string() }
    }.getOrNull()

    fun getBytes(url: String, headers: Map<String, String> = emptyMap()): ByteArray? =
        runCatching { get(url, headers).use { it.body?.bytes() } }.getOrNull()

    /**
     * GET, falling back to a real WebView when the plain client is refused.
     *
     * A WAF challenge page comes back as HTTP 200 with JavaScript in it, so a
     * status-code check cannot detect it — the body has to be inspected. We
     * treat "no body", a challenge signature, or a suspiciously small document
     * as blocked, and only then pay the (slow, main-thread) WebView cost.
     */
    suspend fun getStringSmart(
        url: String,
        headers: Map<String, String> = emptyMap(),
    ): String? = withContext(Dispatchers.IO) {
        val plain = getString(url, headers)
        if (plain != null && !looksBlocked(plain)) return@withContext plain
        getStringRendered(url) ?: plain
    }

    /**
     * Renders [url] in a real Android WebView and returns the settled HTML.
     *
     * Delegates to CloudStream's `WebViewResolver`, which already owns the
     * main-thread hop, the load timeout and the teardown. The regex matches any
     * URL so the resolver completes on the first request the page fires; the
     * rendered document is read back from the WebView itself.
     */
    suspend fun getStringRendered(url: String, timeoutMs: Long = 25_000): String? =
        withContext(Dispatchers.IO) {
            runCatching {
                com.lagradost.cloudstream3.network.WebViewResolver(
                    interceptUrl = Regex(".*"),
                    timeout = timeoutMs,
                ).resolveUsingWebView(url).first?.url?.toString()?.let { settled ->
                    // The resolver hands back the request it captured, not the
                    // document; re-read the settled page through the client with
                    // the cookies the WebView collected.
                    getString(settled, emptyMap())
                }
            }.getOrNull()
        }

    /** Signatures of the interstitial pages that mean "blocked", not "content". */
    private val BLOCK_MARKERS = listOf(
        "just a moment",
        "checking your browser",
        "cf-browser-verification",
        "challenge-platform",
        "enable javascript and cookies to continue",
        "attention required! | cloudflare",
    )

    internal fun looksBlocked(body: String): Boolean {
        if (body.isBlank()) return true
        val lower = body.lowercase()
        return BLOCK_MARKERS.any { lower.contains(it) }
    }
}
