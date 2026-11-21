package com.spyou.watch_app.telegram

import android.util.Log
import java.io.BufferedOutputStream
import java.io.IOException
import java.io.RandomAccessFile
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.atomic.AtomicInteger
import kotlin.concurrent.thread

/**
 * A loopback HTTP server that serves TDLib's files, with range support.
 *
 * Hikari plays Telegram videos through a media3 `DataSource` (`TdFileDataSource`)
 * because its player is ExoPlayer. This app's player is mpv, which wants a URL,
 * so the same job is done by a socket on 127.0.0.1: mpv asks for a range, the
 * server waits until TDLib has that range on disk, and writes it out.
 *
 * Bound to loopback only, and the port is ephemeral, so nothing on the network
 * can reach a signed-in user's files.
 */
object TelegramStreamServer {
    private const val CHUNK = 64 * 1024
    private const val WAIT_MS = 20_000L

    private var server: ServerSocket? = null
    private var port = 0
    private val clients = AtomicInteger(0)

    /** Starts the server if it is not running and returns its port. */
    @Synchronized
    fun ensure(): Int {
        val running = server
        if (running != null && !running.isClosed) return port
        val socket = ServerSocket(0, 8, InetAddress.getByName("127.0.0.1"))
        port = socket.localPort
        server = socket
        thread(name = "telegram-stream", isDaemon = true) {
            while (!socket.isClosed) {
                val client = try {
                    socket.accept()
                } catch (_: IOException) {
                    break
                }
                thread(name = "telegram-stream-${clients.incrementAndGet()}", isDaemon = true) {
                    try {
                        serve(client)
                    } catch (e: Exception) {
                        Log.w("TelegramStream", "connection failed: ${e.message}")
                    } finally {
                        runCatching { client.close() }
                    }
                }
            }
        }
        return port
    }

    fun streamUrl(fileId: Int, chatId: Long, messageId: Long): String =
        "http://127.0.0.1:${ensure()}/stream?id=$fileId&chat=$chatId&msg=$messageId"

    fun thumbUrl(fileId: Int): String? =
        if (fileId == 0) null else "http://127.0.0.1:${ensure()}/thumb?id=$fileId"

    private fun serve(client: Socket) {
        val input = client.getInputStream().bufferedReader()
        val request = input.readLine() ?: return
        // Drain the headers; only the request line and Range matter here.
        var range: String? = null
        while (true) {
            val line = input.readLine() ?: break
            if (line.isEmpty()) break
            if (line.startsWith("Range:", ignoreCase = true)) {
                range = line.substringAfter(':').trim()
            }
        }
        val parts = request.split(' ')
        if (parts.size < 2) return
        val target = parts[1]
        val uri = java.net.URI("http://127.0.0.1$target")
        val query = uri.query.orEmpty()
            .split('&')
            .mapNotNull { pair ->
                val bits = pair.split('=', limit = 2)
                if (bits.size == 2) bits[0] to bits[1] else null
            }
            .toMap()
        val fileId = query["id"]?.toIntOrNull() ?: return
        val out = BufferedOutputStream(client.getOutputStream())
        when (uri.path) {
            "/stream" -> stream(fileId, range, out)
            "/thumb" -> thumb(fileId, out)
            else -> writeStatus(out, 404, "Not found")
        }
        out.flush()
    }

    private fun thumb(fileId: Int, out: BufferedOutputStream) {
        TelegramTd.warmThumb(fileId)
        val deadline = System.currentTimeMillis() + WAIT_MS
        var path: String? = null
        while (System.currentTimeMillis() < deadline) {
            path = TelegramTd.thumbPath(fileId)
            if (path != null) break
            Thread.sleep(100)
        }
        if (path == null) {
            writeStatus(out, 404, "Thumbnail not ready")
            return
        }
        val bytes = runCatching { java.io.File(path).readBytes() }.getOrNull()
        if (bytes == null) {
            writeStatus(out, 404, "Thumbnail missing")
            return
        }
        val head = buildString {
            append("HTTP/1.1 200 OK\r\n")
            append("Content-Type: image/jpeg\r\n")
            append("Content-Length: ${bytes.size}\r\n")
            append("Cache-Control: max-age=600\r\n")
            append("Connection: close\r\n\r\n")
        }
        out.write(head.toByteArray())
        out.write(bytes)
    }

