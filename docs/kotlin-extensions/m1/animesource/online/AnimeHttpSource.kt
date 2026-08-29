package eu.kanade.tachiyomi.animesource.online

import eu.kanade.tachiyomi.animesource.AnimeCatalogueSource
import eu.kanade.tachiyomi.animesource.model.AnimeFilterList
import eu.kanade.tachiyomi.animesource.model.AnimesPage
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video
import eu.kanade.tachiyomi.network.GET
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.network.asObservableSuccess
import eu.kanade.tachiyomi.network.awaitSuccess
import okhttp3.Headers
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import rx.Observable
import uy.kohesive.injekt.injectLazy
import java.security.MessageDigest

/**
 * A real, JVM-runnable AnimeHttpSource — the anime parallel of Suwayomi's manga
 * HttpSource. Aniyomi's extensions-lib ships this class only as a "Stub!" thrower
 * (the app provides the impl on-device); this mirror lets Foxlations' embedded
 * Suwayomi host run the same Aniyomi extensions, using the SAME NetworkHelper /
 * OkHttp / Injekt already wired for manga.
 */
abstract class AnimeHttpSource : AnimeCatalogueSource {

    protected val network: NetworkHelper by injectLazy()

    abstract val baseUrl: String

    open val versionId = 1

    override val id by lazy { generateId(name, lang, versionId) }

    open val headers: Headers by lazy { headersBuilder().build() }

    open val client: OkHttpClient
        get() = network.client

    protected open fun headersBuilder(): Headers.Builder = Headers.Builder().apply {
        add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
    }

    protected fun generateId(name: String, lang: String, versionId: Int): Long {
        val key = "${name.lowercase()}/$lang/$versionId"
        val bytes = MessageDigest.getInstance("MD5").digest(key.toByteArray())
        return (0..7).map { bytes[it].toLong() and 0xff shl (7 - it) * 8 }
            .reduce(Long::or) and Long.MAX_VALUE
    }

    override fun toString(): String = "$name (${lang.uppercase()})"

    // ── Popular ──────────────────────────────────────────────────────────────
    override fun fetchPopularAnime(page: Int): Observable<AnimesPage> =
        client.newCall(popularAnimeRequest(page)).asObservableSuccess().map { popularAnimeParse(it) }

    override suspend fun getPopularAnime(page: Int): AnimesPage =
        popularAnimeParse(client.newCall(popularAnimeRequest(page)).awaitSuccess())

    protected abstract fun popularAnimeRequest(page: Int): Request
    protected abstract fun popularAnimeParse(response: Response): AnimesPage

    // ── Latest ───────────────────────────────────────────────────────────────
    override fun fetchLatestUpdates(page: Int): Observable<AnimesPage> =
        client.newCall(latestUpdatesRequest(page)).asObservableSuccess().map { latestUpdatesParse(it) }

    override suspend fun getLatestUpdates(page: Int): AnimesPage =
        latestUpdatesParse(client.newCall(latestUpdatesRequest(page)).awaitSuccess())

    protected abstract fun latestUpdatesRequest(page: Int): Request
    protected abstract fun latestUpdatesParse(response: Response): AnimesPage

    // ── Search ───────────────────────────────────────────────────────────────
    override fun fetchSearchAnime(page: Int, query: String, filters: AnimeFilterList): Observable<AnimesPage> =
        client.newCall(searchAnimeRequest(page, query, filters)).asObservableSuccess().map { searchAnimeParse(it) }

    override suspend fun getSearchAnime(page: Int, query: String, filters: AnimeFilterList): AnimesPage =
        searchAnimeParse(client.newCall(searchAnimeRequest(page, query, filters)).awaitSuccess())

    protected abstract fun searchAnimeRequest(page: Int, query: String, filters: AnimeFilterList): Request
    protected abstract fun searchAnimeParse(response: Response): AnimesPage

    // ── Details ──────────────────────────────────────────────────────────────
    override fun fetchAnimeDetails(anime: SAnime): Observable<SAnime> =
        client.newCall(animeDetailsRequest(anime)).asObservableSuccess()
            .map { animeDetailsParse(it).apply { initialized = true } }

    override suspend fun getAnimeDetails(anime: SAnime): SAnime =
        animeDetailsParse(client.newCall(animeDetailsRequest(anime)).awaitSuccess())

    open fun animeDetailsRequest(anime: SAnime): Request = GET(baseUrl + anime.url, headers)
    protected abstract fun animeDetailsParse(response: Response): SAnime

    open fun getAnimeUrl(anime: SAnime): String = animeDetailsRequest(anime).url.toString()

    // ── Episodes ─────────────────────────────────────────────────────────────
    override fun fetchEpisodeList(anime: SAnime): Observable<List<SEpisode>> =
        client.newCall(episodeListRequest(anime)).asObservableSuccess().map { episodeListParse(it) }

    override suspend fun getEpisodeList(anime: SAnime): List<SEpisode> =
        episodeListParse(client.newCall(episodeListRequest(anime)).awaitSuccess())

    protected open fun episodeListRequest(anime: SAnime): Request = GET(baseUrl + anime.url, headers)
    protected abstract fun episodeListParse(response: Response): List<SEpisode>

    open fun getEpisodeUrl(episode: SEpisode): String = baseUrl + episode.url

    // ── Videos ───────────────────────────────────────────────────────────────
    override fun fetchVideoList(episode: SEpisode): Observable<List<Video>> =
        client.newCall(videoListRequest(episode)).asObservableSuccess().map { videoListParse(it) }

    override suspend fun getVideoList(episode: SEpisode): List<Video> =
        videoListParse(client.newCall(videoListRequest(episode)).awaitSuccess())

    protected open fun videoListRequest(episode: SEpisode): Request = GET(baseUrl + episode.url, headers)
    protected abstract fun videoListParse(response: Response): List<Video>

    open fun fetchVideoUrl(video: Video): Observable<String> =
        client.newCall(videoUrlRequest(video)).asObservableSuccess().map { videoUrlParse(it) }

    protected open fun videoUrlRequest(video: Video): Request = GET(video.url, headers)
    protected open fun videoUrlParse(response: Response): String = ""

    // ── Misc ─────────────────────────────────────────────────────────────────
    override fun getFilterList(): AnimeFilterList = AnimeFilterList()

    open fun setUrlWithoutDomain(anime: SAnime, url: String) { anime.url = url }
    open fun setUrlWithoutDomain(episode: SEpisode, url: String) { episode.url = url }
}
