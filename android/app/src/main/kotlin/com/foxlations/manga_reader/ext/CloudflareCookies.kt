package com.foxlations.manga_reader.ext

import eu.kanade.tachiyomi.network.NetworkHelper
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl.Companion.toHttpUrl
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.get

/**
 * Bridges the app's Cloudflare clearances into the extension runtime.
 *
 * Unlike the embedded-JVM hosts (iOS/desktop), the ApkBridge [NetworkHelper] on Android
 * has no CloudflareInterceptor / FlareSolverr: its OkHttp client just carries whatever is
 * in its in-memory cookie jar plus a fixed default User-Agent. So when the app solves a
 * challenge in its WebView (WebViewService → CookieStore), Dart pushes those cookies + the
 * matching UA down here on each `invoke` and we inject them:
 *   • cookies via the standard [CookieJar.saveFromResponse] contract (works whatever jar
 *     the vendored runtime uses — MemoryCookieJar today);
 *   • UA via NetworkHelper.setUA, which feeds ApkBridge's UserAgentInterceptor.
 *
 * cf_clearance is bound to the exact User-Agent that solved the challenge, so the UA MUST
 * be kept in sync or Cloudflare rejects the cookie. Everything is best-effort: a shape
 * change upstream degrades to "no clearance", never a crash.
 */
object CloudflareCookies {
    @Volatile private var lastUa: String? = null

    fun apply(userAgent: String?, cookiesByDomain: JsonObject?) {
        val nh = runCatching { Injekt.get<NetworkHelper>() }.getOrNull() ?: return

        if (!userAgent.isNullOrBlank() && userAgent != lastUa) {
            // setUA is ApkBridge's hook into UserAgentInterceptor's default provider.
            // Reflected so a runtime that renames/drops it just skips UA sync.
            runCatching {
                nh.javaClass.getMethod("setUA", String::class.java).invoke(nh, userAgent)
                lastUa = userAgent
            }
        }

        if (cookiesByDomain == null || cookiesByDomain.isEmpty()) return
        val jar: CookieJar = runCatching { nh.cookieJar }.getOrNull() ?: return
        for ((domain, headerEl) in cookiesByDomain) {
            val header = (headerEl as? JsonPrimitive)?.content ?: continue
            val url = runCatching { "https://$domain/".toHttpUrl() }.getOrNull() ?: continue
            val cookies = header.split(";").mapNotNull { pair ->
                val t = pair.trim()
                val eq = t.indexOf('=')
                if (eq <= 0) return@mapNotNull null
                val name = t.substring(0, eq).trim()
                val value = t.substring(eq + 1).trim()
                runCatching {
                    // Domain-scoped (not host-only) so it matches the apex + any subdomain
                    // the source hits; long expiry so the jar won't prune it (the app
                    // re-pushes fresh values each invoke anyway).
                    Cookie.Builder()
                        .name(name)
                        .value(value)
                        .domain(domain)
                        .path("/")
                        .expiresAt(System.currentTimeMillis() + 7L * 24 * 60 * 60 * 1000)
                        .build()
                }.getOrNull()
            }
            if (cookies.isNotEmpty()) runCatching { jar.saveFromResponse(url, cookies) }
        }
    }
}
