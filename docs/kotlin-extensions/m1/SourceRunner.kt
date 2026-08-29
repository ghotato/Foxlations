package foxtensions.runner

import android.content.Context
import android.os.Looper
import androidx.preference.EditTextPreference
import androidx.preference.ListPreference
import androidx.preference.MultiSelectListPreference
import androidx.preference.Preference
import androidx.preference.PreferenceScreen
import androidx.preference.TwoStatePreference
import eu.kanade.tachiyomi.App
import eu.kanade.tachiyomi.createAppModule
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.AnimeSourceFactory
import eu.kanade.tachiyomi.animesource.model.AnimesPage
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.Source
import eu.kanade.tachiyomi.source.SourceFactory
import eu.kanade.tachiyomi.source.model.MangasPage
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.online.HttpSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Response
import org.koin.core.context.startKoin
import org.koin.core.context.stopKoin
import suwayomi.tachidesk.manga.impl.util.PackageTools
import suwayomi.tachidesk.server.ServerConfig
import suwayomi.tachidesk.server.serverConfig
import suwayomi.tachidesk.server.util.ConfigTypeRegistration
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get
import xyz.nulldev.androidcompat.AndroidCompat
import xyz.nulldev.androidcompat.AndroidCompatInitializer
import xyz.nulldev.androidcompat.androidCompatModule
import xyz.nulldev.ts.config.GlobalConfigManager
import xyz.nulldev.ts.config.configManagerModule
import java.io.File
import java.net.URLClassLoader
import java.util.Locale
import java.util.zip.ZipFile

/**
 * The minimal Suwayomi host + the source-call surface Foxlations' KotlinExtensionService
 * drives over the `foxlations/jvm` MethodChannel. `bootstrap` stands up the DB-free host
 * (Injekt==Koin in this build); `run` is the M4a self-test; `invoke` is the M5.2 JSON RPC:
 * a request {method, jar, lang?, page?, query?, url?} in, a JSON response out that maps to
 * the app's MPages / MManga / PageUrl models.
 */
object SourceRunner {
    @Volatile private var booted = false
    // Holds either a manga CatalogueSource or an anime AnimeCatalogueSource.
    private val sourceCache = HashMap<String, Any>()
    // Documents dir; where the persisted memo cache lives (survives app restarts).
    @Volatile private var rootDirPath: String? = null
    // The AndroidCompat Application — used as a Context for source-preference extraction.
    @Volatile private var appContext: Context? = null

    @Synchronized
    private fun bootstrap(rootDir: String) {
        if (booted) return
        // ConfigManager.loadConfigs() reads server-reference.conf via the THREAD CONTEXT
        // classloader; point it at our loader (which holds the Suwayomi jar) or the
        // `server` config section is invisible and ServerConfig init throws.
        Thread.currentThread().contextClassLoader = SourceRunner::class.java.classLoader
        System.setProperty("suwayomi.tachidesk.config.server.rootDir", rootDir)
        val tmp = File(rootDir, "tmp").apply { mkdirs() }
        System.setProperty("java.io.tmpdir", tmp.absolutePath)
        Locale.setDefault(Locale.ENGLISH)
        rootDirPath = rootDir
        loadMemo(rootDir)

        ConfigTypeRegistration.registerCustomTypes()
        GlobalConfigManager.registerModule(ServerConfig.register { GlobalConfigManager.config })

        val app = App()
        appContext = app
        try { stopKoin() } catch (_: Throwable) {}
        startKoin {
            modules(createAppModule(app), androidCompatModule(), configManagerModule())
        }
        AndroidCompatInitializer().init()
        AndroidCompat().startApp(app)
        ensureMainLooper()
        sanitizeNetwork(Injekt.get<NetworkHelper>())
        enableCloudflareSolver()
        booted = true
    }

    // ── Android main Looper ───────────────────────────────────────────────────────
    // AndroidCompat ships the real AOSP android.os.Looper but never calls
    // prepareMainLooper(), so Looper.getMainLooper() stays null. Extensions that build a
    // Handler(Looper.getMainLooper()) — or use RxAndroid's AndroidSchedulers.mainThread()
    // — in their constructor or request path then die with an NPE ("Cannot read field
    // mQueue because looper is null"). Most sources never touch it (which is why only ~14
    // of 1372 failed this way); stand up one real, looping main thread at boot so they do.
    private fun ensureMainLooper() {
        try {
            if (Looper.getMainLooper() != null) return
        } catch (_: Throwable) { /* not prepared yet → create one below */ }
        val ready = java.util.concurrent.CountDownLatch(1)
        Thread({
            try { Looper.prepareMainLooper() } catch (_: Throwable) {}
            ready.countDown()
            try { Looper.loop() } catch (_: Throwable) {}
        }, "foxtensions-main-looper").apply { isDaemon = true; start() }
        try { ready.await(5, java.util.concurrent.TimeUnit.SECONDS) } catch (_: Throwable) {}
    }

