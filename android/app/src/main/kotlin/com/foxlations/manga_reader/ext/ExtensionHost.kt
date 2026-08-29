package com.foxlations.manga_reader.ext

import android.content.Context
import android.content.pm.PackageManager
import androidx.preference.EditTextPreference
import androidx.preference.ListPreference
import androidx.preference.MultiSelectListPreference
import androidx.preference.Preference
import androidx.preference.PreferenceManager
import androidx.preference.PreferenceScreen
import androidx.preference.TwoStatePreference
import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.AnimeSourceFactory
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.source.CatalogueSource
import eu.kanade.tachiyomi.source.SourceFactory
import eu.kanade.tachiyomi.source.model.Page
import eu.kanade.tachiyomi.source.model.SChapter
import eu.kanade.tachiyomi.source.model.SManga
import eu.kanade.tachiyomi.source.online.HttpSource
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
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.Headers
import java.io.File

/**
 * Android extension host — the Mihon-style ART loader. Loads Tachiyomi/Aniyomi/keiyoushi
 * extension APKs directly on the device runtime (ChildFirstPathClassLoader) and runs their
 * source methods, emitting the SAME JSON contract as the embedded-JVM SourceRunner so the
 * Dart side is platform-identical. No embedded JVM, no dex2jar — DexClassLoader loads dex.
 *
 * The eu.kanade.tachiyomi.* runtime is vendored by CI (from ApkBridge, Apache-2.0); Injekt +
 * NetworkHelper are stood up in [AndroidExtBootstrap].
 */
object ExtensionHost {
    private val sourceCache = HashMap<String, Any>()
    private val mangaMemoCache = java.util.concurrent.ConcurrentHashMap<String, JsonObject>()
    private val chapterMemoCache = java.util.concurrent.ConcurrentHashMap<String, JsonObject>()
    @Volatile private var memoDir: File? = null

    fun init(context: Context) {
        AndroidExtBootstrap.ensure(context)
        val dir = context.filesDir
        memoDir = dir
        runCatching {
            val f = File(dir, "foxlations_memo.json")
            if (f.exists()) {
                val obj = Json.parseToJsonElement(f.readText()).jsonObject
                (obj["chapters"] as? JsonObject)?.forEach { (k, v) -> (v as? JsonObject)?.let { chapterMemoCache[k] = it } }
                (obj["mangas"] as? JsonObject)?.forEach { (k, v) -> (v as? JsonObject)?.let { mangaMemoCache[k] = it } }
            }
        }
    }

    /** Same request/response contract as SourceRunner.invoke. */
    fun invoke(context: Context, request: String): String {
        return try {
            init(context)
            val req = Json.parseToJsonElement(request).jsonObject
            val method = req.str("method", "")
            if (method == "warmup") return "{\"ok\":true}"
            // Push the app's Cloudflare clearances (cookies + matching UA) into the
            // extension's OkHttp before any request — Android has no CF solver of its own.
            CloudflareCookies.apply(
                req.str("userAgent", "").ifBlank { null },
                req["cookies"] as? JsonObject,
            )
            val apk = req.str("jar", "").ifBlank { req.str("apk", "") }
            val lang = req["lang"]?.jsonPrimitive?.content
            val src = loadSource(context, apk, lang, req.str("entry", ""))
            // Source preferences apply to both manga and anime ConfigurableSources.
            when (method) {
                "getPreferences" -> return preferencesJson(context, src)
                "setPreference" -> return setPreference(context, apk, lang, src, req.str("key", ""), req["value"])
            }
            when (src) {
                is AnimeCatalogueSource -> animeInvoke(method, src, req)
                is CatalogueSource -> mangaInvoke(method, src, req)
                else -> err("unsupported source type: ${src.javaClass.name}")
            }
        } catch (t: Throwable) {
            err(describe(t))
        }
    }

    // ── loading ──────────────────────────────────────────────────────────────────

