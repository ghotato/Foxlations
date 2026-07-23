import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data' show BytesBuilder;
import 'package:flutter/foundation.dart';
import 'package:d4rt/d4rt.dart';
import 'package:rhttp/rhttp.dart' as rhttp;
import '../../../core/services/cookie_store.dart';
import '../../../core/services/webview_service.dart';
import '../../model/m_source.dart';

/// When true, HTTP bridge skips WebView operations (running in background isolate).
bool isBackgroundIsolate = false;

/// Bridges HTTP client for Dart extensions running in d4rt.
/// Uses rhttp (Rust/reqwest) for Chrome-like TLS fingerprint.
class HttpBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: _HttpClient,
      name: 'Client',
      constructors: {
        // Client() — no base. Client(source) — resolve relative URLs against
        // the source's baseUrl (Mangayomi-format sources rely on this).
        '': (visitor, positionalArgs, namedArgs) {
          String? base;
          if (positionalArgs.isNotEmpty && positionalArgs[0] is MSource) {
            base = (positionalArgs[0] as MSource).baseUrl;
          }
          return _HttpClient(baseUrl: base);
        },
      },
      methods: {
        'get': (visitor, instance, positionalArgs, namedArgs) async {
          final client = instance as _HttpClient;
          // Accept a String OR a Uri: Mangayomi-format sources commonly pass
          // client.get(Uri.parse(...)), and a Uri's toString() is the URL.
          // Resolve relative paths against the client's base.
          final url = client._resolve('${positionalArgs[0]}');
          final headers =
              (namedArgs['headers'] as Map?)?.cast<String, String>() ?? {};
          return await client.get(url, headers: headers);
        },
        // Returns the raw response body as a List<int> (bytes 0-255).
        // Required for sources that consume binary endpoints (e.g. Hitomi's
        // .nozomi gallery indices). Headers are forwarded so callers can
        // pass Range, Referer, etc.
        'getBytes': (visitor, instance, positionalArgs, namedArgs) async {
          final client = instance as _HttpClient;
          // Accept a String OR a Uri: Mangayomi-format sources commonly pass
          // client.get(Uri.parse(...)), and a Uri's toString() is the URL.
          // Resolve relative paths against the client's base.
          final url = client._resolve('${positionalArgs[0]}');
          final headers =
              (namedArgs['headers'] as Map?)?.cast<String, String>() ?? {};
          return await client.getBytes(url, headers: headers);
        },
        'post': (visitor, instance, positionalArgs, namedArgs) async {
          final client = instance as _HttpClient;
          // Accept a String OR a Uri: Mangayomi-format sources commonly pass
          // client.get(Uri.parse(...)), and a Uri's toString() is the URL.
          // Resolve relative paths against the client's base.
          final url = client._resolve('${positionalArgs[0]}');
          // Accept headers as positional[1] (if Map) or named
          Map<String, String> headers = {};
          dynamic body;
          if (positionalArgs.length > 1 && positionalArgs[1] is Map) {
            headers = (positionalArgs[1] as Map).cast<String, String>();
            body = positionalArgs.length > 2 ? positionalArgs[2] : namedArgs['body'];
          } else {
            headers = (namedArgs['headers'] as Map?)?.cast<String, String>() ?? {};
            body = positionalArgs.length > 1 ? positionalArgs[1] : namedArgs['body'];
          }
          final result = await client.post(url, headers: headers, body: body);
          debugPrint('[HTTP] POST $url → ${result.statusCode} (${result.body.length} bytes)');
          return result;
        },
      },
      getters: {},
      setters: {},
    );
  }
}

class _HttpClient {
  rhttp.RhttpClient? _client;

  /// Base URL for resolving relative request paths. Mangayomi-format sources
  /// construct `Client(source)` and then call `get('/relative/path')`, relying
  /// on the client to resolve against the source's base. Null for the bare
  /// `Client()` that hand-written Foxtensions sources use (they pass absolute
  /// URLs).
  final String? baseUrl;
  _HttpClient({this.baseUrl});