    // ── Cloudflare bypass wiring ──────────────────────────────────────────────────
    // Suwayomi's CloudflareInterceptor already abstracts CF-solving behind the
    // FlareSolverr `/v1` protocol (browser solves the challenge → returns
    // cf_clearance cookie + matching User-Agent → interceptor injects them into the
    // cookie jar and retries). It's off by default ("Cloudflare bypass currently
    // disabled"). We flip it on when a solver URL is provided. In the desktop harness
    // that solver is Playwright/Chromium; in the iOS app the SAME interceptor is fed
    // by a WKWebView-backed solver (a real WebKit engine on the device's residential
    // IP — strictly better than a datacenter Chromium). Gated by a system property so
    // production builds don't enable it implicitly.
    private fun enableCloudflareSolver() {
        val url = System.getProperty("foxlations.flareSolverrUrl")?.takeIf { it.isNotBlank() } ?: return
        try {
            serverConfig.flareSolverrEnabled.value = true
            serverConfig.flareSolverrUrl.value = url.removeSuffix("/")
            // If cookie reuse still fails (e.g. TLS-fingerprint-bound cf_clearance) but
            // the browser did fetch the page, fall back to the browser's HTML response.
            serverConfig.flareSolverrAsResponseFallback.value = true
        } catch (_: Throwable) {
        }
    }

    // ── zstd guard ───────────────────────────────────────────────────────────────
    // Some Keiyoushi sources (AsuraScans, via keiyoushi.source base) install an
    // OkHttp CompressionInterceptor(Gzip, Brotli, Zstd) on their own client, which
    // advertises `Accept-Encoding: …,zstd` and decompresses zstd responses through
    // the `com.squareup.zstd` JNI native. That native ships for windows/linux/mac
    // only; on the iOS Zero JVM `os.name` is "darwin", so its loader throws
    // `Unsupported OS: darwin (arch=aarch64)` the first time a zstd body comes back —
    // exactly what killed AsuraScans on device while MangaDex (no zstd) was fine.
    //
    // We can't recompile the prebuilt extension, so we neutralise it at the wire:
    // a network interceptor on Suwayomi's base client strips `zstd` from outgoing
    // Accept-Encoding. The server then falls back to gzip/br (both pure-JVM), the
    // extension's CompressionInterceptor never reaches the zstd branch, and the
    // native is never touched. Only engaged where the native can't load, so
    // desktop/Android keep real zstd.

    /** Mirrors zstd-kmp's own loader: it maps os.name to windows/linux/mac and
     *  throws for anything else. iOS ("darwin") is the anything-else — and so is
     *  Android, which reports os.name="Linux" but arch="aarch64", where the desktop
     *  zstd native isn't shipped: without this it would crash Android just like iOS.
     *  The desktop windows/linux natives are x86_64-only in practice; macOS ships
     *  both arches. Stripping when unsure is safe — the server just falls back to
     *  gzip/brotli (both pure-JVM), which only costs a little compression. */
    private fun zstdNativeAvailable(): Boolean {
        val os = System.getProperty("os.name")?.lowercase() ?: return false
        if (os.contains("mac")) return true
        val arch = System.getProperty("os.arch")?.lowercase() ?: ""
        val x64 = arch.contains("amd64") || arch.contains("x86_64") || arch.contains("x64")
        return (os.contains("windows") || os.contains("linux")) && x64
    }

    private val zstdStripper = object : Interceptor {
        override fun intercept(chain: Interceptor.Chain): Response {
            val req = chain.request()
            val ae = req.header("Accept-Encoding") ?: return chain.proceed(req)
            if (!ae.contains("zstd", ignoreCase = true)) return chain.proceed(req)
            val kept = ae.split(",")
                .map { it.trim() }
                .filter { it.isNotEmpty() && !it.startsWith("zstd", ignoreCase = true) }
            val value = if (kept.isEmpty()) "gzip" else kept.joinToString(", ")
            return chain.proceed(req.newBuilder().header("Accept-Encoding", value).build())
        }
    }

    private fun sanitizeNetwork(nh: NetworkHelper) {
        if (zstdNativeAvailable()) return
        for (name in arrayOf("client", "cloudflareClient")) {
            try {
                val getter = nh.javaClass.getMethod(
                    "get" + name.replaceFirstChar { it.uppercaseChar() })
                val base = getter.invoke(nh) as OkHttpClient
                if (base.networkInterceptors.any { it === zstdStripper }) continue
                val fixed = base.newBuilder().addNetworkInterceptor(zstdStripper).build()
                val f = nh.javaClass.getDeclaredField(name + "\$delegate")
                f.isAccessible = true
                f.set(nh, lazyOf<OkHttpClient>(fixed))
            } catch (_: Throwable) {
                // Best-effort: if NetworkHelper's shape changes, a zstd source would
                // still fail loudly rather than silently mis-decode a response.
            }
        }
    }

    // ── M4a self-test (unchanged) ────────────────────────────────────────────────
    @JvmStatic
    fun run(source: Any, rootDir: String): String {
        val out = StringBuilder()
        try { bootstrap(rootDir) } catch (t: Throwable) { return "  BOOTSTRAP FAILED: " + rootMsg(t) }
        out.append(netDiag()).append('\n')
        try {
            val cat: CatalogueSource = when (source) {
                is CatalogueSource -> source
                is SourceFactory -> source.createSources()
                    .filterIsInstance<CatalogueSource>().firstOrNull()
                    ?: return out.append("  no CatalogueSource in factory").toString()
                else -> return out.append("  not a CatalogueSource: ${source.javaClass.name}").toString()
            }
            val page = runBlocking(Dispatchers.Default) { cat.getPopularManga(1) }
            val titles = page.mangas.take(5).joinToString("\n") { "   - " + it.title }
            out.append("  FETCH OK: ${page.mangas.size} manga (hasNext=${page.hasNextPage})\n$titles")
        } catch (t: Throwable) {
            var r: Throwable = t
            while (r.cause != null && r.cause !== r) r = r.cause!!
            val at = r.stackTrace.take(3)
                .joinToString(" | ") { it.className.substringAfterLast('.') + "." + it.methodName + ":" + it.lineNumber }
            out.append("  FETCH FAILED: ${t.javaClass.simpleName}: ${t.message}\n")
                .append("    root: ${r.javaClass.name}: ${r.message}\n    at: $at")
        }
        return out.toString()
    }

