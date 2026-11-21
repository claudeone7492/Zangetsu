package com.spyou.watch_app.telegram

import android.content.Context
import android.os.Build
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import org.drinkless.tdlib.Client
import org.drinkless.tdlib.TdApi
import java.io.File
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume

/**
 * The Telegram client, ported from Hikari's `telegram/Td.kt`.
 *
 * Hikari's version also draws a chat list, in-chat search, album tails and a
 * download manager, because its Telegram tab is a file browser. This app's tab
 * browses one channel and plays its videos, so what is kept is the part that
 * serves that: the client lifecycle, the phone/code/password login, resolving a
 * channel, and the file reads the stream server needs.
 *
 * The native half is Telegram X's TDLib build, vendored under `jniLibs/` with
 * the `org.drinkless.tdlib` bindings it registers against — see
 * `jniLibs/README.md` for provenance and the `libc++_shared.so` rename.
 */
object TelegramTd {
    /** The login states the Dart screen renders. */
    sealed class Auth {
        /** No api_id/api_hash yet, so no client was ever started. */
        data object Idle : Auth()

        /** The native library or the client could not start. */
        data class Unavailable(val reason: String) : Auth()
        data object Starting : Auth()
        data object WaitPhone : Auth()
        data object WaitCode : Auth()
        data class WaitPassword(val hint: String) : Auth()
        data class WaitRegistration(val terms: String) : Auth()
        data object Ready : Auth()
        data object Closed : Auth()
    }

    /** One playable video from a channel, as the bridge hands it to Dart. */
    data class ChannelVideo(
        val chatId: Long,
        val messageId: Long,
        val fileId: Int,
        val title: String,
        val duration: Int,
        val size: Long,
        val date: Int,
        val thumbFileId: Int,
        val channel: String,
    )

    /** One file's download state, straight out of TDLib. */
    data class FileState(
        val path: String,
        val size: Long,
        val downloadedPrefix: Long,
        val complete: Boolean,
        val canBeDownloaded: Boolean,
    )

    /** Whether the native library loaded. True before any client exists, so the
     *  screen can offer a sign-in on a build that has TDLib but no session. */
    @Volatile
    var linked: Boolean = false
        private set

    @Volatile
    var loadError: String? = null
        private set

    private const val PREFS = "telegram_td"
    private const val HISTORY_PAGE = 100
    private const val AHEAD_BYTES: Long = 64L * 1024 * 1024

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val started = AtomicBoolean(false)

    /** Set when new credentials are about to replace a running client. */
    private val restartWanted = AtomicBoolean(false)

    @Volatile
    private var client: Client? = null

    @Volatile
    private var auth: Auth = Auth.Idle

    @Volatile
    private var creds: Pair<Int, String>? = null

    @Volatile
    private var appContext: Context? = null

    private val fileValues = ConcurrentHashMap<Int, TdApi.File>()
    private val fetchedFiles = ConcurrentHashMap<Int, TdApi.File>()
    private val downloadErrors = ConcurrentHashMap<Int, String>()

    // ---- lifecycle -------------------------------------------------------

    fun init(context: Context) {
        appContext = context.applicationContext
        if (client != null || loadError != null) return
        if (!loadLibrary()) return
        if (!started.compareAndSet(false, true)) return
        val stored = storedCredentials(context)
        if (stored == null) {
            started.set(false)
            auth = Auth.Idle
            return
        }
        start(stored.first, stored.second)
    }

    /** Loads `libtdjni` once; records why it could not. */
    private fun loadLibrary(): Boolean {
        if (linked) return true
        val error = runCatching {
            System.loadLibrary("tdjni")
            null
        }.getOrElse { it.message ?: it.toString() }
        if (error != null) {
            loadError = error
            auth = Auth.Unavailable(error)
            return false
        }
        linked = true
        return true
    }

    fun auth(): Auth = auth

    /** `waitPassword` carries a hint and `unavailable` a reason, so the state
     *  travels as a map rather than a bare name. */
    fun authMap(): Map<String, Any?> = when (val state = auth) {
        is Auth.Unavailable -> mapOf("state" to "unavailable", "reason" to state.reason)
        is Auth.WaitPassword -> mapOf("state" to "waitPassword", "hint" to state.hint)
        is Auth.WaitRegistration -> mapOf("state" to "waitRegistration", "terms" to state.terms)
        Auth.Idle -> mapOf("state" to "idle")
        Auth.Starting -> mapOf("state" to "starting")
        Auth.WaitPhone -> mapOf("state" to "waitPhone")
        Auth.WaitCode -> mapOf("state" to "waitCode")
        Auth.Ready -> mapOf("state" to "ready")
        Auth.Closed -> mapOf("state" to "closed")
    }

