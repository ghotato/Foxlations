import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_js/flutter_js.dart';
import '../../core/services/cookie_store.dart';
import '../../core/services/webview_service.dart';
import '../../presentation/webview_screen/cf_challenge_screen.dart';
import '../dart/bridge/http.dart' show isBackgroundIsolate;

/// Injects HTTP client functions into the JS runtime.
class JsHttpClient {
  final JavascriptRuntime _runtime;

  JsHttpClient(this._runtime);

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'User-Agent': CookieStore.defaultUserAgent,
    },
  ));

  static final CookieStore _cookies = CookieStore();

  /// True if the response looks like a Cloudflare challenge (needs solving).
  static bool _isChallenge(int status, String body) {
    if (status == 403 || status == 503) return true;
    if (body.isEmpty || body.length > 60000) return false;
    final b = body.toLowerCase();
    return b.contains('just a moment') ||
        b.contains('challenge-platform') ||
        b.contains('cf-browser-verification') ||
        b.contains('_cf_chl_opt') ||
        b.contains('enable javascript and cookies to continue');
  }

  /// Merge stored Cloudflare cookies + the resolved User-Agent into [headers].
  static Future<Map<String, String>> _buildHeaders(
      String url, Map<String, String> headers) async {
    final h = Map<String, String>.from(headers);
    h['User-Agent'] = await _cookies.getUserAgent();
    final cookie = await _cookies.getCookieHeader(url);
    if (cookie != null && cookie.isNotEmpty) {
      h['Cookie'] = h['Cookie'] != null && h['Cookie']!.isNotEmpty
          ? '${h['Cookie']}; $cookie'
          : cookie;
    }
    return h;
  }

  /// A Cloudflare-aware fetch: attaches cookies, and on a challenge, solves it
  /// (headless, else interactive WebView) and retries — persisting cookies so
  /// the challenge isn't re-shown next time.
  static Future<String> _cfAwareFetch(
      String method, String url, Map<String, String> headers,
      [String? body]) async {
    Future<Response<String>> doRequest() async {
      final opts = Options(
        headers: await _buildHeaders(url, headers),
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      );
      return method == 'POST'
          ? _dio.post<String>(url, data: body, options: opts)
          : _dio.get<String>(url, options: opts);
    }

    String encode(Response<String> r) => jsonEncode({
          'statusCode': r.statusCode,
          'body': r.data ?? '',
          'headers':
              r.headers.map.map((k, v) => MapEntry(k, v.join(', '))),
        });

    Response<String> resp;
    try {
      resp = await doRequest();
    } catch (e) {
      return jsonEncode({'statusCode': 0, 'body': '', 'error': e.toString()});
    }

    if (!_isChallenge(resp.statusCode ?? 0, resp.data ?? '')) {
      return encode(resp);
    }

    // Cloudflare challenge — solve headless first, then retry.
    //
    // A background isolate can't drive a WebView: `rootNavigatorKey` is a
    // different, null instance there, so the interactive fallback always
    // returns false and the headless attempt just burns its 30s timeout before
    // failing anyway. The Dart bridge guards this the same way — bail out and
    // let the caller retry on the main isolate.
    if (isBackgroundIsolate) {
      return encode(resp);
    }

    var resolved = await WebViewService().resolveCloudflare(url);
    // If the headless solve couldn't clear it (interactive Turnstile / captcha),
    // ask the user to complete it in a visible WebView.
    if (!resolved) {
      resolved = await solveCloudflareInteractively(url);
    }
    if (resolved) {
      _cookies.markResolved(url);
      try {
        final retry = await doRequest();
        if (!_isChallenge(retry.statusCode ?? 0, retry.data ?? '')) {
          return encode(retry);
        }
      } catch (_) {}
    }
    // GET fallback: let the WebView return the rendered HTML directly.
    if (method == 'GET') {
      final html = await WebViewService().fetchHtml(url);
      if (html != null && html.isNotEmpty) {
        return jsonEncode({'statusCode': 200, 'body': html, 'headers': {}});
      }
    }
    return encode(resp);
  }

  void init() {
    // Register the HTTP bridge channel
    _runtime.onMessage('HttpGet', (dynamic args) async {
      final url = args['url'] as String;
      final headers = (args['headers'] as Map?)?.cast<String, String>() ?? {};
      return _cfAwareFetch('GET', url, headers);
    });

    _runtime.onMessage('HttpPost', (dynamic args) async {
      final url = args['url'] as String;
      final headers = (args['headers'] as Map?)?.cast<String, String>() ?? {};
      final body = args['body'] as String?;
      return _cfAwareFetch('POST', url, headers, body);
    });

    // Inject JS Client class
    _runtime.evaluate('''
class Client {
  constructor() {}

  async get(url, headers) {
    const result = await sendMessage('HttpGet', JSON.stringify({
      url: url,
      headers: headers || {}
    }));
    return JSON.parse(result);
  }

  async post(url, headers, body) {
    const result = await sendMessage('HttpPost', JSON.stringify({
      url: url,
      headers: headers || {},
      body: body || ''
    }));
    return JSON.parse(result);
  }
}
''');
  }
}