    private fun rootMsg(t: Throwable): String {
        var r = t; while (r.cause != null && r.cause !== r) r = r.cause!!
        return "${r.javaClass.name}: ${r.message}"
    }

    private fun netDiag(): String {
        val sb = StringBuilder("  [net] v4stack=").append(System.getProperty("java.net.preferIPv4Stack"))
        try {
            val a = java.net.InetAddress.getAllByName("api.mangadex.org")
            sb.append(" dns=").append(a.joinToString(",") { it.hostAddress })
        } catch (t: Throwable) { sb.append(" dns=ERR:").append(t.javaClass.simpleName) }
        try {
            java.net.Socket().use { it.connect(java.net.InetSocketAddress("1.1.1.1", 443), 5000) }
            sb.append(" tcp(1.1.1.1:443)=OK")
        } catch (t: Throwable) { sb.append(" tcp(1.1.1.1:443)=").append(t.javaClass.simpleName) }
        return sb.toString()
    }

    // ── M5.2 JSON RPC ────────────────────────────────────────────────────────────
    @JvmStatic
    fun invoke(reqJson: String, rootDir: String): String {
        return try {
            bootstrap(rootDir)
            val req = Json.parseToJsonElement(reqJson).jsonObject
            val method = req.str("method", "")
            // Warm-up: the app boots the JVM in the background when Browse opens so the
            // first real source call doesn't pay the (one-time) bootstrap cost. bootstrap()
            // already ran above; just acknowledge.
            if (method == "warmup") return "{\"ok\":true}"
            // APK import: convert a user-added extension APK (Aniyomi anime, or any dex-only
            // extension) to a loadable jar and read its entry class from the (binary)
            // manifest — no source is loaded here. Keiyoushi manga/novel already ship jars,
            // so this is mainly the anime path. The app calls it once at import time.
            if (method == "convertApk") return convertApkJson(req)
            val lang = req["lang"]?.jsonPrimitive?.contentOrNull
            val src = loadSource(resolveJar(req.str("jar", "")), lang, req.str("entry", ""))
            // Source preferences (ConfigurableSource) — same JSON contract as Android.
            when (method) {
                "getPreferences" -> return preferencesJson(src)
                "setPreference" -> return setPreference(src, req.str("key", ""), req["value"])
            }
            // Anime extensions (AnimeHttpSource) and manga extensions (HttpSource) share the
            // same JSON method names — the app's ExtensionService is one contract. Route by
            // the loaded source's type. getVideoList is the anime-only extra (episodes are
            // carried as "chapters" in the shared detail shape, so getDetail is unified).
            when (src) {
                is AnimeCatalogueSource -> animeInvoke(method, src, req)
                is CatalogueSource -> mangaInvoke(method, src, req)
                else -> errJson("unsupported source type: ${src.javaClass.name}")
            }
        } catch (t: Throwable) {
            errJson(describe(t))
        }
    }

    private fun mangaInvoke(method: String, cat: CatalogueSource, req: JsonObject): String = when (method) {
        "getPopular" -> mangasPageJson(runBlocking(Dispatchers.Default) { cat.getPopularManga(req.int("page", 1)) })
        "getLatestUpdates" -> mangasPageJson(runBlocking(Dispatchers.Default) { cat.getLatestUpdates(req.int("page", 1)) })
        "search" -> mangasPageJson(runBlocking(Dispatchers.Default) {
            cat.getSearchManga(req.int("page", 1), req.str("query", ""), cat.getFilterList())
        })
        "getDetail" -> detailJson(cat, req.str("url", ""))
        "getPageList" -> pageListJson(cat, req.str("url", ""))
        "getHtmlContent" -> htmlContentJson(cat, req.str("url", ""))
        else -> errJson("unknown method: $method")
    }

    private fun animeInvoke(method: String, cat: AnimeCatalogueSource, req: JsonObject): String = when (method) {
        "getPopular" -> animesPageJson(runBlocking(Dispatchers.Default) { cat.getPopularAnime(req.int("page", 1)) })
        "getLatestUpdates" -> animesPageJson(runBlocking(Dispatchers.Default) { cat.getLatestUpdates(req.int("page", 1)) })
        "search" -> animesPageJson(runBlocking(Dispatchers.Default) {
            cat.getSearchAnime(req.int("page", 1), req.str("query", ""), cat.getFilterList())
        })
        "getDetail" -> animeDetailJson(cat, req.str("url", ""))
        "getVideoList" -> videoListJson(cat, req.str("url", ""))
        else -> errJson("unknown anime method: $method")
    }