    fun setCredentials(context: Context, apiId: Int, apiHash: String) {
        if (apiId <= 0 || apiHash.isBlank()) return
        appContext = context.applicationContext
        val previous = creds
        creds = apiId to apiHash
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putInt("apiId", apiId)
            .putString("apiHash", apiHash)
            .apply()
        if (client == null) {
            start(apiId, apiHash)
        } else if (previous != (apiId to apiHash)) {
            // Another app's credentials need a new session; the old client is
            // closed first so two logins never share one database. The restart
            // happens on Auth.Closed, once TDLib has released the old one.
            restartWanted.set(true)
            runCatching { client?.send(TdApi.Close(), null, null) }
        }
    }

    private fun storedCredentials(context: Context): Pair<Int, String>? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val id = prefs.getInt("apiId", 0)
        val hash = prefs.getString("apiHash", "").orEmpty()
        return if (id > 0 && hash.length == 32) id to hash else null
    }

    private fun start(apiId: Int, apiHash: String) {
        if (client != null) return
        creds = apiId to apiHash
        auth = Auth.Starting
        if (!loadLibrary()) {
            started.set(false)
            return
        }
        runCatching {
            Client.create(
                { update -> onUpdate(update) },
                { error -> note(error) },
                { error -> note(error) },
            )
        }.onSuccess { created ->
            loadError = null
            client = created
            started.set(true)
            auth = Auth.Starting
        }.onFailure { error ->
            loadError = error.message ?: error.toString()
            started.set(false)
            auth = Auth.Unavailable(loadError.orEmpty())
        }
    }

    private fun note(error: Throwable) {
        Log.w("TelegramTd", "TDLib error: ${error.message}")
    }

    fun signOut() {
        runCatching { client?.send(TdApi.LogOut(), null, null) }
        fileValues.clear()
        fetchedFiles.clear()
        downloadErrors.clear()
    }

    // ---- login -----------------------------------------------------------

    fun normalizePhone(phone: String): String {
        val digits = phone.filter { it.isDigit() }
        if (digits.isEmpty()) return ""
        return "+" + digits.trimStart('0').ifEmpty { digits }
    }

    /** The api_id as my.telegram.org shows it: digits only. */
    fun apiIdOf(raw: String): Int? =
        raw.trim().filter { it in '0'..'9' }.toIntOrNull()?.takeIf { it > 0 }

    /** The api_hash as it should be sent: 32 hex characters, or null. */
    fun apiHashOf(raw: String): String? =
        raw.trim().filter { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }
            .lowercase()
            .takeIf { it.length == 32 }

    fun submitPhone(phone: String) {
        val running = client ?: throw IllegalStateException("Telegram is not connected")
        val settings = TdApi.PhoneNumberAuthenticationSettings(
            /* allowFlashCall = */ false,
            /* allowMissedCall = */ false,
            /* isCurrentPhoneNumber = */ false,
            /* hasUnknownPhoneNumber = */ false,
            /* allowSmsRetrieverApi = */ true,
            /* firebaseAuthenticationSettings = */ null,
            /* authenticationTokens = */ emptyArray<String>(),
        )
        running.send(TdApi.SetAuthenticationPhoneNumber(normalizePhone(phone), settings), null, null)
    }

    fun submitCode(code: String) {
        val running = client ?: throw IllegalStateException("Telegram is not connected")
        running.send(
            TdApi.CheckAuthenticationCode(code.filter { !it.isWhitespace() }),
            null,
            null,
        )
    }

    fun submitPassword(password: String) {
        val running = client ?: throw IllegalStateException("Telegram is not connected")
        running.send(TdApi.CheckAuthenticationPassword(password), null, null)
    }

    fun submitRegistration(first: String, last: String) {
        val running = client ?: throw IllegalStateException("Telegram is not connected")
        running.send(TdApi.RegisterUser(first, last, true), null, null)
    }

    private fun onUpdate(update: TdApi.Object) {
        when (update) {
            is TdApi.UpdateAuthorizationState -> onAuthState(update.authorizationState)
            is TdApi.UpdateFile -> fileValues[update.file.id] = update.file
            else -> Unit
        }
    }

    private fun onAuthState(state: TdApi.AuthorizationState) {
        when (state) {
            is TdApi.AuthorizationStateWaitTdlibParameters -> sendParameters()
            is TdApi.AuthorizationStateWaitPhoneNumber -> auth = Auth.WaitPhone
            is TdApi.AuthorizationStateWaitCode -> auth = Auth.WaitCode
            is TdApi.AuthorizationStateWaitPassword ->
                auth = Auth.WaitPassword(state.passwordHint.orEmpty())
            is TdApi.AuthorizationStateWaitRegistration ->
                auth = Auth.WaitRegistration(state.termsOfService?.text?.text.orEmpty())
            is TdApi.AuthorizationStateReady -> auth = Auth.Ready
            is TdApi.AuthorizationStateLoggingOut,
            is TdApi.AuthorizationStateClosing -> Unit
            is TdApi.AuthorizationStateClosed -> {
                client = null
                started.set(false)
                fileValues.clear()
                fetchedFiles.clear()
                downloadErrors.clear()
                auth = Auth.Closed
                if (restartWanted.getAndSet(false)) {
                    creds?.let { (apiId, apiHash) -> start(apiId, apiHash) }
                }
            }
            // Email, Google/Apple sign-in and the premium step are not
            // implemented; the phone flow is the one every account has.
            else -> auth = Auth.Closed
        }
    }

    private fun sendParameters() {
        val (apiId, apiHash) = creds ?: return
        val root = File(
            appContext?.filesDir ?: return,
            "tdlib",
        )
        File(root, "db").mkdirs()
        File(root, "files").mkdirs()
        client?.send(
            TdApi.SetTdlibParameters(
                /* useTestDc = */ false,
                /* databaseDirectory = */ File(root, "db").absolutePath,
                /* filesDirectory = */ File(root, "files").absolutePath,
                /* databaseEncryptionKey = */ ByteArray(0),
                /* useFileDatabase = */ true,
                /* useChatInfoDatabase = */ true,
                /* useMessageDatabase = */ true,
                /* useSecretChats = */ false,
                /* apiId = */ apiId,
                /* apiHash = */ apiHash,
                /* systemLanguageCode = */ Locale.getDefault().language.ifBlank { "en" },
                /* deviceModel = */ Build.MANUFACTURER + " " + Build.MODEL,
                /* systemVersion = */ "Android " + Build.VERSION.RELEASE,
                /* applicationVersion = */ "Zangetsu",
            ),
            null,
            null,
        )
    }

    // ---- TDLib plumbing --------------------------------------------------

    private suspend fun query(function: TdApi.Function<*>): TdApi.Object? {
        val running = client ?: return null
        return suspendCancellableCoroutine { cont ->
            runCatching {
                running.send(function) { result ->
                    if (cont.isActive) cont.resume(if (result is TdApi.Error) null else result)
                }
            }.onFailure { if (cont.isActive) cont.resume(null) }
        }
    }

    // ---- channels --------------------------------------------------------

    /** `"@name"`, `"name"`, a `t.me` link or a post link → the bare name. */
    private fun handleOf(raw: String): String? {
        val name = raw.trim()
            .removePrefix("@")
            .removePrefix("https://t.me/")
            .removePrefix("http://t.me/")
            .removePrefix("t.me/")
            .removePrefix("s/")
            .substringBefore('/')
            .substringBefore('?')
        return name.takeIf { it.isNotBlank() }
    }

    /**
     * A channel's videos, newest first.
     *
     * [messageId] narrows the answer to one post, which is what a `t.me/x/123`
     * link means. Without it the newest [limit] messages are walked: TDLib
     * returns a history page newest-first, which is what the tab lists.
     */
    suspend fun channelVideos(
        username: String,
        limit: Int,
        messageId: Long = 0,
    ): List<ChannelVideo> {
        val name = handleOf(username) ?: return emptyList()
        val chat = query(TdApi.SearchPublicChat(name)) as? TdApi.Chat ?: return emptyList()
        if (messageId > 0) {
            val message = query(TdApi.GetMessage(chat.id, messageId)) as? TdApi.Message
                ?: return emptyList()
            return listOfNotNull(videoOf(name, chat.id, message))
        }
        val history = query(
            TdApi.GetChatHistory(chat.id, 0, 0, limit.coerceIn(1, HISTORY_PAGE), false),
        ) as? TdApi.Messages ?: return emptyList()

        val seen = HashSet<Long>()
        val out = ArrayList<ChannelVideo>()
        for (message in history.messages) {
            val video = videoOf(name, chat.id, message) ?: continue
            if (seen.add(video.messageId)) out.add(video)
        }
        return out.sortedByDescending { it.messageId }
    }

    private fun videoOf(channel: String, chatId: Long, message: TdApi.Message): ChannelVideo? {
        val content = message.content
        return when (content) {
            is TdApi.MessageVideo -> ChannelVideo(
                chatId = chatId,
                messageId = message.id,
                fileId = content.video.video.id,
                title = content.caption.text.ifBlank { content.video.fileName }
                    .ifBlank { "Video" },
                duration = content.video.duration,
                size = content.video.video.size,
                date = message.date,
                thumbFileId = content.video.thumbnail?.file?.id ?: 0,
                channel = channel,
            )
            is TdApi.MessageAnimation -> ChannelVideo(
                chatId = chatId,
                messageId = message.id,
                fileId = content.animation.animation.id,
                title = content.caption.text.ifBlank { content.animation.fileName }
                    .ifBlank { "Video" },
                duration = content.animation.duration,
                size = content.animation.animation.size,
                date = message.date,
                thumbFileId = content.animation.thumbnail?.file?.id ?: 0,
                channel = channel,
            )
            is TdApi.MessageDocument -> {
                val document = content.document
                if (!document.mimeType.startsWith("video/")) return null
                ChannelVideo(
                    chatId = chatId,
                    messageId = message.id,
                    fileId = document.document.id,
                    title = content.caption.text.ifBlank { document.fileName }
                        .ifBlank { "Video" },
                    duration = 0,
                    size = document.document.size,
                    date = message.date,
                    thumbFileId = document.thumbnail?.file?.id ?: 0,
                    channel = channel,
                )
            }
            else -> null
        }
    }

    // ---- files -----------------------------------------------------------

    fun fileState(fileId: Int): FileState? {
        val file = fileValues[fileId] ?: fetchedFiles[fileId] ?: return null
        val local = file.local
        return FileState(
            path = local?.path.orEmpty(),
            size = maxOf(file.size, file.expectedSize),
            downloadedPrefix = local?.downloadedPrefixSize ?: 0L,
            complete = local?.isDownloadingCompleted == true,
            canBeDownloaded = local?.canBeDownloaded == true ||
                local?.isDownloadingActive == true ||
                local?.isDownloadingCompleted == true,
        )
    }

    /** [fileState], asking TDLib first: a file nobody has downloaded has never
     *  appeared in an update, so the cache alone knows nothing. */
    suspend fun stateOf(fileId: Int): FileState? {
        if (fileValues[fileId] == null && fetchedFiles[fileId] == null) {
            val file = query(TdApi.GetFile(fileId)) as? TdApi.File ?: return null
            fetchedFiles[fileId] = file
        }
        return fileState(fileId)
    }

    fun downloadError(fileId: Int): String? = downloadErrors[fileId]

    fun clearDownloadError(fileId: Int) {
        downloadErrors.remove(fileId)
    }

    fun request(fileId: Int, offset: Long, limit: Long) {
        val running = client ?: return
        runCatching {
            running.send(
                TdApi.DownloadFile(fileId, 32, offset, limit, false),
                { result ->
                    if (result is TdApi.Error) {
                        downloadErrors[fileId] = result.message
                    } else {
                        downloadErrors.remove(fileId)
                    }
                },
                null,
            )
        }
    }

    suspend fun downloadedFrom(fileId: Int, offset: Long): Long =
        (query(TdApi.GetFileDownloadedPrefixSize(fileId, offset))
            as? TdApi.FileDownloadedPrefixSize)?.size ?: -1L

    /**
     * Waits until [fileId] has bytes at [offset] on disk and returns how many
     * contiguous ones are readable from there ([Long.MAX_VALUE] once complete).
     *
     * Runs on the stream server's connection thread, which is why it bridges
     * into a coroutine instead of being one.
     */
    fun awaitReadable(fileId: Int, offset: Long, timeoutMs: Long): Long = runBlocking {
        val deadline = System.currentTimeMillis() + timeoutMs
        var asked = false
        while (true) {
            val state = stateOf(fileId)
                ?: throw IllegalStateException("Telegram does not know file $fileId")
            if (state.complete) return@runBlocking Long.MAX_VALUE
            val ready = downloadedFrom(fileId, offset)
            if (ready > 0) return@runBlocking ready
            downloadErrors[fileId]?.let { throw IllegalStateException(it) }
            if (!asked) {
                request(fileId, offset, AHEAD_BYTES)
                asked = true
            } else if (System.currentTimeMillis() >= deadline) {
                throw IllegalStateException("Telegram is not sending this video")
            }
            delay(150)
        }
        @Suppress("UNREACHABLE_CODE")
        0L
    }

    /** Warms a thumbnail so the list can paint it, without waiting for it. */
    fun warmThumb(fileId: Int) {
        if (fileId == 0) return
        scope.launch {
            if (stateOf(fileId)?.complete == false) request(fileId, 0, 1024L * 1024L)
        }
    }

    fun thumbPath(fileId: Int): String? {
        val state = fileState(fileId) ?: return null
        return if (state.complete) state.path else null
    }
}
