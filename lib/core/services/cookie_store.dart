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
  ///
  /// iOS needs its own branch: without it the phone claims to be desktop
  /// Chrome on Windows, and then once the WebView resolves Cloudflare the
  /// stored UA flips to the real iOS Safari string mid-session. Cloudflare
  /// ties `cf_clearance` to the UA that solved the challenge, so that switch
  /// invalidates the clearance and re-triggers the challenge every time.
  static String get defaultUserAgent {
    if (Platform.isAndroid) {
      return 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
    }
    if (Platform.isIOS) {
      return 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 '
          'Mobile/15E148 Safari/604.1';
    }
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  }

  /// Multi-label public suffixes where the "last two labels" are NOT a single
  /// owner. Attaching a cookie stored for one `*.github.io` tenant to a request
  /// for a sibling tenant would leak it across origins. Not exhaustive (a full
  /// Public Suffix List is huge), but covers the suffixes a source is realistic
  /// to touch. When the registrable domain lands on one of these, we do NOT
  /// widen to it.
  static const _multiLabelSuffixes = {
    'co.uk', 'org.uk', 'ac.uk', 'gov.uk', 'co.jp', 'or.jp', 'ne.jp',
    'co.kr', 'or.kr', 'com.br', 'com.au', 'com.cn', 'co.in', 'co.nz',
    'github.io', 'blogspot.com', 'wordpress.com', 'pages.dev', 'workers.dev',
    'netlify.app', 'vercel.app', 'web.app', 'firebaseapp.com',
  };

  /// Get stored cookies for a domain as a Cookie header string.
  /// Also checks the registrable parent (e.g. comic.naver.com → naver.com),
  /// but never a public-suffix parent, which would cross tenant boundaries.
  Future<String?> getCookieHeader(String url) async {
    final domain = _normalize(Uri.parse(url).host);
    final merged = <String, String>{};

    final domains = [domain];
    final parts = domain.split('.');
    if (parts.length > 2) {
      final parent = parts.sublist(parts.length - 2).join('.');
      // e.g. for foo.github.io the parent is github.io — a public suffix, so
      // skip it. Only widen to a real registrable domain.
      if (!_multiLabelSuffixes.contains(parent)) {
        domains.add(parent);
      } else if (parts.length > 3) {
        // foo.bar.github.io → bar.github.io is the registrable domain.
        domains.add(parts.sublist(parts.length - 3).join('.'));
      }
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
