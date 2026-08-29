package eu.kanade.tachiyomi.source.model

import kotlinx.serialization.json.JsonObject
import java.io.Serializable

/**
 * ApkBridge's SChapter with the API-1.6 `memo` field added (see [SManga]). keiyoushi
 * sources round-trip a per-chapter JsonObject here (e.g. an id read back in getPageList);
 * without it they fail with `NoSuchMethodError: setMemo`. Vendored over ApkBridge's copy by
 * the Android build; the JVM host uses Suwayomi's model, which already has memo.
 */
interface SChapter : Serializable {

    var url: String

    var name: String

    var date_upload: Long

    var chapter_number: Float

    var scanlator: String?

    var memo: JsonObject?

    fun copyFrom(other: SChapter) {
        name = other.name
        url = other.url
        date_upload = other.date_upload
        chapter_number = other.chapter_number
        scanlator = other.scanlator
        if (other.memo != null) {
            memo = other.memo
        }
    }

    companion object {
        fun create(): SChapter {
            return SChapterImpl()
        }
    }
}
