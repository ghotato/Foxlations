package okhttp3.brotli

import okhttp3.CompressionInterceptor

/**
 * keiyoushi's `okhttp3.brotli.Brotli` decompression-algorithm singleton, passed to
 * [CompressionInterceptor]. Provided by the host at runtime (compileOnly in extensions);
 * see [CompressionInterceptor] for why this is a marker only. Note this is distinct from
 * OkHttp's real `okhttp3.brotli.BrotliInterceptor`.
 */
object Brotli : CompressionInterceptor.DecompressionAlgorithm
