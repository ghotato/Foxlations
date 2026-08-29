package eu.kanade.tachiyomi.source

/**
 * Stub of keiyoushi's `RateLimited` marker interface, which newer keiyoushi extensions
 * (e.g. NovelFire / "Novel Phoenix") implement but Suwayomi v2.3.2243 doesn't ship — without
 * it those sources fail to load (NoClassDefFoundError). The values are advisory: the source
 * applies its own rate limiting internally (keiyoushi.network.rateLimit), so the host only
 * needs the interface to exist with the members the extension overrides/calls.
 *
 * Compiled into runner.jar (embedded-JVM hosts) and vendored on Android.
 */
interface RateLimited {
    val recommendedPermits: Int
    val recommendedDelayMillis: Long

    /** NovelFire reads this (a default) to seed its own rate-limit period. */
    val minimumDelayMillis: Long
        get() = recommendedDelayMillis
}
