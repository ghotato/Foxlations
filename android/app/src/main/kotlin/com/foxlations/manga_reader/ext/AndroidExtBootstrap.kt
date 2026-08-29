package com.foxlations.manga_reader.ext

import android.app.Application
import android.content.Context
import eu.kanade.tachiyomi.network.NetworkHelper
import eu.kanade.tachiyomi.network.interceptor.CloudflareInterceptor
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import uy.kohesive.injekt.Injekt
import uy.kohesive.injekt.api.InjektModule
import uy.kohesive.injekt.api.InjektRegistrar
import uy.kohesive.injekt.api.addSingleton
import uy.kohesive.injekt.api.addSingletonFactory
import uy.kohesive.injekt.api.get

/**
 * Stands up the DI a Tachiyomi/Aniyomi source needs to construct: the [Application] and a
 * [NetworkHelper] (which holds the shared OkHttpClient) via Injekt, plus a Json. Sources
 * fetch the client with `by injectLazy()` and read their prefs from
 * `Application.getSharedPreferences("source_<id>")`. Mirrors ApkBridge's AppModule.
 */
object AndroidExtBootstrap {
    @Volatile private var done = false

    @Synchronized
    fun ensure(context: Context) {
        if (done) return
        val app = context.applicationContext as Application
        Injekt.importModule(object : InjektModule {
            override fun InjektRegistrar.registerInjectables() {
                addSingleton<Application>(app)
                addSingletonFactory { Json { ignoreUnknownKeys = true; explicitNulls = false } }
                addSingletonFactory { NetworkHelper(app) }
            }
        })
        runCatching { patchDefaultClient(Injekt.get<NetworkHelper>()) } // warm + reshape client
        done = true
    }

    /**
     * keiyoushi's base HttpSource validates the default client's interceptors and refuses to
     * run unless it matches Mihon's shape (verified by disassembling keiyoushi.source.a):
     *   • present (application): UncaughtExceptionInterceptor, UserAgentInterceptor, CloudflareInterceptor
     *   • absent  (network):     IgnoreGzipInterceptor, BrotliInterceptor
     * (the source brings its own CompressionInterceptor, so host-side gzip/brotli would double-handle).
     * ApkBridge already has the first two application interceptors but omits CloudflareInterceptor
     * and adds the two forbidden network interceptors, so reshape client + cloudflareClient here,
     * before any source is constructed. `client`/`cloudflareClient` are final `val`s — set the
     * backing field reflectively (allowed for final INSTANCE fields with setAccessible).
     * Best-effort: a shape change upstream degrades to the original client, never a crash.
     */
    private fun patchDefaultClient(nh: NetworkHelper) {
        val cf = CloudflareInterceptor()
        val forbidden = setOf("IgnoreGzipInterceptor", "BrotliInterceptor")
        for (name in arrayOf("client", "cloudflareClient")) {
            runCatching {
                val f = nh.javaClass.getDeclaredField(name)
                f.isAccessible = true
                val cur = f.get(nh) as? OkHttpClient ?: return@runCatching
                val b = cur.newBuilder()
                // Builder.interceptors/networkInterceptors are internal props — use the
                // public interceptors()/networkInterceptors() accessors (they return the
                // live MutableList).
                if (b.interceptors().none { it.javaClass.simpleName == "CloudflareInterceptor" }) {
                    b.interceptors().add(cf)
                }
                b.networkInterceptors().removeAll { it.javaClass.simpleName in forbidden }
                f.set(nh, b.build())
            }
        }
    }
}