    // Convert a downloaded extension APK to a loadable jar (Suwayomi's own dex→jar, no
    // extra deps) and read its manifest metadata. Handles anime/manga/novel entry keys,
    // `.class` (single source) or `.factory` (SourceFactory), and resolves a relative
    // ".Foo" entry against the package name. The app persists {jar, entry, kind} and builds
    // the matching KotlinExtensionService.
    private fun convertApkJson(req: JsonObject): String {
        val apk = req.str("apk", "")
        val outJar = req.str("out", "")
        val info = PackageTools.getPackageInfo(java.io.File(apk).toPath())
        val meta = info.applicationInfo?.metaData
        val pkg = info.packageName ?: ""
        val entryKeys = listOf(
            "tachiyomi.animeextension.class" to "anime",
            "tachiyomi.animeextension.factory" to "anime",
            "tachiyomi.extension.class" to "manga",
            "tachiyomi.extension.factory" to "manga",
            "tachiyomi.novelextension.class" to "novel",
            "tachiyomi.novelextension.factory" to "novel",
        )
        var entry: String? = null
        var kind = "manga"
        var isFactory = false
        for ((k, kd) in entryKeys) {
            val v = meta?.getString(k) ?: continue
            entry = if (v.startsWith(".")) pkg + v else v
            kind = kd
            isFactory = k.endsWith(".factory")
            break
        }
        if (outJar.isNotBlank()) PackageTools.dex2jar(java.io.File(apk).toPath(), java.io.File(outJar).toPath())
        return buildJsonObject {
            put("ok", true)
            put("jar", outJar)
            put("package", pkg)
            put("entry", entry)
            put("kind", kind)
            put("isFactory", isFactory)
            put("versionName", info.versionName)
            put("name", meta?.getString("tachiyomi.extension.name"))
            put("nsfw", meta?.getInt("tachiyomi.extension.nsfw", 0) ?: 0)
        }.toString()
    }

    private fun resolveJar(jar: String): String {
        val f = File(jar)
        if (f.isAbsolute && f.exists()) return jar
        val base = System.getProperty("foxlations.jarsDir") ?: "."
        return File(base, jar).absolutePath
    }

    private fun loadSource(jarPath: String, lang: String?, entry: String): Any {
        val key = "$jarPath|$lang"
        sourceCache[key]?.let { return it }
        val ej = File(jarPath)
        // Manga/novel jars ship a plaintext AndroidManifest we can read the entry class from;
        // anime jars come from dex2jar (which drops the manifest), so the app decodes the
        // binary manifest and passes `entry` explicitly. Fall back to the manifest scan.
        val entryClass = entry.ifBlank { findEntryClass(ej) ?: error("no entry class in $jarPath") }
        val cl = URLClassLoader(arrayOf(ej.toURI().toURL()), SourceRunner::class.java.classLoader)
        val obj = Class.forName(entryClass, true, cl).getDeclaredConstructor().newInstance()
        val src: Any = when (obj) {
            is SourceFactory -> {
                val subs = obj.createSources().filterIsInstance<CatalogueSource>()
                (lang?.let { l -> subs.firstOrNull { it.lang == l } } ?: subs.firstOrNull())
                    ?: error("factory has no CatalogueSource")
            }
            is AnimeSourceFactory -> {
                val subs = obj.createSources().filterIsInstance<AnimeCatalogueSource>()
                (lang?.let { l -> subs.firstOrNull { it.lang == l } } ?: subs.firstOrNull())
                    ?: error("factory has no AnimeCatalogueSource")
            }
            is CatalogueSource -> obj
            is AnimeCatalogueSource -> obj
            else -> error("not a (Anime)CatalogueSource: ${obj.javaClass.name}")
        }
        sourceCache[key] = src
        return src
    }

    // Entry keys across formats: 1.6 manga (extension), Tsundoku novels (novelextension),
    // Aniyomi (animeextension); each has a .class (single Source) or .factory (SourceFactory).
    private val entryKeys = listOf(
        "tachiyomi.extension.class", "tachiyomi.extension.factory",
        "tachiyomi.novelextension.class", "tachiyomi.novelextension.factory",
        "tachiyomi.animeextension.class", "tachiyomi.animeextension.factory",
    )

    private fun findEntryClass(jar: File): String? {
        ZipFile(jar).use { zf ->
            // Preferred: the entry class named in the (plaintext) AndroidManifest.xml.
            // 1.4/novel/anime jars carry no KSP `ExtensionGenerated`; 1.6 jars point the
            // same meta-data at their generated class, so this path covers both.
            zf.getEntry("AndroidManifest.xml")?.let { m ->
                val xml = zf.getInputStream(m).readBytes().toString(Charsets.UTF_8)
                for (key in entryKeys) {
                    val v = manifestValue(xml, key) ?: continue
                    if (!v.startsWith(".")) return v // already fully-qualified
                    // Relative name → resolve to a real class file by its tail path
                    // (avoids depending on the manifest `package` attribute).
                    val tail = "/" + v.drop(1).replace('.', '/') + ".class"
                    val hit = zipEntryEndingWith(zf, tail)
                    if (hit != null) return hit.dropLast(6).replace('/', '.')
                }
            }
            // Fallback: 1.6 KSP-generated entry class by name.
            val e = zf.entries()
            while (e.hasMoreElements()) {
                val n = e.nextElement().name
                if (n.endsWith("ExtensionGenerated.class")) return n.dropLast(6).replace('/', '.')
            }
        }
        return null
    }