  /// Resolve a possibly-relative URL against [baseUrl].
  String _resolve(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    final b = baseUrl;
    if (b == null || b.isEmpty) return url;
    try {
      return Uri.parse(b).resolve(url).toString();
    } catch (_) {
      return url.startsWith('/') ? '$b$url' : '$b/$url';
    }
  }

  Future<rhttp.RhttpClient> _getClient() async {
    if (_client != null) return _client!;
    // TLS verification MUST stay on: _buildHeaders attaches the user's stored
    // cookies (including the HttpOnly cf_clearance lifted from the WebView), so
    // an accepted forged cert would hand a network MITM the user's cleared
    // Cloudflare session and let it inject arbitrary source content. The JS
    // bridge's Dio client verifies; this one must match.
    _client = await rhttp.RhttpClient.create(
      settings: const rhttp.ClientSettings(
        throwOnStatusCode: false,
      ),
    );
    return _client!;
  }

  Future<Map<String, String>> _buildHeaders(
      String url, Map<String, String> headers) async {
    final merged = Map<String, String>.from(headers);
    final cookieHeader = await CookieStore().getCookieHeader(url);
    if (cookieHeader != null) {
      merged['Cookie'] = cookieHeader;
    }
    // Honours per-source desktop mode; otherwise the stored/platform UA.
    final ua = await CookieStore().userAgentFor(url);
    merged.putIfAbsent('User-Agent', () => ua);
    return merged;
  }

  // Returns true only if the 403 response looks like a Cloudflare challenge.
  // Plain 403s (WAF blocks, auth-required pages) should not trigger WebView.
  bool _isCloudflare(String body, Map<String, String> headers) {
    final lcHeaders = headers.map((k, v) => MapEntry(k.toLowerCase(), v.toLowerCase()));
    if (lcHeaders.containsKey('cf-ray')) return true;
    if ((lcHeaders['server'] ?? '').contains('cloudflare')) return true;
    final b = body.toLowerCase();
    return b.contains('__cf_') ||
        b.contains('cf-ray') ||
        b.contains('cf_clearance') ||
        b.contains('just a moment') ||
        b.contains('checking your browser') ||
        (b.contains('cloudflare') && b.contains('challenge'));
  }

  Future<_HttpResponse> get(String url,
      {Map<String, String> headers = const {}}) async {
    final mergedHeaders = await _buildHeaders(url, headers);
    try {
      final client = await _getClient();
      final response = await client.requestText(
        method: rhttp.HttpMethod.get,
        url: url,
        headers: rhttp.HttpHeaders.rawMap(mergedHeaders),
      );
      debugPrint('[HTTP] GET $url → ${response.statusCode} (${response.body.length} bytes)');
      if (response.statusCode == 403) {
        if (!_isCloudflare(response.body, response.headerMap)) {
          debugPrint('[HTTP] 403 for $url — not Cloudflare, returning as-is');
          return _HttpResponse(body: response.body, statusCode: 403, headers: response.headerMap);
        }
        return await _handleCloudflare(url, headers, 'GET');
      }
      return _HttpResponse(
        body: response.body,
        statusCode: response.statusCode,
        headers: response.headerMap,
      );
    } catch (e) {
      // Fallback to Dart HttpClient on rhttp connection errors (DNS issues on Windows)
      if (e.toString().contains('ConnectError') || e.toString().contains('dns error')) {
        debugPrint('[HTTP] rhttp failed, falling back to Dart HttpClient for $url');
        return await _dartGet(url, mergedHeaders);
      }
      debugPrint('[HTTP] GET error for $url: $e');
      rethrow;
    }
  }

