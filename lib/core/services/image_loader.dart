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
  final Map<String, Uint8List> _cache = {};
  static const int _maxCacheSize = 200;
  final Set<String> _blockedDomains = {};

  Future<rhttp.RhttpClient> _getClient() async {
    if (_client != null) return _client!;
    _client = await rhttp.RhttpClient.create(
      settings: const rhttp.ClientSettings(
        throwOnStatusCode: false,
        tlsSettings: rhttp.TlsSettings(
          verifyCertificates: false,
        ),
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
      'sec-ch-ua': '"Not A Brand";v="99","Google Chrome";v="120","Chromium";v="120"',
      'sec-ch-ua-mobile': '?0',
      'sec-ch-ua-platform': '"Windows"',
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
    if (_cache.length >= _maxCacheSize) {
      final keysToRemove = _cache.keys.take(_cache.length ~/ 4).toList();
      for (final key in keysToRemove) {
        _cache.remove(key);
      }
    }
    _cache[url] = bytes;
  }

  void clearCache() {
    _cache.clear();
    _blockedDomains.clear();
    _client?.dispose();
    _client = null;
  }
}