    private fun loadSource(context: Context, apkPath: String, lang: String?, entryOverride: String): Any {
        val key = "$apkPath|$lang"
        sourceCache[key]?.let { return it }
        val file = File(apkPath)
        require(file.exists()) { "extension apk not found: $apkPath" }
        // Android 14+ (API 34) throws SecurityException "Writable dex file … is not
        // allowed" when loading executable code (dex/APK) from a file the app can still
        // write to (a W^X rule). Extensions download into our writable files dir, so mark
        // the apk read-only before the classloader touches it. Deletion/updates still work
        // — that's governed by the parent directory's write bit, not the file's.
        runCatching { if (file.canWrite()) file.setReadOnly() }
        val pm = context.packageManager
        @Suppress("DEPRECATION")
        val info = pm.getPackageArchiveInfo(
            apkPath, PackageManager.GET_META_DATA or PackageManager.GET_CONFIGURATIONS,
        ) ?: error("cannot read apk metadata: $apkPath")
        val meta = info.applicationInfo?.metaData
        val entry = entryOverride.ifBlank {
            val keys = listOf(
                "tachiyomi.extension.class", "tachiyomi.animeextension.class",
                "tachiyomi.novelextension.class",
            )
            var e = keys.firstNotNullOfOrNull { meta?.getString(it) }
                ?: error("no entry class in apk manifest")
            e = e.split(";").first().trim()
            if (e.startsWith(".")) (info.packageName ?: "") + e else e
        }
        val parent = this::class.java.classLoader ?: ClassLoader.getSystemClassLoader()
        val loader = ChildFirstPathClassLoader(apkPath, file.parent, parent)
        val obj = Class.forName(entry, false, loader).getDeclaredConstructor().newInstance()
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

    // ── manga dispatch (classic suspend API) ───────────────────────────────────────

    private fun mangaInvoke(method: String, cat: CatalogueSource, req: JsonObject): String = when (method) {
        "getPopular" -> mangasPageJson(runBlocking { cat.getPopularManga(req.int("page", 1)) })
        "getLatestUpdates" -> mangasPageJson(runBlocking { cat.getLatestUpdates(req.int("page", 1)) })
        "search" -> mangasPageJson(runBlocking {
            cat.getSearchManga(req.int("page", 1), req.str("query", ""), cat.getFilterList())
        })
        "getDetail" -> detailJson(cat, req.str("url", ""))
        "getPageList" -> pageListJson(cat, req.str("url", ""))
        "getHtmlContent" -> htmlContentJson(cat, req.str("url", ""))
        else -> err("unknown method: $method")
    }

    // The app can hand back an ABSOLUTE url (some sources emit SManga/SAnime.url with the
    // domain, and the app keeps it absolute so "Open in browser" loads it directly). Tachiyomi's
    // contract is a DOMAIN-RELATIVE url, and the default detail/page/episode requests rebuild it
    // as `baseUrl + url` — so an absolute url double-joins into "https://example.orghttps://…",
    // whose host won't resolve. Strip the domain when the host matches the source's own baseUrl;
    // leave a relative path (the common case) or a different host untouched. (Mirrors SourceRunner.)
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
            this.url = relativize(url, cat)
            mangaMemoCache[url]?.let { setMemoRef(this, it) }
        }
        // keiyoushi 1.6 sources implement getMangaUpdate (details + chapters) and stub the classic
        // getMangaDetails/getChapterList (→ UnsupportedOperationException). Prefer it when the
        // source declares it; fall back to the classic API otherwise. Two sequential calls
        // (details, then chapters with the populated manga) mirror the JVM host — a combined
        // concurrent fetch can leave chapters empty on rate-limited/paginated sources.
        val useUpdate = hasMethod(cat, "getMangaUpdate")
        val details: SManga = if (useUpdate) {
            (mangaUpdate(cat, stub, true, false)?.let { reflectGet(it, "getManga") } as? SManga) ?: stub
        } else {
            runBlocking { cat.getMangaDetails(stub) }
        }
        if (runCatching { details.url }.getOrNull().isNullOrBlank()) details.url = url
        if (memoOf(details) == null) memoOf(stub)?.let { setMemoRef(details, it) }
        var chapters: List<SChapter> = emptyList()
        var chErr: String? = null
        try {
            chapters = if (useUpdate) {
                (mangaUpdate(cat, details, false, true)?.let { reflectGet(it, "getChapters") } as? List<*>)
                    ?.filterIsInstance<SChapter>() ?: emptyList()
            } else {
                runBlocking { cat.getChapterList(details) }
            }
        } catch (t: Throwable) {
            chErr = describe(t)
        }
        var cachedAny = false
        memoOf(details)?.let { runCatching { mangaMemoCache[url] = it; cachedAny = true } }
        chapters.forEach { ch -> memoOf(ch)?.let { runCatching { chapterMemoCache[ch.url] = it; cachedAny = true } } }
        if (cachedAny) persistMemo()
        return buildJsonObject {
            mangaJson(details, link = url).forEach { (k, v) -> put(k, v) }
            put("chapters", buildJsonArray { chapters.forEach { add(chapterJson(it)) } })
            put("_detailUrl", details.url)
            if (chErr != null) put("_chaptersError", chErr)
        }.toString()
    }

    private fun chapterStub(chapterUrl: String, cat: Any): SChapter = SChapter.create().apply {
        this.url = relativize(chapterUrl, cat)
        chapterMemoCache[chapterUrl]?.let { setMemoRef(this, it) }
    }

    private fun pageListJson(cat: CatalogueSource, chapterUrl: String): String {
        val pages = runBlocking { cat.getPageList(chapterStub(chapterUrl, cat)) }
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

    private fun htmlContentJson(cat: CatalogueSource, chapterUrl: String): String {
        var text = fetchNovelText(cat, Page(0, chapterUrl, ""))
        if (text.isNullOrBlank()) {
            val page = runCatching { runBlocking { cat.getPageList(chapterStub(chapterUrl, cat)) } }
                .getOrNull()?.firstOrNull()
            if (page != null) text = fetchNovelText(cat, page)
        }
        return buildJsonObject { put("content", text ?: "") }.toString()
    }

    // ── anime dispatch ─────────────────────────────────────────────────────────────

    private fun animeInvoke(method: String, cat: AnimeCatalogueSource, req: JsonObject): String = when (method) {
        "getPopular" -> animesPageJson(runBlocking { cat.getPopularAnime(req.int("page", 1)) })
        "getLatestUpdates" -> animesPageJson(runBlocking { cat.getLatestUpdates(req.int("page", 1)) })
        "search" -> animesPageJson(runBlocking {
            cat.getSearchAnime(req.int("page", 1), req.str("query", ""), cat.getFilterList())
        })
        "getDetail" -> animeDetailJson(cat, req.str("url", ""))
        "getVideoList" -> videoListJson(cat, req.str("url", ""))
        else -> err("unknown anime method: $method")
    }

    private fun animeDetailJson(cat: AnimeCatalogueSource, url: String): String {
        val stub = SAnime.create().apply { this.url = relativize(url, cat) }
        val details = runBlocking { cat.getAnimeDetails(stub) }
        if (runCatching { details.url }.getOrNull().isNullOrBlank()) details.url = url
        val episodes = runCatching { runBlocking { cat.getEpisodeList(stub) } }.getOrDefault(emptyList())
        return buildJsonObject {
            animeJson(details, link = url).forEach { (k, v) -> put(k, v) }
            put("chapters", buildJsonArray { episodes.forEach { add(episodeJson(it)) } })
            put("_detailUrl", details.url)
        }.toString()
    }

    private fun videoListJson(cat: AnimeCatalogueSource, episodeUrl: String): String {
        val ep = SEpisode.create().apply { this.url = relativize(episodeUrl, cat) }
        val videos = runBlocking { cat.getVideoList(ep) }
        return buildJsonArray {
            videos.forEach { v ->
                add(buildJsonObject {
                    val vUrl = reflectStr(v, "getVideoUrl")?.takeIf { it.isNotBlank() } ?: reflectStr(v, "getUrl") ?: ""
                    put("url", vUrl)
                    put("originalUrl", reflectStr(v, "getUrl") ?: vUrl)
                    // videoTitle is the 1.6 name; getQuality is its deprecated alias.
                    put("quality", reflectStr(v, "getVideoTitle")?.takeIf { it.isNotBlank() }
                        ?: reflectStr(v, "getQuality") ?: "")
                    videoHeaders(v)?.let { put("headers", it) }
                    put("subtitles", trackArray(v, "getSubtitleTracks"))
                    put("audios", trackArray(v, "getAudioTracks"))
                    put("timestamps", timestampsJson(v))
                })
            }
        }.toString()
    }

    /** Subtitle/audio Track list → [{file,label}] (Track.url/Track.lang), matching SourceRunner.
     *  Reflective so it tolerates extension-lib shape drift; empty when the getter is absent. */
    private fun trackArray(v: Any, getter: String): JsonArray = buildJsonArray {
        val list = runCatching { v.javaClass.getMethod(getter).invoke(v) as? List<*> }.getOrNull() ?: return@buildJsonArray
        list.forEach { t ->
            if (t != null) add(buildJsonObject {
                put("file", reflectStr(t, "getUrl") ?: "")
                put("label", reflectStr(t, "getLang") ?: "")
            })
        }
    }

    /** Source-provided intro/outro markers (Aniyomi Video.timestamps) → [{start,end,name,type}].
     *  Reflective + empty when absent — most sources don't set them. */
    private fun timestampsJson(v: Any): JsonArray = buildJsonArray {
        val list = runCatching { v.javaClass.getMethod("getTimestamps").invoke(v) as? List<*> }
            .getOrNull() ?: return@buildJsonArray
        list.forEach { ts ->
            if (ts != null) add(buildJsonObject {
                put("start", (reflectGet(ts, "getStart") as? Double) ?: 0.0)
                put("end", (reflectGet(ts, "getEnd") as? Double) ?: 0.0)
                put("name", reflectStr(ts, "getName") ?: "")
                put("type", reflectGet(ts, "getType")?.toString() ?: "")
            })
        }
    }

    /** Per-stream request headers (User-Agent/Referer/…) so the player isn't 403'd. */
    private fun videoHeaders(v: Any): JsonObject? {
        val h = runCatching { v.javaClass.getMethod("getHeaders").invoke(v) }.getOrNull() as? Headers ?: return null
        return runCatching {
            buildJsonObject { for (i in 0 until h.size) put(h.name(i), h.value(i)) }
        }.getOrNull()?.takeIf { it.isNotEmpty() }
    }

    // ── serialization (matches SourceRunner exactly) ───────────────────────────────

    private fun mangaJson(m: SManga, link: String? = null): JsonObject = buildJsonObject {
        put("name", m.title)
        put("link", link ?: m.url)
        put("imageUrl", m.thumbnail_url)
        put("description", m.description)
        put("author", m.author)
        put("artist", m.artist)
        put("status", m.status)
        put("genre", buildJsonArray {
            m.genre?.split(",")?.forEach { g -> if (g.isNotBlank()) add(kotlinx.serialization.json.JsonPrimitive(g.trim())) }
        })
    }

    private fun mangasPageJson(p: eu.kanade.tachiyomi.source.model.MangasPage): String = buildJsonObject {
        put("list", buildJsonArray {
            p.mangas.forEach { m ->
                memoOf(m)?.let { runCatching { mangaMemoCache[m.url] = it } }
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
        memoOf(c)?.let { put("memo", it) }
    }

    private fun animeJson(a: SAnime, link: String? = null): JsonObject = buildJsonObject {
        put("name", a.title)
        put("link", link ?: a.url)
        put("imageUrl", a.thumbnail_url)
        put("description", a.description)
        put("author", a.author)
        put("status", a.status)
        put("genre", buildJsonArray {
            a.genre?.split(",")?.forEach { g -> if (g.isNotBlank()) add(kotlinx.serialization.json.JsonPrimitive(g.trim())) }
        })
    }

    private fun animesPageJson(p: eu.kanade.tachiyomi.animesource.model.AnimesPage): String = buildJsonObject {
        put("list", buildJsonArray { p.animes.forEach { add(animeJson(it)) } })
        put("hasNextPage", p.hasNextPage)
    }.toString()

    private fun episodeJson(e: SEpisode): JsonObject = buildJsonObject {
        put("name", e.name)
        put("url", e.url)
        put("dateUpload", e.date_upload.toString())
        put("scanlator", e.scanlator)
    }

    // ── helpers ────────────────────────────────────────────────────────────────────

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

    /** Novel chapter text — NovelSource.fetchPageText(Page) via reflection (bundled in the apk). */
    private fun fetchNovelText(cat: Any, page: Page): String? {
        val method = cat.javaClass.methods.firstOrNull {
            it.name == "fetchPageText" && it.parameterCount == 2
        } ?: return null
        return runCatching {
            runBlocking {
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

    // memo is an API-1.6 field the vendored model may or may not carry; access reflectively.
    private fun memoOf(o: Any?): JsonObject? {
        if (o == null) return null
        return runCatching { o.javaClass.getMethod("getMemo").invoke(o) as? JsonObject }.getOrNull()
    }

    private fun setMemoRef(o: Any, memo: JsonObject) {
        runCatching { o.javaClass.getMethod("setMemo", JsonObject::class.java).invoke(o, memo) }
    }

    private fun reflectStr(o: Any, getter: String): String? =
        runCatching { o.javaClass.getMethod(getter).invoke(o) as? String }.getOrNull()

    private fun reflectGet(o: Any, getter: String): Any? =
        runCatching { o.javaClass.getMethod(getter).invoke(o) }.getOrNull()

    private fun hasMethod(o: Any, name: String): Boolean =
        o.javaClass.methods.any { it.name == name }

    /** extensions-lib 1.6 `getMangaUpdate(manga, chapters, fetchDetails, fetchChapters)` — a
     *  suspend fun returning SMangaUpdate (details + chapters). Invoked reflectively (Continuation
     *  bridge, like fetchNovelText); returns the SMangaUpdate, or null if the source doesn't have
     *  the 5-arg shape. Errors from the call itself propagate. */
    private fun mangaUpdate(cat: Any, manga: SManga, fetchDetails: Boolean, fetchChapters: Boolean): Any? {
        val m = cat.javaClass.methods.firstOrNull {
            it.name == "getMangaUpdate" && it.parameterCount == 5
        } ?: return null
        return runBlocking {
            suspendCancellableCoroutine<Any?> { cont ->
                val k = object : kotlin.coroutines.Continuation<Any?> {
                    override val context get() = cont.context
                    override fun resumeWith(result: Result<Any?>) { cont.resumeWith(result) }
                }
                val ret = m.invoke(cat, manga, emptyList<SChapter>(), fetchDetails, fetchChapters, k)
                if (ret != kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED) {
                    cont.resumeWith(Result.success(ret))
                }
            }
        }
    }

    private fun persistMemo() {
        val dir = memoDir ?: return
        runCatching {
            val obj = buildJsonObject {
                put("chapters", buildJsonObject { chapterMemoCache.forEach { (k, v) -> put(k, v) } })
                put("mangas", buildJsonObject { mangaMemoCache.forEach { (k, v) -> put(k, v) } })
            }
            val tmp = File(dir, "foxlations_memo.json.tmp")
            tmp.writeText(obj.toString())
            tmp.renameTo(File(dir, "foxlations_memo.json"))
        }
    }

    // ── source preferences (ConfigurableSource.setupPreferenceScreen) ──────────────
    // Mirrors ApkBridge's DalvikHandler: build a headless androidx PreferenceScreen,
    // let the source populate it, then serialize each preference to the SAME shape the
    // app's SourcePreference model expects. Values live in the source's own store
    // ("source_$id"); setPreference writes there and invalidates the cached source so the
    // change is picked up whether the source reads prefs at construction or per-request.

    private fun sourceId(src: Any): Long? =
        runCatching { src.javaClass.getMethod("getId").invoke(src) as? Long }.getOrNull()

    private fun preferencesJson(context: Context, src: Any): String {
        val screen = buildPreferenceScreen(context, src) ?: return "[]"
        return buildJsonArray {
            for (i in 0 until screen.preferenceCount) {
                prefJson(screen.getPreference(i))?.let { add(it) }
            }
        }.toString()
    }

    private fun buildPreferenceScreen(context: Context, src: Any): PreferenceScreen? = runCatching {
        // PreferenceManager's (Context) constructor is @RestrictTo — reach it reflectively.
        val ctor = PreferenceManager::class.java.getDeclaredConstructor(Context::class.java)
        ctor.isAccessible = true
        val pm = ctor.newInstance(context)
        // Point at the source's own store so extracted values reflect what the user saved.
        sourceId(src)?.let { pm.sharedPreferencesName = "source_$it" }
        val screen = pm.createPreferenceScreen(context)
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
            // CheckBoxPreference + SwitchPreference(Compat) all extend TwoStatePreference.
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

    private fun setPreference(
        context: Context, apk: String, lang: String?, src: Any, key: String, value: JsonElement?,
    ): String {
        if (key.isBlank() || value == null) return err("setPreference needs key and value")
        val id = sourceId(src) ?: return err("source has no id")
        val editor = context.getSharedPreferences("source_$id", Context.MODE_PRIVATE).edit()
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
        sourceCache.remove("$apk|$lang")
        return "{\"ok\":true}"
    }

    private fun err(msg: String) = buildJsonObject { put("error", msg) }.toString()
    private fun describe(t: Throwable): String = (t.cause ?: t).let { "${it.javaClass.simpleName}: ${it.message}" }

    private fun JsonObject.str(key: String, def: String): String =
        this[key]?.jsonPrimitive?.content ?: def
    private fun JsonObject.int(key: String, def: Int): Int =
        this[key]?.jsonPrimitive?.let { runCatching { it.int }.getOrNull() } ?: def
}
