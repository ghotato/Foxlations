package eu.kanade.tachiyomi.animesource.model

// Real SEpisode + impl (extensions-lib:14 stubs the `create()` companion and omits
// SEpisodeImpl). Mirrors Tachiyomi/Suwayomi's SChapter. SEpisode is the anime
// parallel of SChapter (episode_number ↔ chapter_number).
interface SEpisode {
    var url: String
    var name: String
    var date_upload: Long
    var episode_number: Float
    var scanlator: String?

    companion object {
        fun create(): SEpisode = SEpisodeImpl()
    }
}

class SEpisodeImpl : SEpisode {
    override var url: String = ""
    override var name: String = ""
    override var date_upload: Long = 0L
    override var episode_number: Float = -1f
    override var scanlator: String? = null
}