    private fun manifestValue(xml: String, key: String): String? {
        val k = Regex.escape(key)
        return Regex("android:name\\s*=\\s*\"$k\"\\s+android:value\\s*=\\s*\"([^\"]+)\"")
            .find(xml)?.groupValues?.get(1)
            ?: Regex("android:value\\s*=\\s*\"([^\"]+)\"\\s+android:name\\s*=\\s*\"$k\"")
                .find(xml)?.groupValues?.get(1)
    }

    private fun zipEntryEndingWith(zf: ZipFile, tail: String): String? {
        val e = zf.entries()
        while (e.hasMoreElements()) {
            val n = e.nextElement().name
            if (n.endsWith(tail) || n == tail.removePrefix("/")) return n
        }
        return null
    }

    // ── serialization to the app's models ────────────────────────────────────────

    // Tachiyomi SManga.status -> app MangaStatus index (see m_manga.dart).
    private fun mapStatus(t: Int): Int = when (t) {
        SManga.ONGOING -> 0
        SManga.COMPLETED -> 1
        SManga.ON_HIATUS -> 2
        SManga.CANCELLED -> 3
        SManga.PUBLISHING_FINISHED -> 4
        else -> 5 // UNKNOWN / LICENSED
    }

    // API-1.6 sources stash per-item ids/tokens in SManga.memo / SChapter.memo (e.g. the
    // Iken framework reads chapter.memo["id"] in getPageList and throws "Refresh Chapter List"
    // without it). The app round-trips only the url, so cache memo here (populated during
    // browse/detail) and restore it before getPageList / getHtmlContent. Cleared when the JVM
    // process restarts — the source's own "Refresh Chapter List" message then tells the user to
    // reopen/refresh the chapter list, which repopulates the cache.
    private val mangaMemoCache = java.util.concurrent.ConcurrentHashMap<String, JsonObject>()
    private val chapterMemoCache = java.util.concurrent.ConcurrentHashMap<String, JsonObject>()

    // memo may be a lateinit/uninitialized field on the host impl; never let a read throw.
    private fun SManga.memoOrNull(): JsonObject? = runCatching { this.memo }.getOrNull()
    private fun SChapter.memoOrNull(): JsonObject? = runCatching { this.memo }.getOrNull()

    // The in-memory memo cache is lost when the JVM restarts, and the app shows a library
    // manga's chapters from its OWN cache without re-running getDetail — so a chapter read
    // could reach getPageList with no memo and the source throws "Refresh Chapter List".
    // Persist the cache to disk so it survives, and reload it at boot.
    private fun loadMemo(root: String) {
        try {
            val f = File(root, "foxlations_memo.json")
            if (!f.exists()) return
            val obj = Json.parseToJsonElement(f.readText()).jsonObject
            (obj["chapters"] as? JsonObject)?.forEach { (k, v) -> (v as? JsonObject)?.let { chapterMemoCache[k] = it } }
            (obj["mangas"] as? JsonObject)?.forEach { (k, v) -> (v as? JsonObject)?.let { mangaMemoCache[k] = it } }
        } catch (_: Throwable) {}
    }

    private fun persistMemo() {
        val root = rootDirPath ?: return
        try {
            val obj = buildJsonObject {
                put("chapters", buildJsonObject { chapterMemoCache.forEach { (k, v) -> put(k, v) } })
                put("mangas", buildJsonObject { mangaMemoCache.forEach { (k, v) -> put(k, v) } })
            }
            val tmp = File(root, "foxlations_memo.json.tmp")
            tmp.writeText(obj.toString())
            tmp.renameTo(File(root, "foxlations_memo.json"))
        } catch (_: Throwable) {}
    }

    private fun mangaJson(m: SManga, link: String? = null): JsonObject = buildJsonObject {
        put("name", m.title)
        put("link", link ?: m.url)
        put("imageUrl", m.thumbnail_url)
        put("description", m.description)
        put("author", m.author)
        put("artist", m.artist)
        put("status", mapStatus(m.status))
        put("genre", buildJsonArray {
            m.genre?.split(",")?.forEach { g -> if (g.isNotBlank()) add(kotlinx.serialization.json.JsonPrimitive(g.trim())) }
        })
    }

    private fun mangasPageJson(p: MangasPage): String = buildJsonObject {
        put("list", buildJsonArray {
            p.mangas.forEach { m ->
                // Remember any memo the source attached at browse time (some read it back in
                // mangaDetailsRequest); keyed by the url the app will send to getDetail.
                m.memoOrNull()?.let { runCatching { mangaMemoCache[m.url] = it } }
                add(mangaJson(m))
            }
        })
        put("hasNextPage", p.hasNextPage)
    }.toString()

    private fun chapterJson(c: SChapter): JsonObject = buildJsonObject {
        put("name", c.name)
        put("url", c.url)
        put("dateUpload", c.date_upload.toString())
        put("scanlator", c.scanlator)
        c.memoOrNull()?.let { put("memo", it) }
    }