  /// Returns the response body as a `List<int>` for binary endpoints. Used by
  /// sources that consume non-text payloads (e.g. Hitomi's .nozomi files).
  Future<List<int>> getBytes(String url,
      {Map<String, String> headers = const {}}) async {
    final mergedHeaders = await _buildHeaders(url, headers);
    try {
      final client = await _getClient();
      final response = await client.requestBytes(
        method: rhttp.HttpMethod.get,
        url: url,
        headers: rhttp.HttpHeaders.rawMap(mergedHeaders),
      );
      debugPrint(
          '[HTTP] GET (bytes) $url → ${response.statusCode} (${response.body.length} bytes)');
      // Convert Uint8List to List<int> so d4rt's bridge sees a plain List.
      return List<int>.from(response.body);
    } catch (e) {
      // Same fallback as `get()`: rhttp's DNS resolver fails on some Windows
      // configurations; fall back to Dart's HttpClient which uses the system
      // resolver.
      if (e.toString().contains('ConnectError') ||
          e.toString().contains('dns error')) {
        debugPrint(
            '[HTTP] rhttp (bytes) failed, falling back to Dart HttpClient for $url');
        return await _dartGetBytes(url, mergedHeaders);
      }
      debugPrint('[HTTP] GET (bytes) error for $url: $e');
      rethrow;
    }
  }

