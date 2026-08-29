package eu.kanade.tachiyomi.source.model

/**
 * extensions-lib 1.6 `SMangaUpdate` — the combined result of `getMangaUpdate(...)`, which
 * keiyoushi sources implement (and stub the classic getMangaDetails/getChapterList, so those
 * throw UnsupportedOperationException). ApkBridge's runtime omits it; vendored here so
 * getMangaUpdate is callable on Android. Structure matches keiyoushi extensions-lib v16
 * exactly (manga + chapters, with getManga()/getChapters()). The JVM host uses Suwayomi's own.
 */
class SMangaUpdate(
    val manga: SManga,
    val chapters: List<SChapter>,
)