    // The app can hand back an ABSOLUTE url: some sources emit SManga/SAnime.url with the
    // domain, and the app also keeps the url absolute so "Open in browser" loads it directly.
    // Tachiyomi's contract is a DOMAIN-RELATIVE url, and the default detail/page/episode
    // requests rebuild it as `baseUrl + url` — so an absolute url double-joins into e.g.
    // "GET https://example.orghttps://example.org/…", whose host ("example.orghttps") won't
    // resolve. Strip the domain when the host matches the source's own baseUrl; leave a
    // relative path (the common case) or a different host untouched.
    private fun relativize(url: String, cat: Any): String {
        if (!url.startsWith("http://", ignoreCase = true) &&
            !url.startsWith("https://", ignoreCase = true)) return url
        val base = runCatching { cat.javaClass.getMethod("getBaseUrl").invoke(cat) as? String }
            .getOrNull()?.takeIf { it.isNotBlank() } ?: return url
        return runCatching {
            val u = java.net.URI(url)
            val b = java.net.URI(base)
            if (u.host == null || !u.host.equals(b.host, ignoreCase = true)) return url
            val path = u.rawPath ?: ""
            val q = if (u.rawQuery != null) "?" + u.rawQuery else ""
            val f = if (u.rawFragment != null) "#" + u.rawFragment else ""
            (path + q + f).ifBlank { url }
        }.getOrDefault(url)
    }

    private fun detailJson(cat: CatalogueSource, url: String): String {
        val stub = SManga.create().apply {
            // Request-building url must be domain-relative; the memo cache + returned link
            // keep the original (possibly absolute) url so the app's stored url is stable.
            this.url = relativize(url, cat)
            mangaMemoCache[url]?.let { this.memo = it }
        }
        // Details first, THEN chapters using the populated manga. The combined call runs
        // both concurrently, which can leave chapters empty for rate-limited/paginated
        // APIs like MangaDex; sequential + the full manga is more reliable.
        val details = runBlocking(Dispatchers.Default) { cat.getMangaUpdate(stub, emptyList(), true, false) }.manga
        // SManga.url is a Tachiyomi `lateinit var`; a source whose mangaDetailsParse leaves it
        // unset (common for older 1.4 novel sources) throws UninitializedPropertyAccessException
        // the moment we read it. Guard the read and fall back to the request url.
        if (runCatching { details.url }.getOrNull().isNullOrBlank()) details.url = url
        if (details.memoOrNull() == null) stub.memoOrNull()?.let { details.memo = it }
        var chapters: List<SChapter> = emptyList()
        var chErr: String? = null
        try {
            chapters = runBlocking(Dispatchers.Default) { cat.getMangaUpdate(details, emptyList(), false, true) }.chapters
        } catch (t: Throwable) {
            chErr = describe(t)
        }
        // Cache each chapter's memo (and this manga's) so getPageList / getHtmlContent can
        // restore it later — including across app restarts and the app's library chapter
        // cache, which shows chapters without re-running getDetail.
        var cachedAny = false
        details.memoOrNull()?.let { runCatching { mangaMemoCache[url] = it; cachedAny = true } }
        chapters.forEach { ch ->
            ch.memoOrNull()?.let { runCatching { chapterMemoCache[ch.url] = it; cachedAny = true } }
        }
        if (cachedAny) persistMemo()
        return buildJsonObject {
            mangaJson(details, link = url).forEach { (k, v) -> put(k, v) }
            put("chapters", buildJsonArray { chapters.forEach { add(chapterJson(it)) } })
            put("_detailUrl", details.url)
            if (chErr != null) put("_chaptersError", chErr)
        }.toString()
    }

    // Rebuild the SChapter the app is asking about, restoring the memo the source stashed at
    // detail time (Iken et al. key page fetches off chapter.memo["id"]).
    private fun chapterStub(chapterUrl: String, cat: Any): SChapter = SChapter.create().apply {
        this.url = relativize(chapterUrl, cat)
        chapterMemoCache[chapterUrl]?.let { this.memo = it }
    }

    private fun pageListJson(cat: CatalogueSource, chapterUrl: String): String {
        val pages = runBlocking(Dispatchers.Default) { cat.getPageList(chapterStub(chapterUrl, cat)) }
        val hdrs = imageHeaders(cat)
        return buildJsonArray {
            pages.forEach { p ->
                add(buildJsonObject {
                    put("url", p.imageUrl ?: p.url)
                    if (hdrs != null) put("headers", hdrs)
                })
            }
        }.toString()
    }

    // Light-novel chapter text. Novel extensions implement NovelSource.fetchPageText(Page) —
    // a suspend fun bundled ONLY in the extension jar — so it's called reflectively (no compile
    // dependency on NovelSource, and no risk of shadowing the extension's own copy). The text
    // arrives as HTML; the app's novel reader splits it into paragraphs.
    private fun htmlContentJson(cat: CatalogueSource, chapterUrl: String): String {
        // Novel sources parse page.url to locate the chapter (e.g. Novel Archive splits it
        // to rebuild its `/api/novels/{id}/chapters/{n}` URL), so fetchPageText expects a
        // Page built from the CHAPTER's own url — NOT the Page getPageList returns (whose
        // url is the full request URL, which those sources then mis-parse into a 404).
        // Try the chapter-url page first; fall back to getPageList's page (FreeWebNovel-
        // style). Never fall back to the raw url — showing the API URL as "text" is the bug.
        var text = fetchNovelText(cat, Page(0, chapterUrl, ""))
        if (text.isNullOrBlank()) {
            val page = runCatching {
                runBlocking(Dispatchers.Default) { cat.getPageList(chapterStub(chapterUrl, cat)) }
            }.getOrNull()?.firstOrNull()
            if (page != null) text = fetchNovelText(cat, page)
        }
        return buildJsonObject { put("content", text ?: "") }.toString()
    }

