import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:rhttp/rhttp.dart' as rhttp;
import 'cookie_store.dart';

/// Loads images using rhttp (Rust/reqwest) with Chrome-like TLS fingerprint.
/// This is the same HTTP engine that bypasses Cloudflare.
class ImageLoader {
  static final ImageLoader _instance = ImageLoader._();
  factory ImageLoader() => _instance;
  ImageLoader._();

  rhttp.RhttpClient? _client;
  /// Insertion-ordered, so `keys.first` is the oldest entry.
  final Map<String, Uint8List> _cache = {};
  int _cacheBytes = 0;

  /// Encoded-image cache budget. Bytes are the real constraint — entry count
  /// is kept only as a secondary guard against pathologically tiny images.
  static const int _maxCacheBytes = 64 * 1024 * 1024;
  static const int _maxCacheEntries = 200;
  final Set<String> _blockedDomains = {};

  Future<rhttp.RhttpClient> _getClient() async {
    if (_client != null) return _client!;
    // Verify TLS — image requests carry per-domain cookies too, and a MITM
    // that can forge a cert could otherwise swap image bytes or harvest them.
    _client = await rhttp.RhttpClient.create(
      settings: const rhttp.ClientSettings(
        throwOnStatusCode: false,
      ),
    );
    return _client!;
  }

  /// Load image bytes from URL with headers.
  Future<Uint8List?> loadImage(String url,
      {Map<String, String>? headers}) async {
    if (url.isEmpty) return null;
    if (_cache.containsKey(url)) return _cache[url];

    final imageDomain = Uri.tryParse(url)?.host ?? '';
    if (_blockedDomains.contains(imageDomain)) return null;

    // Build headers — include Sec-Fetch-* so Cloudflare's bot detection treats
    // this as a legitimate cross-origin image request from a browser.
    final refererForSite = headers?['Referer'];
    final isCrossOrigin = refererForSite != null &&
        Uri.tryParse(refererForSite)?.host != Uri.tryParse(url)?.host;
    final mergedHeaders = <String, String>{
      'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
      'sec-fetch-dest': 'image',
      'sec-fetch-mode': 'no-cors',
      'sec-fetch-site': isCrossOrigin ? 'cross-site' : 'same-site',
      // Client Hints are Chromium-only — Safari never sends them. On iOS the
      // stored UA is iOS Safari, so advertising Chromium *and* desktop Windows
      // from an iPhone is a strong bot signal. A 403 here is unrecoverable:
      // the domain gets added to _blockedDomains for the rest of the session.
      if (!Platform.isIOS) ...{
        'sec-ch-ua':
            '"Not A Brand";v="99","Google Chrome";v="120","Chromium";v="120"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
      },
      ...?headers,
    };

    // Use stored UA
    final storedUA = await CookieStore().getUserAgent();
    mergedHeaders.putIfAbsent('User-Agent', () => storedUA);

    // Only send cookies that belong to the image domain.
    // Do NOT send the Referer domain's cookies here — that leaks source-site
    // session tokens (e.g. missav.ai cookies) to third-party CDNs.
    final imageCookies = await CookieStore().getCookieHeader(url);
    if (imageCookies != null) {
      final existing = mergedHeaders['Cookie'] ?? '';
      if (existing.isEmpty) {
        mergedHeaders['Cookie'] = imageCookies;
      } else if (!existing.contains(imageCookies)) {
        mergedHeaders['Cookie'] = '$existing; $imageCookies';
      }
    }

    // Try loading with rhttp (Chrome TLS fingerprint)
    try {
      final client = await _getClient();
      final response = await client.requestBytes(
        method: rhttp.HttpMethod.get,
        url: url,
        headers: rhttp.HttpHeaders.rawMap(mergedHeaders),
      );

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final bytes = Uint8List.fromList(response.body);
        _addToCache(url, bytes);
        debugPrint('[ImageLoader] Loaded ${bytes.length} bytes from $url');
        return bytes;
      }

      if (response.statusCode == 403) {
        // Some CDNs (e.g. fourhoi.com) use Cloudflare Managed Challenge which
        // can't be bypassed by any automated HTTP client. Block immediately so
        // we don't waste 30 s per page on a bypass that will always fail.
        debugPrint('[ImageLoader] 403 for $url — blocking domain $imageDomain');
        _blockedDomains.add(imageDomain);
      }
    } catch (e) {
      debugPrint('[ImageLoader] Error loading $url: $e');
    }

    return null;
  }

  void unblockDomains() => _blockedDomains.clear();

  void _addToCache(String url, Uint8List bytes) {
    // A single oversized page shouldn't be able to evict the whole cache.
    if (bytes.lengthInBytes > _maxCacheBytes ~/ 4) return;

    _cache[url] = bytes;
    _cacheBytes += bytes.lengthInBytes;

    // Evict oldest-first until BOTH budgets are satisfied. Capping by entry
    // count alone is what let this grow unbounded: webtoon strips are ~10x the
    // size of a normal page, so 200 of them is gigabytes of encoded data held
    // outside Flutter's ImageCache budget. Android merely OOMs; iOS jetsams the
    // process with no Dart exception, so the app just vanishes mid-chapter.
    while (_cache.isNotEmpty &&
        (_cacheBytes > _maxCacheBytes || _cache.length > _maxCacheEntries)) {
      final oldest = _cache.keys.first;
      final evicted = _cache.remove(oldest);
      _cacheBytes -= evicted?.lengthInBytes ?? 0;
    }
    if (_cache.isEmpty) _cacheBytes = 0;
  }

  void clearCache() {
    _cache.clear();
    _cacheBytes = 0;
    _blockedDomains.clear();
    _client?.dispose();
    _client = null;
  }
}