    private fun stream(fileId: Int, range: String?, out: BufferedOutputStream) {
        TelegramTd.clearDownloadError(fileId)
        val state = try {
            kotlinx.coroutines.runBlocking { TelegramTd.stateOf(fileId) }
        } catch (e: Exception) {
            null
        }
        if (state == null) {
            writeStatus(out, 404, "Telegram does not know this video")
            return
        }
        val size = state.size
        if (size <= 0) {
            writeStatus(out, 404, "Telegram has no size for this video")
            return
        }

        val (start, end) = parseRange(range, size)
        if (start >= size) {
            writeStatus(out, 416, "Range not satisfiable")
            return
        }
        val length = end - start + 1
        val partial = range != null
        val head = buildString {
            append(if (partial) "HTTP/1.1 206 Partial Content\r\n" else "HTTP/1.1 200 OK\r\n")
            append("Content-Type: video/mp4\r\n")
            append("Accept-Ranges: bytes\r\n")
            append("Content-Length: $length\r\n")
            if (partial) append("Content-Range: bytes $start-$end/$size\r\n")
            append("Connection: close\r\n\r\n")
        }
        out.write(head.toByteArray())
        out.flush()

        val path = state.path.ifBlank {
            // TDLib names the file once it starts writing, so wait for that.
            val deadline = System.currentTimeMillis() + WAIT_MS
            var found: String? = null
            while (System.currentTimeMillis() < deadline && found == null) {
                found = TelegramTd.fileState(fileId)?.path?.takeIf { it.isNotBlank() }
                if (found == null) Thread.sleep(100)
            }
            found ?: return
        }

        RandomAccessFile(path, "r").use { reader ->
            reader.seek(start)
            var position = start
            val buffer = ByteArray(CHUNK)
            while (position <= end) {
                val ready = try {
                    TelegramTd.awaitReadable(fileId, position, WAIT_MS)
                } catch (e: Exception) {
                    Log.w("TelegramStream", "stopped at $position: ${e.message}")
                    return
                }
                val onDisk = (reader.length() - position).coerceAtLeast(0)
                val want = minOf(CHUNK.toLong(), end - position + 1, onDisk, ready)
                if (want <= 0) {
                    Thread.sleep(50)
                    continue
                }
                val read = reader.read(buffer, 0, want.toInt())
                if (read <= 0) return
                out.write(buffer, 0, read)
                out.flush()
                position += read
            }
        }
    }

    /** `bytes=0-`, `bytes=1000-2000`, or no header at all. */
    private fun parseRange(header: String?, size: Long): Pair<Long, Long> {
        if (header == null) return 0L to (size - 1)
        val spec = header.substringAfter("bytes=", "").substringBefore(',').trim()
        if (spec.isEmpty()) return 0L to (size - 1)
        val from = spec.substringBefore('-').trim().toLongOrNull() ?: 0L
        val to = spec.substringAfter('-', "").trim().toLongOrNull() ?: (size - 1)
        return from.coerceIn(0, size - 1) to to.coerceIn(from, size - 1)
    }

    private fun writeStatus(out: BufferedOutputStream, code: Int, message: String) {
        val body = message.toByteArray()
        val head = buildString {
            append("HTTP/1.1 $code ${if (code == 404) "Not Found" else "Error"}\r\n")
            append("Content-Type: text/plain; charset=utf-8\r\n")
            append("Content-Length: ${body.size}\r\n")
            append("Connection: close\r\n\r\n")
        }
        out.write(head.toByteArray())
        out.write(body)
    }
}
