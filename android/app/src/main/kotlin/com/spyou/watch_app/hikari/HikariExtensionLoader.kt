package com.spyou.watch_app.hikari

import android.content.Context
import com.hikari.ext.HikariProvider
import dalvik.system.DexClassLoader
import org.json.JSONObject
import java.io.File
import java.util.zip.ZipFile

/**
 * A `.hiki` package as described by its own `manifest.json`.
 *
 * @param name       display name from the manifest.
 * @param version    manifest version integer.
 * @param mainClass  fully-qualified class implementing [HikariProvider].
 */
data class HikariManifest(
    val name: String,
    val version: Int,
    val mainClass: String,
)

/** A loaded `.hiki` extension: its manifest plus the live provider instance. */
data class HikariLoadedExtension(
    val manifest: HikariManifest,
    val provider: HikariProvider,
)

/**
 * Loads `.hiki` extensions.
 *
 * A `.hiki` is **not** an APK: it is a plain zip holding `classes.dex`,
 * `manifest.json` and a `META-INF/` stub (verified against
 * `releases/download/continuous/51cg.hiki`, 19 KB). That shape drives every
 * decision below:
 *
 *  - There is no `AndroidManifest.xml`, so `PackageManager.getPackageArchiveInfo`
 *    cannot read it — the manifest is parsed straight out of the zip as JSON.
 *  - `DexClassLoader` takes a *dex or jar* path, not a zip, so `classes.dex` is
 *    extracted to its own file first. Handing it the `.hiki` directly yields
 *    "not a valid zip archive"/`NoClassDefFoundError` rather than anything
 *    diagnostic.
 *  - The parent classloader must be ours, because that is what supplies
 *    `com.hikari.ext.*` (vendored in this module) and Kotlin/coroutines. That
 *    parent-first order is also what makes our [com.hikari.ext.HikariNet]
 *    implementation win over any copy an extension might bundle.
 */
object HikariExtensionLoader {

    /** The provider contract an extension class must implement. */
    private const val PROVIDER_INTERFACE = "com.hikari.ext.HikariProvider"

    /** Parses `manifest.json` out of a `.hiki` archive. */
    fun readManifest(hiki: File): Result<HikariManifest> = runCatching {
        ZipFile(hiki).use { zip ->
            val entry = zip.getEntry("manifest.json")
                ?: error("Not a .hiki extension (missing manifest.json): ${hiki.name}")
            val json = zip.getInputStream(entry).bufferedReader().use { it.readText() }
            parseManifest(json, hiki.name)
        }
    }

    /**
     * Parses the manifest text. Split out from [readManifest] so it is testable
     * without a zip on disk.
     */
    fun parseManifest(json: String, sourceName: String = "manifest.json"): HikariManifest {
        val obj = JSONObject(json)
        val mainClass = obj.optString("mainClass").trim()
        require(mainClass.isNotEmpty()) {
            "Manifest has no mainClass ($sourceName)"
        }
        return HikariManifest(
            name = obj.optString("name").ifBlank { mainClass.substringAfterLast('.') },
            version = obj.optInt("version", 1),
            mainClass = mainClass,
        )
    }

    /**
     * Loads [hiki], instantiating its `mainClass`.
     *
     * Never throws — every failure is a [Result.failure] carrying a message that
     * names the file, because a bad third-party extension must not take the app
     * down and must be reportable from the Sources screen.
     */
    fun load(context: Context, hiki: File): Result<HikariLoadedExtension> = runCatching {
        val manifest = readManifest(hiki).getOrThrow()

        // Extracted dex lives beside the optimised output, keyed by file name so
        // two extensions can never overwrite each other's dex.
        val workDir = File(context.codeCacheDir, "hikari").apply { mkdirs() }
        val dexFile = File(workDir, "${hiki.nameWithoutExtension}.dex")
        extractDex(hiki, dexFile)

        // Android refuses to load a writable dex ("Writable dex file is not
        // allowed"); app-private storage is writable by default.
        dexFile.setReadOnly()

        val optimizedDir = File(workDir, "odex").apply { mkdirs() }
        val loader = DexClassLoader(
            dexFile.absolutePath,
            optimizedDir.absolutePath,
            null,
            context.classLoader,
        )

        val clazz = loader.loadClass(manifest.mainClass)
        val iface = loader.loadClass(PROVIDER_INTERFACE)
        require(iface.isAssignableFrom(clazz)) {
            "${manifest.mainClass} does not implement $PROVIDER_INTERFACE"
        }

        val instance = clazz.getDeclaredConstructor().newInstance()
        val provider = instance as? HikariProvider
            ?: error("${manifest.mainClass} is not a HikariProvider")

        HikariLoadedExtension(manifest, provider)
    }

    /** Copies `classes.dex` out of the archive to [dest]. */
    private fun extractDex(hiki: File, dest: File) {
        ZipFile(hiki).use { zip ->
            val entry = zip.getEntry("classes.dex")
                ?: error("Not a .hiki extension (missing classes.dex): ${hiki.name}")
            zip.getInputStream(entry).use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            }
        }
    }
}
