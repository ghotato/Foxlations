package okhttp3

/**
 * Compat for keiyoushi's `okhttp3.CompressionInterceptor`, which many keiyoushi sources
 * (AsuraScans and every `keiyoushi.source` base) construct as
 * `CompressionInterceptor(Brotli, Gzip, Zstd)` and add to their client. The class lives in
 * the `okhttp3` package (to reach OkHttp internals in the real impl) and is compiled
 * `compileOnly` in extensions, so the host must supply it at runtime. Suwayomi bundles it
 * (iOS/desktop), but the Mihon-style ApkBridge runtime does not — without it the source
 * fails to construct (`ClassNotFoundException: okhttp3.CompressionInterceptor`).
 *
 * We provide a **pass-through**: it does not advertise br/zstd, so OkHttp's own transparent
 * `Accept-Encoding: gzip` still applies and gzip responses are decompressed normally. That
 * covers virtually every site (servers only send an encoding the client advertised) and, as
 * a bonus, avoids the zstd JNI native that isn't shipped for Android arm64 — the exact thing
 * that broke AsuraScans on the constrained runtimes. The [DecompressionAlgorithm] arguments
 * are accepted for API compatibility and ignored.
 */
class CompressionInterceptor(
    @Suppress("UNUSED_PARAMETER") vararg algorithms: DecompressionAlgorithm,
) : Interceptor {
    /** Marker the Gzip/Brotli/Zstd objects implement; the real interface's methods are
     *  never called by extensions (they only pass the singletons to the constructor). */
    interface DecompressionAlgorithm

    override fun intercept(chain: Interceptor.Chain): Response = chain.proceed(chain.request())
}

/** keiyoushi's `okhttp3.Gzip` decompression-algorithm singleton. */
object Gzip : CompressionInterceptor.DecompressionAlgorithm