  /// Bytes-mode fallback using Dart's built-in HttpClient. Drains the
  /// response stream into a single `List<int>` without any text decoding.
  Future<List<int>> _dartGetBytes(
      String url, Map<String, String> headers) async {
    // No badCertificateCallback override — a bad cert must fail, not be
    // accepted (this request carries the user's session cookies).
    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(Uri.parse(url));
      headers.forEach((k, v) => request.headers.set(k, v));
      final response = await request.close();
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      debugPrint(
          '[HTTP] Dart GET (bytes) $url → ${response.statusCode} (${bytes.length} bytes)');
      return List<int>.from(bytes);
    } finally {
      httpClient.close();
    }
  }

  /// Fallback GET using Dart's built-in HttpClient (for when rhttp DNS fails)
  Future<_HttpResponse> _dartGet(String url, Map<String, String> headers) async {
    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(Uri.parse(url));
      headers.forEach((k, v) => request.headers.set(k, v));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final headerMap = <String, String>{};
      response.headers.forEach((name, values) => headerMap[name] = values.join(', '));
      debugPrint('[HTTP] Dart GET $url → ${response.statusCode} (${body.length} bytes)');
      if (response.statusCode == 403) {
        if (!_isCloudflare(body, headerMap)) {
          return _HttpResponse(body: body, statusCode: 403, headers: headerMap);
        }
        return await _handleCloudflare(url, {}, 'GET');
      }
      return _HttpResponse(body: body, statusCode: response.statusCode, headers: headerMap);
    } finally {
      httpClient.close();
    }
  }

  Future<_HttpResponse> post(String url,
      {Map<String, String> headers = const {}, dynamic body}) async {
    final mergedHeaders = await _buildHeaders(url, headers);
    try {
      final client = await _getClient();
      final response = await client.requestText(
        method: rhttp.HttpMethod.post,
        url: url,
        headers: rhttp.HttpHeaders.rawMap(mergedHeaders),
        body: body is String ? rhttp.HttpBody.text(body) : null,
      );
      if (response.statusCode == 403) {
        return await _handleCloudflare(url, headers, 'POST', body: body);
      }
      return _HttpResponse(
        body: response.body,
        statusCode: response.statusCode,
        headers: response.headerMap,
      );
    } catch (e) {
      debugPrint('[HTTP] POST error for $url: $e');
      rethrow;
    }
  }

  // Lock to prevent concurrent Cloudflare resolutions for the same domain
  static final Map<String, Future<bool>> _cfLocks = {};

  /// Handle Cloudflare 403: use cached cookies if fresh, otherwise resolve.
  Future<_HttpResponse> _handleCloudflare(
    String url,
    Map<String, String> originalHeaders,
    String method, {
    dynamic body,
  }) async {
    // On Windows, WebView can't extract HttpOnly cookies — skip all WebView steps.
    // Try once with cached cookies; if still blocked, fail fast with a clear message.
    if (Platform.isWindows) {
      debugPrint('[HTTP] 403 CF on Windows for $url — trying cached cookies only');
      final mergedHeaders = await _buildHeaders(url, originalHeaders);
      try {
        final client = await _getClient();
        final response = await client.requestText(
          method: method == 'POST' ? rhttp.HttpMethod.post : rhttp.HttpMethod.get,
          url: url,
          headers: rhttp.HttpHeaders.rawMap(mergedHeaders),
          body: method == 'POST' && body is String ? rhttp.HttpBody.text(body) : null,
        );
        if (response.statusCode != 403) {
          return _HttpResponse(body: response.body, statusCode: response.statusCode, headers: response.headerMap);
        }
      } catch (_) {}
      throw Exception('This source is Cloudflare-protected and requires Android or iOS to access.');
    }

    // In background isolate, can't spawn WebView — just retry with cookies or throw
    if (isBackgroundIsolate) {
      debugPrint('[HTTP] 403 in isolate for $url — retrying with cached cookies only');
      final mergedHeaders = await _buildHeaders(url, originalHeaders);
      final client = await _getClient();
      final response = await client.requestText(
        method: method == 'POST' ? rhttp.HttpMethod.post : rhttp.HttpMethod.get,
        url: url,
        headers: rhttp.HttpHeaders.rawMap(mergedHeaders),
        body: method == 'POST' && body is String ? rhttp.HttpBody.text(body) : null,
      );
      if (response.statusCode != 403) {
        return _HttpResponse(body: response.body, statusCode: response.statusCode, headers: response.headerMap);
      }
      throw Exception('Cloudflare 403 in isolate — needs main thread WebView resolution');
    }

    final cookieStore = CookieStore();
    final domain = Uri.parse(url).host;

    // Step 1: If we have fresh cookies (resolved <30 min ago), retry with rhttp only
    // Don't spawn WebView — just use the cached cookies
    if (cookieStore.hasFreshCookies(url)) {
      debugPrint('[HTTP] 403 for $url — retrying with fresh cached cookies (no WebView)');
      final mergedHeaders = await _buildHeaders(url, originalHeaders);
      try {
        final client = await _getClient();
        final response = await client.requestText(
          method: method == 'POST' ? rhttp.HttpMethod.post : rhttp.HttpMethod.get,
          url: url,
          headers: rhttp.HttpHeaders.rawMap(mergedHeaders),
          body: method == 'POST' && body is String ? rhttp.HttpBody.text(body) : null,
        );
        if (response.statusCode != 403) {
          debugPrint('[HTTP] Cached cookie retry succeeded! Status: ${response.statusCode}');
          return _HttpResponse(body: response.body, statusCode: response.statusCode, headers: response.headerMap);
        }
      } catch (e) {
        debugPrint('[HTTP] Cached cookie retry failed: $e');
      }
      // Cookies are stale despite being "fresh" — clear and fall through to full resolution
      debugPrint('[HTTP] Fresh cookies rejected — clearing and re-resolving');
    }

    // Step 2: Need to resolve Cloudflare — but prevent concurrent resolutions
    debugPrint('[HTTP] 403 for $url — resolving Cloudflare...');

    // Wait if another resolution is already in progress for this domain
    if (_cfLocks.containsKey(domain)) {
      debugPrint('[HTTP] Waiting for existing CF resolution for $domain...');
      await _cfLocks[domain];
      // After waiting, retry with the new cookies
      final mergedHeaders = await _buildHeaders(url, originalHeaders);
      try {
        final client = await _getClient();
        final response = await client.requestText(
          method: method == 'POST' ? rhttp.HttpMethod.post : rhttp.HttpMethod.get,
          url: url,
          headers: rhttp.HttpHeaders.rawMap(mergedHeaders),
          body: method == 'POST' && body is String ? rhttp.HttpBody.text(body) : null,
        );
        if (response.statusCode != 403) {
          return _HttpResponse(body: response.body, statusCode: response.statusCode, headers: response.headerMap);
        }
      } catch (_) {}
    }

    // Step 3: Resolve Cloudflare with WebView (locked per domain)
    final completer = Completer<bool>();
    _cfLocks[domain] = completer.future;

    try {
      final webViewService = WebViewService();
      final resolved = await webViewService.resolveCloudflare(url);

      if (resolved) {
        cookieStore.markResolved(url);

        // Retry with rhttp + new cookies
        final mergedHeaders = await _buildHeaders(url, originalHeaders);
        debugPrint('[HTTP] Retrying with rhttp + cookies (${mergedHeaders['Cookie']?.length ?? 0} chars)');
        try {
          final client = await _getClient();
          final response = await client.requestText(
            method: method == 'POST' ? rhttp.HttpMethod.post : rhttp.HttpMethod.get,
            url: url,
            headers: rhttp.HttpHeaders.rawMap(mergedHeaders),
            body: method == 'POST' && body is String ? rhttp.HttpBody.text(body) : null,
          );
          if (response.statusCode != 403) {
            debugPrint('[HTTP] rhttp retry succeeded! Status: ${response.statusCode}');
            completer.complete(true);
            _cfLocks.remove(domain);
            return _HttpResponse(body: response.body, statusCode: response.statusCode, headers: response.headerMap);
          }
        } catch (e) {
          debugPrint('[HTTP] rhttp retry failed: $e');
        }
      }

      // Fall back to WebView HTML fetch (internally re-runs resolveCloudflare if needed)
      debugPrint('[HTTP] Falling back to WebView HTML fetch...');
      final html = await webViewService.fetchHtml(url);
      completer.complete(true);
      _cfLocks.remove(domain);
      if (html != null && html.isNotEmpty) {
        return _HttpResponse(body: html, statusCode: 200, headers: {});
      }

      // fetchHtml may have extracted fresh cookies even if it returned null —
      // do one final rhttp retry before giving up.
      debugPrint('[HTTP] fetchHtml returned null — final rhttp retry with fresh cookies...');
      try {
        final retryHeaders = await _buildHeaders(url, originalHeaders);
        final client = await _getClient();
        final response = await client.requestText(
          method: method == 'POST' ? rhttp.HttpMethod.post : rhttp.HttpMethod.get,
          url: url,
          headers: rhttp.HttpHeaders.rawMap(retryHeaders),
          body: method == 'POST' && body is String ? rhttp.HttpBody.text(body) : null,
        );
        debugPrint('[HTTP] Final retry → ${response.statusCode} (${response.body.length} bytes)');
        if (response.statusCode != 403) {
          return _HttpResponse(body: response.body, statusCode: response.statusCode, headers: response.headerMap);
        }
      } catch (e) {
        debugPrint('[HTTP] Final rhttp retry failed: $e');
      }
    } catch (e) {
      completer.complete(false);
      _cfLocks.remove(domain);
      debugPrint('[HTTP] Cloudflare resolution error: $e');
    }

    throw Exception('Cloudflare challenge failed for $url');
  }
}

class _HttpResponse {
  final String body;
  final int statusCode;
  final Map<String, String> headers;

  _HttpResponse({
    required this.body,
    required this.statusCode,
    required this.headers,
  });
}

class HttpResponseBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: _HttpResponse,
      name: 'Response',
      constructors: {},
      methods: {},
      getters: {
        'body': (visitor, instance) => (instance as _HttpResponse).body,
        'statusCode': (visitor, instance) =>
            (instance as _HttpResponse).statusCode,
        'headers': (visitor, instance) => (instance as _HttpResponse).headers,
      },
      setters: {},
    );
  }
}
