package okhttp3.zstd

import okhttp3.CompressionInterceptor

/**
 * keiyoushi's `okhttp3.zstd.Zstd` decompression-algorithm singleton, passed to
 * [CompressionInterceptor]. A marker only (see [CompressionInterceptor]) — deliberately no
 * real zstd support, since the zstd JNI native isn't shipped for Android arm64; the
 * pass-through interceptor falls back to gzip instead.
 */
object Zstd : CompressionInterceptor.DecompressionAlgorithm
