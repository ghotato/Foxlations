package eu.kanade.tachiyomi.animesource.online

import eu.kanade.tachiyomi.animesource.model.AnimesPage
import eu.kanade.tachiyomi.animesource.model.SAnime
import eu.kanade.tachiyomi.animesource.model.SEpisode
import eu.kanade.tachiyomi.animesource.model.Video
import okhttp3.Response
import org.jsoup.Jsoup
import org.jsoup.nodes.Document
import org.jsoup.nodes.Element

/**
 * Jsoup-selector base for HTML-scraping anime sources — the anime parallel of
 * Suwayomi's manga ParsedHttpSource. extensions-lib ships this as a "Stub!" thrower;
 * this real mirror lets the many selector-based Aniyomi extensions run on the JVM host.
 */
abstract class ParsedAnimeHttpSource : AnimeHttpSource() {

    protected fun Response.asJsoup(html: String? = null): Document =
        Jsoup.parse(html ?: body.string(), request.url.toString())

    // ── Popular ──
    override fun popularAnimeParse(response: Response): AnimesPage {
        val document = response.asJsoup()
        val animes = document.select(popularAnimeSelector()).map { popularAnimeFromElement(it) }
        val hasNextPage = popularAnimeNextPageSelector()?.let { document.selectFirst(it) } != null
        return AnimesPage(animes, hasNextPage)
    }
    protected abstract fun popularAnimeSelector(): String
    protected abstract fun popularAnimeFromElement(element: Element): SAnime
    protected abstract fun popularAnimeNextPageSelector(): String?

    // ── Search ──
    override fun searchAnimeParse(response: Response): AnimesPage {
        val document = response.asJsoup()
        val animes = document.select(searchAnimeSelector()).map { searchAnimeFromElement(it) }
        val hasNextPage = searchAnimeNextPageSelector()?.let { document.selectFirst(it) } != null
        return AnimesPage(animes, hasNextPage)
    }
    protected abstract fun searchAnimeSelector(): String
    protected abstract fun searchAnimeFromElement(element: Element): SAnime
    protected abstract fun searchAnimeNextPageSelector(): String?

    // ── Latest ──
    override fun latestUpdatesParse(response: Response): AnimesPage {
        val document = response.asJsoup()
        val animes = document.select(latestUpdatesSelector()).map { latestUpdatesFromElement(it) }
        val hasNextPage = latestUpdatesNextPageSelector()?.let { document.selectFirst(it) } != null
        return AnimesPage(animes, hasNextPage)
    }
    protected abstract fun latestUpdatesSelector(): String
    protected abstract fun latestUpdatesFromElement(element: Element): SAnime
    protected abstract fun latestUpdatesNextPageSelector(): String?

    // ── Details ──
    override fun animeDetailsParse(response: Response): SAnime = animeDetailsParse(response.asJsoup())
    protected abstract fun animeDetailsParse(document: Document): SAnime

    // ── Episodes ──
    override fun episodeListParse(response: Response): List<SEpisode> =
        response.asJsoup().select(episodeListSelector()).map { episodeFromElement(it) }
    protected abstract fun episodeListSelector(): String
    protected abstract fun episodeFromElement(element: Element): SEpisode

    // ── Videos ──
    override fun videoListParse(response: Response): List<Video> =
        response.asJsoup().select(videoListSelector()).map { videoFromElement(it) }
    protected abstract fun videoListSelector(): String
    protected abstract fun videoFromElement(element: Element): Video

    override fun videoUrlParse(response: Response): String = videoUrlParse(response.asJsoup())
    protected abstract fun videoUrlParse(document: Document): String
}
