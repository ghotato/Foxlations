package eu.kanade.tachiyomi.source.model

import kotlinx.serialization.json.JsonObject
import java.io.Serializable

/**
 * ApkBridge's SManga with the API-1.6 `memo` field added. keiyoushi extensions call
 * `SManga.setMemo(JsonObject)` / `getMemo()` to round-trip opaque per-source metadata
 * (e.g. Iken sources stash an id here) between browse and detail calls; ApkBridge's model
 * omits it, which crashed those sources with `NoSuchMethodError: setMemo`. Vendored over
 * ApkBridge's copy by the Android build (CI); the JVM host uses Suwayomi's model, which
 * already has memo. Keep the rest byte-for-byte compatible with ApkBridge's SManga.
 */
interface SManga : Serializable {

    var url: String

    var title: String

    var artist: String?

    var author: String?

    var description: String?

    var genre: String?

    var status: Int

    var thumbnail_url: String?

    var update_strategy: UpdateStrategy

    var initialized: Boolean

    var memo: JsonObject?

    fun getGenres(): List<String>? {
        if (genre.isNullOrBlank()) return null
        return genre?.split(", ")?.map { it.trim() }?.filterNot { it.isBlank() }?.distinct()
    }

    fun copyFrom(other: SManga) {
        if (other.author != null) {
            author = other.author
        }

        if (other.artist != null) {
            artist = other.artist
        }

        if (other.description != null) {
            description = other.description
        }

        if (other.genre != null) {
            genre = other.genre
        }

        if (other.thumbnail_url != null) {
            thumbnail_url = other.thumbnail_url
        }

        status = other.status

        update_strategy = other.update_strategy

        if (other.memo != null) {
            memo = other.memo
        }

        if (!initialized) {
            initialized = other.initialized
        }
    }

    fun copy() = create().also {
        it.url = url
        it.title = title
        it.artist = artist
        it.author = author
        it.description = description
        it.genre = genre
        it.status = status
        it.thumbnail_url = thumbnail_url
        it.update_strategy = update_strategy
        it.memo = memo
        it.initialized = initialized
    }

    companion object {
        const val UNKNOWN = 0
        const val ONGOING = 1
        const val COMPLETED = 2
        const val LICENSED = 3
        const val PUBLISHING_FINISHED = 4
        const val CANCELLED = 5
        const val ON_HIATUS = 6

        fun create(): SManga {
            return SMangaImpl()
        }

        private const val serialVersionUID = 1L
    }
}
