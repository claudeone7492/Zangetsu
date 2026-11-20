package com.spyou.watch_app.hikari

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Tests for the parts of [HikariExtensionLoader] that decide whether a `.hiki`
 * is even loadable.
 *
 * The archives here are built by hand rather than checked in: the format is
 * just a zip with `classes.dex` + `manifest.json`, and generating it keeps the
 * test honest about which entry is required. [HikariExtensionLoader.load] itself
 * is not covered — it needs a real `DexClassLoader` and a dexed provider, so it
 * is exercised by installing an extension on a device.
 */
class HikariExtensionLoaderTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private fun hiki(name: String, entries: Map<String, ByteArray>): File {
        val file = File(tmp.root, name)
        ZipOutputStream(file.outputStream()).use { zip ->
            entries.forEach { (path, bytes) ->
                zip.putNextEntry(ZipEntry(path))
                zip.write(bytes)
                zip.closeEntry()
            }
        }
        return file
    }

    private fun manifestJson(name: String, version: Int, mainClass: String) =
        """{"name":"$name","version":$version,"mainClass":"$mainClass"}"""

    private fun manifest(name: String, version: Int, mainClass: String) =
        manifestJson(name, version, mainClass).toByteArray()

    // ---------------------------------------------------------------------
    // parseManifest
    // ---------------------------------------------------------------------

    @Test
    fun `parses a well formed manifest`() {
        val m = HikariExtensionLoader.parseManifest(
            manifestJson("51CG", 3, "com.example.Provider"),
        )
        assertEquals("51CG", m.name)
        assertEquals(3, m.version)
        assertEquals("com.example.Provider", m.mainClass)
    }

    @Test
    fun `falls back to the simple class name when name is missing`() {
        val m = HikariExtensionLoader.parseManifest(
            """{"version":1,"mainClass":"com.example.SomeProvider"}""",
        )
        assertEquals("SomeProvider", m.name)
    }

    @Test
    fun `defaults the version to 1 when absent`() {
        val m = HikariExtensionLoader.parseManifest(
            """{"mainClass":"com.example.P"}""",
        )
        assertEquals(1, m.version)
    }

    @Test
    fun `rejects a manifest with no mainClass`() {
        val error = runCatching {
            HikariExtensionLoader.parseManifest("""{"name":"X"}""")
        }.exceptionOrNull()
        assertTrue(
            "expected a mainClass complaint, got $error",
            error is IllegalArgumentException && error.message!!.contains("mainClass"),
        )
    }

    @Test
    fun `rejects a manifest whose mainClass is only whitespace`() {
        val error = runCatching {
            HikariExtensionLoader.parseManifest("""{"mainClass":"   "}""")
        }.exceptionOrNull()
        assertTrue(error is IllegalArgumentException)
    }

    @Test
    fun `rejects malformed json`() {
        assertTrue(
            runCatching { HikariExtensionLoader.parseManifest("{not json") }
                .exceptionOrNull() != null,
        )
    }

    // ---------------------------------------------------------------------
    // readManifest
    // ---------------------------------------------------------------------

    @Test
    fun `reads the manifest out of a real archive`() {
        val file = hiki(
            "a.hiki",
            mapOf(
                "manifest.json" to manifest("Alpha", 2, "com.a.P"),
                "classes.dex" to byteArrayOf(0x64, 0x65, 0x78),
            ),
        )
        val m = HikariExtensionLoader.readManifest(file).getOrThrow()
        assertEquals("Alpha", m.name)
        assertEquals(2, m.version)
        assertEquals("com.a.P", m.mainClass)
    }

    @Test
    fun `an archive without a manifest fails with a message naming the file`() {
        val file = hiki("no-manifest.hiki", mapOf("classes.dex" to byteArrayOf(0)))
        val error = HikariExtensionLoader.readManifest(file).exceptionOrNull()
        assertTrue(
            "expected the file name in the message, got $error",
            error?.message?.contains("no-manifest.hiki") == true,
        )
    }

    @Test
    fun `a non-zip file fails rather than throwing`() {
        val file = File(tmp.root, "bogus.hiki")
        file.writeText("this is not a zip")
        assertTrue(HikariExtensionLoader.readManifest(file).isFailure)
    }
}
