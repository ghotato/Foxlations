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

    // Build headers
    final mergedHeaders = <String, String>{
      'Accept':
          'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
      ...?headers,
    };

    // Use stored UA
    final storedUA = await CookieStore().getUserAgent();
    mergedHeaders.putIfAbsent('User-Agent', () => storedUA);

    // Add source domain cookies (for CDN hotlink protection)
    final referer = headers?['Referer'];
    if (referer != null && referer.isNotEmpty) {
      final refererCookies = await CookieStore().getCookieHeader(referer);
      if (refererCookies != null) {
        mergedHeaders['Cookie'] = refererCookies;
      }
    }

    // Also add image domain cookies
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
        debugPrint(
            '[ImageLoader] 403 for $url — blocking domain $imageDomain');
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
