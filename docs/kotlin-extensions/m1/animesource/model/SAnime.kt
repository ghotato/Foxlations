package eu.kanade.tachiyomi.animesource.model

// Real SAnime + impl for the embedded Suwayomi host. Aniyomi's extensions-lib
// (com.github.aniyomiorg:extensions-lib:14) ships SAnime's companion `create()` as
// a "Stub!" thrower and omits SAnimeImpl (the app provides them on-device); these
// mirror Tachiyomi/Suwayomi's SManga so the same Aniyomi extensions run on the JVM.
// The interface surface is kept binary-identical to extensions-lib:14 so extensions
// compiled against it link against this at runtime.
interface SAnime {
    var url: String
    var title: String
    var artist: String?
    var author: String?
    var description: String?
    var genre: String?
    var status: Int
    var thumbnail_url: String?
    var update_strategy: AnimeUpdateStrategy
    var initialized: Boolean

    companion object {
        const val UNKNOWN = 0
        const val ONGOING = 1
        const val COMPLETED = 2
        const val LICENSED = 3
        const val PUBLISHING_FINISHED = 4
        const val CANCELLED = 5
        const val ON_HIATUS = 6
        fun create(): SAnime = SAnimeImpl()
    }
}

class SAnimeImpl : SAnime {
    override var url: String = ""
    override var title: String = ""
    override var artist: String? = null
    override var author: String? = null
    override var description: String? = null
    override var genre: String? = null
    override var status: Int = 0
    override var thumbnail_url: String? = null
    override var update_strategy: AnimeUpdateStrategy = AnimeUpdateStrategy.ALWAYS_UPDATE
    override var initialized: Boolean = false
}
