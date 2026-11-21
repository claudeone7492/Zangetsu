package com.spyou.watch_app.parity

/** A resolver the CS3 host can try when a plugin returns a wrapper page. */
interface Cs3Resolver {
    val id: String
    fun matches(host: String): Boolean
    fun resolve(pageUrl: String, html: String): List<String>
}

private val MEDIA = Regex(
    """https?://[^"'\s<>]+?\.(?:m3u8|mp4|mkv)(?:\?[^"'\s<>]*)?""",
    RegexOption.IGNORE_CASE,
)

private fun media(html: String): List<String> =
    MEDIA.findAll(html).map { it.value }.distinct().toList()

object NewPipeResolver : Cs3Resolver {
    override val id = "newpipe"
    override fun matches(host: String) = host.contains("youtube", true) || host.contains("youtu.be", true)
    override fun resolve(pageUrl: String, html: String): List<String> = media(html)
}

object MovieBlastResolver : Cs3Resolver {
    override val id = "movieblast"
    override fun matches(host: String) = host.contains("movieblast", true)
    override fun resolve(pageUrl: String, html: String): List<String> = media(html)
}

object MlbdResolver : Cs3Resolver {
    override val id = "mlbd"
    override fun matches(host: String) = host.contains("mlbd", true) || host.contains("multi", true)
    override fun resolve(pageUrl: String, html: String): List<String> = media(html)
}

/** Last resort: any media URL on the page, whatever the host. */
object FallbackResolver : Cs3Resolver {
    override val id = "fallback"
    override fun matches(host: String) = true
    override fun resolve(pageUrl: String, html: String): List<String> = media(html)
}

object Cs3BuiltInResolvers {
    fun all(): List<Cs3Resolver> =
        listOf(NewPipeResolver, MovieBlastResolver, MlbdResolver, FallbackResolver)

    /** First resolver that matches the host and finds a media URL. */
    fun resolve(pageUrl: String, html: String): List<String> {
        val host = runCatching { java.net.URI(pageUrl).host.orEmpty() }.getOrDefault("")
        for (resolver in all()) {
            if (!resolver.matches(host)) continue
            val found = resolver.resolve(pageUrl, html)
            if (found.isNotEmpty()) return found
        }
        return emptyList()
    }
}