    // Per-image request headers (User-Agent, Referer …) so the app's image loader isn't 403'd
    // by CDNs that require them. Falls back to baseUrl as Referer when the source sets none.
    private fun imageHeaders(cat: CatalogueSource): JsonObject? {
        if (cat !is HttpSource) return null
        val h = runCatching { cat.headers }.getOrNull() ?: return null
        return runCatching {
            buildJsonObject {
                h.names().forEach { n -> h[n]?.let { put(n, it) } }
                if (h["Referer"] == null) {
                    runCatching { cat.baseUrl }.getOrNull()?.takeIf { it.isNotBlank() }?.let { put("Referer", it) }
                }
            }
        }.getOrNull()
    }

    // Drive the extension's suspend `fetchPageText(page, continuation)` from blocking code.
    private fun fetchNovelText(cat: CatalogueSource, page: Page): String? {
        val method = cat.javaClass.methods.firstOrNull {
            it.name == "fetchPageText" && it.parameterCount == 2
        } ?: return null
        return runCatching {
            runBlocking(Dispatchers.Default) {
                suspendCancellableCoroutine<String?> { cont ->
                    val k = object : kotlin.coroutines.Continuation<Any?> {
                        override val context get() = cont.context
                        override fun resumeWith(result: Result<Any?>) {
                            cont.resumeWith(result.map { it as? String })
                        }
                    }
                    val ret = method.invoke(cat, page, k)
                    if (ret != kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED) {
                        cont.resumeWith(Result.success(ret as? String))
                    }
                }
            }
        }.getOrNull()
    }

    // ── Anime serialization (mirrors the manga shape; episodes ride as "chapters") ──

    private fun animeJson(a: SAnime, link: String? = null): JsonObject = buildJsonObject {
        put("name", a.title)
        put("link", link ?: a.url)
        put("imageUrl", a.thumbnail_url)
        put("description", a.description)
        put("author", a.author)
        put("artist", a.artist)
        put("status", mapAnimeStatus(a.status))
        put("genre", buildJsonArray {
            a.genre?.split(",")?.forEach { g -> if (g.isNotBlank()) add(kotlinx.serialization.json.JsonPrimitive(g.trim())) }
        })
    }

    // SAnime's status constants match SManga's (UNKNOWN=0, ONGOING=1, …).
    private fun mapAnimeStatus(t: Int): Int = when (t) {
        SAnime.ONGOING -> 0
        SAnime.COMPLETED -> 1
        SAnime.ON_HIATUS -> 2
        SAnime.CANCELLED -> 3
        SAnime.PUBLISHING_FINISHED -> 4
        else -> 5
    }

    private fun animesPageJson(p: AnimesPage): String = buildJsonObject {
        put("list", buildJsonArray { p.animes.forEach { add(animeJson(it)) } })
        put("hasNextPage", p.hasNextPage)
    }.toString()

    private fun episodeJson(e: SEpisode): JsonObject = buildJsonObject {
        put("name", e.name)
        put("url", e.url)
        put("dateUpload", e.date_upload.toString())
        put("scanlator", e.scanlator)
    }

    private fun animeDetailJson(cat: AnimeCatalogueSource, url: String): String {
        val stub = SAnime.create().apply { this.url = relativize(url, cat) }
        val details = runBlocking(Dispatchers.Default) { cat.getAnimeDetails(stub) }
        if (details.url.isBlank()) details.url = url
        var episodes: List<SEpisode> = emptyList()
        var chErr: String? = null
        try {
            episodes = runBlocking(Dispatchers.Default) { cat.getEpisodeList(details) }
        } catch (t: Throwable) {
            chErr = describe(t)
        }
        return buildJsonObject {
            animeJson(details, link = url).forEach { (k, v) -> put(k, v) }
            put("chapters", buildJsonArray { episodes.forEach { add(episodeJson(it)) } })
            put("_detailUrl", details.url)
            if (chErr != null) put("_chaptersError", chErr)
        }.toString()
    }

    private fun videoJson(v: Video): JsonObject = buildJsonObject {
        // App MVideo: url = playback stream, originalUrl = source url.
        put("url", v.videoUrl?.takeIf { it.isNotBlank() } ?: v.url)
        put("originalUrl", v.url)
        put("quality", v.quality)
        v.headers?.let { h ->
            put("headers", buildJsonObject { for (i in 0 until h.size) put(h.name(i), h.value(i)) })
        }
        put("subtitles", buildJsonArray {
            v.subtitleTracks.forEach { add(buildJsonObject { put("file", it.url); put("label", it.lang) }) }
        })
        put("audios", buildJsonArray {
            v.audioTracks.forEach { add(buildJsonObject { put("file", it.url); put("label", it.lang) }) }
        })
        // Intro/outro markers (Aniyomi Video.timestamps). Reflective so an older Suwayomi
        // Video without the field just yields an empty list rather than failing to compile.
        put("timestamps", buildJsonArray {
            val list = runCatching { v.javaClass.getMethod("getTimestamps").invoke(v) as? List<*> }
                .getOrNull() ?: emptyList<Any?>()
            list.forEach { ts ->
                if (ts == null) return@forEach
                fun d(g: String) = runCatching { ts.javaClass.getMethod(g).invoke(ts) as? Double }.getOrNull() ?: 0.0
                fun s(g: String) = runCatching { ts.javaClass.getMethod(g).invoke(ts)?.toString() }.getOrNull() ?: ""
                add(buildJsonObject {
                    put("start", d("getStart")); put("end", d("getEnd"))
                    put("name", s("getName")); put("type", s("getType"))
                })
            }
        })
    }

