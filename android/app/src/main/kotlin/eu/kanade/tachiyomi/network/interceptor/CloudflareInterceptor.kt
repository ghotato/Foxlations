package eu.kanade.tachiyomi.network.interceptor

import okhttp3.Interceptor
import okhttp3.Response

/**
 * Presence-only Cloudflare interceptor required by keiyoushi's base HttpSource.
 *
 * That base validates the default OkHttp client by walking `client.newBuilder().interceptors()`
 * and checking `interceptor.javaClass.simpleName == "CloudflareInterceptor"`; if none matches it
 * throws `IllegalStateException("CloudflareInterceptor must be present in default client")`
 * (verified by disassembling `keiyoushi.source.a`). Mihon's NetworkHelper ships one; ApkBridge's
 * deliberately does not — so we supply it and inject an instance into NetworkHelper's client(s)
 * in [com.foxlations.manga_reader.ext.AndroidExtBootstrap].
 *
 * The check is by simple name (not `instanceof`/FQN), and only works because R8 minification is
 * off — otherwise the class would be renamed. Functionally this is a pass-through: the app's real
 * Cloudflare handling is the cookie/UA injection (CloudflareCookies) plus the Dart-side headless
 * solve-and-retry. Kept in Mihon's package + name so any source that instead checks by type is
 * also satisfied.
 */
class CloudflareInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response = chain.proceed(chain.request())
}
