import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple cookie store that persists cookies per domain.
/// Used to store Cloudflare clearance cookies from WebView.
class CookieStore {
  static const _prefix = 'cookies_';
  static const _uaKey = 'cloudflare_user_agent';
  static final CookieStore _instance = CookieStore._();
  factory CookieStore() => _instance;
  CookieStore._();

  final Map<String, Map<String, String>> _cache = {};
  final Map<String, DateTime> _resolvedAt = {}; // When CF was last resolved per domain
  String? _userAgent;

  String _normalize(String domain) =>
      domain.startsWith('www.') ? domain.substring(4) : domain;

  /// Store the User-Agent used during Cloudflare resolution.
  /// Subsequent requests must use this same UA or Cloudflare rejects the cookie.
  Future<void> setUserAgent(String ua) async {
    _userAgent = ua;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_uaKey, ua);
  }

  /// Get the stored User-Agent (from Cloudflare resolution).
  /// Falls back to a platform-aware default if none stored yet.
  Future<String> getUserAgent() async {
    if (_userAgent != null) return _userAgent!;
    final prefs = await SharedPreferences.getInstance();
    _userAgent = prefs.getString(_uaKey);
    return _userAgent ?? defaultUserAgent;
  }

  /// Platform-aware default User-Agent (used before WebView sets the real one).
  static String get defaultUserAgent {
    if (Platform.isAndroid) {
      return 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
    }
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  }

  /// Get stored cookies for a domain as a Cookie header string.
  /// Also checks parent domain (e.g. comic.naver.com checks naver.com too).
  Future<String?> getCookieHeader(String url) async {
    final domain = _normalize(Uri.parse(url).host);
    final merged = <String, String>{};

    // Check exact domain and parent domain
    final domains = [domain];
    final parts = domain.split('.');
    if (parts.length > 2) {
      domains.add(parts.sublist(parts.length - 2).join('.'));
    }

    final prefs = await SharedPreferences.getInstance();
    for (final d in domains) {
      if (_cache.containsKey(d) && _cache[d]!.isNotEmpty) {
        merged.addAll(_cache[d]!);
      } else {
        final stored = prefs.getStringList('$_prefix$d');
        if (stored != null && stored.isNotEmpty) {
          final cookies = <String, String>{};
          for (final entry in stored) {
            final idx = entry.indexOf('=');
            if (idx > 0) {
              cookies[entry.substring(0, idx)] = entry.substring(idx + 1);
            }
          }
          _cache[d] = cookies;
          merged.addAll(cookies);
        }
      }
    }

    if (merged.isEmpty) return null;
    return merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  /// Store cookies for a domain (merges with existing cookies).
  Future<void> setCookies(String rawDomain, Map<String, String> cookies) async {
    final domain = _normalize(rawDomain);
    // Merge with existing cookies instead of overwriting
    final existing = _cache[domain] ?? {};
    final merged = {...existing, ...cookies};
    _cache[domain] = merged;
    final prefs = await SharedPreferences.getInstance();
    final list = merged.entries.map((e) => '${e.key}=${e.value}').toList();
    await prefs.setStringList('$_prefix$domain', list);
  }

  /// Mark that Cloudflare was resolved for a domain.
  void markResolved(String url) {
    final domain = _normalize(Uri.parse(url).host);
    _resolvedAt[domain] = DateTime.now();
  }

  /// Check if Cloudflare cookies are still fresh (resolved within the last 30 min).
  bool hasFreshCookies(String url) {
    final domain = _normalize(Uri.parse(url).host);
    final resolved = _resolvedAt[domain];
    if (resolved == null) return false;
    return DateTime.now().difference(resolved).inMinutes < 30;
  }

  /// Clear cookies for a domain.
  Future<void> clearCookies(String domain) async {
    _cache.remove(domain);
    _resolvedAt.remove(domain);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$domain');
  }
}