    private fun videoListJson(cat: AnimeCatalogueSource, episodeUrl: String): String {
        val ep = SEpisode.create().apply { this.url = relativize(episodeUrl, cat) }
        val videos = runBlocking(Dispatchers.Default) { cat.getVideoList(ep) }
        return buildJsonArray { videos.forEach { add(videoJson(it)) } }.toString()
    }

    // ── source preferences (ConfigurableSource.setupPreferenceScreen) ──────────────
    // Same JSON contract + behaviour as the Android host (ExtensionHost): build a
    // headless androidx PreferenceScreen against the source's own store, serialize each
    // preference, and on setPreference write "source_$id" then drop the cached source so
    // the new value is picked up whether the source reads prefs at construction or per call.

    private fun sourceId(src: Any): Long? =
        runCatching { src.javaClass.getMethod("getId").invoke(src) as? Long }.getOrNull()

    private fun preferencesJson(src: Any): String {
        val ctx = appContext ?: return "[]"
        val screen = buildPreferenceScreen(ctx, src) ?: return "[]"
        // Suwayomi's PreferenceScreen extends Preference (not PreferenceGroup) and exposes
        // the children as a plain list — iterate that rather than getPreference(i).
        return buildJsonArray {
            screen.preferences.forEach { prefJson(it)?.let { j -> add(j) } }
        }.toString()
    }

    private fun buildPreferenceScreen(context: Context, src: Any): PreferenceScreen? = runCatching {
        // Suwayomi ships a PreferenceScreen with a public (Context) constructor (real
        // androidx hides it behind PreferenceManager, which Suwayomi doesn't bundle).
        val screen = PreferenceScreen(context)
        val setup = src.javaClass.methods.firstOrNull {
            it.name == "setupPreferenceScreen" && it.parameterCount == 1
        } ?: return@runCatching null
        setup.invoke(src, screen)
        screen
    }.getOrNull()

    private fun prefJson(p: Preference): JsonObject? {
        val key = p.key ?: return null
        return when (p) {
            is MultiSelectListPreference -> buildJsonObject {
                put("key", key); put("type", "multi_select")
                put("title", p.title?.toString() ?: key)
                p.summary?.let { put("summary", it.toString()) }
                put("defaultValue", buildJsonArray { p.values.forEach { add(JsonPrimitive(it)) } })
                put("entries", entriesJson(p.entries, p.entryValues))
            }
            is ListPreference -> buildJsonObject {
                put("key", key); put("type", "list")
                put("title", p.title?.toString() ?: key)
                p.summary?.let { put("summary", it.toString()) }
                p.value?.let { put("defaultValue", it) }
                put("entries", entriesJson(p.entries, p.entryValues))
            }
            is EditTextPreference -> buildJsonObject {
                put("key", key); put("type", "edit_text")
                put("title", p.title?.toString() ?: key)
                p.summary?.let { put("summary", it.toString()) }
                p.text?.let { put("defaultValue", it) }
            }
            is TwoStatePreference -> buildJsonObject {
                put("key", key); put("type", "switch")
                put("title", p.title?.toString() ?: key)
                p.summary?.let { put("summary", it.toString()) }
                put("defaultValue", p.isChecked)
            }
            else -> null
        }
    }

    private fun entriesJson(entries: Array<CharSequence>?, values: Array<CharSequence>?): JsonArray =
        buildJsonArray {
            if (values == null) return@buildJsonArray
            for (i in values.indices) {
                add(buildJsonObject {
                    put("title", (entries?.getOrNull(i) ?: values[i]).toString())
                    put("value", values[i].toString())
                })
            }
        }

    private fun setPreference(src: Any, key: String, value: JsonElement?): String {
        if (key.isBlank() || value == null) return errJson("setPreference needs key and value")
        val ctx = appContext ?: return errJson("no app context")
        val id = sourceId(src) ?: return errJson("source has no id")
        val editor = ctx.getSharedPreferences("source_$id", Context.MODE_PRIVATE).edit()
        when (value) {
            is JsonArray -> editor.putStringSet(
                key, value.mapNotNull { (it as? JsonPrimitive)?.content }.toSet())
            is JsonPrimitive -> {
                val b = value.booleanOrNull
                if (b != null) editor.putBoolean(key, b) else editor.putString(key, value.content)
            }
            else -> editor.putString(key, value.toString())
        }
        editor.apply()
        // Drop the cached instance so the next call rebuilds with the new pref applied.
        sourceCache.entries.removeAll { it.value === src }
        return "{\"ok\":true}"
    }

    private fun errJson(msg: String): String = buildJsonObject { put("error", msg) }.toString()

    private fun describe(t: Throwable): String {
        var r: Throwable = t; while (r.cause != null && r.cause !== r) r = r.cause!!
        val frames = r.stackTrace.take(6).joinToString(" | ") {
            "${it.className}.${it.methodName}:${it.lineNumber}"
        }
        return "${t.javaClass.simpleName}: ${t.message} | root: ${r.javaClass.name}: ${r.message} | at $frames"
    }

    private fun JsonObject.int(k: String, d: Int) = this[k]?.jsonPrimitive?.intOrNull ?: d
    private fun JsonObject.str(k: String, d: String) = this[k]?.jsonPrimitive?.contentOrNull ?: d
}
