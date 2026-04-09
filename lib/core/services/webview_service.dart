import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'cookie_store.dart';
import 'image_loader.dart';

/// Global WebViewEnvironment for Windows (must be initialized before use).
WebViewEnvironment? webViewEnvironment;

/// Initialize WebViewEnvironment for Windows desktop.
/// Call this once from main() before runApp().
Future<void> initWebViewEnvironment() async {
  if (!Platform.isWindows) return;
  try {
    final availableVersion = await WebViewEnvironment.getAvailableVersion();
    if (availableVersion != null) {
      final document = await getApplicationDocumentsDirectory();
      final userDataFolder = '${document.path}/manga_reader_webview';
      webViewEnvironment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: userDataFolder,
        ),
      );
      debugPrint('[WebView] Environment initialized (WebView2 $availableVersion)');
    }
  } catch (e) {
    debugPrint('[WebView] Failed to init environment: $e');
  }
}

/// Manages Cloudflare bypass using flutter_inappwebview.
///
/// Strategy:
/// 1. Detect 403 from Cloudflare
/// 2. Open headless InAppWebView to solve challenge
/// 3. Extract ALL cookies (including HttpOnly cf_clearance) via CookieManager
/// 4. Store cookies in CookieStore
/// 5. Retry original request with cookies → success
class WebViewService {
  static final WebViewService _instance = WebViewService._();
  factory WebViewService() => _instance;
  WebViewService._();

  final Set<String> _cleared = {};

  String normalizeDomain(String domain) =>
      domain.startsWith('www.') ? domain.substring(4) : domain;

  bool isCleared(String domain) => _cleared.contains(normalizeDomain(domain));

  /// Resolve Cloudflare challenge for a URL.
  /// Returns true if challenge was solved and cookies extracted.
  Future<bool> resolveCloudflare(String url) async {
    final domain = normalizeDomain(Uri.parse(url).host);

    if (_cleared.contains(domain)) return true;

    debugPrint('[WebView] Resolving Cloudflare for $url');

    HeadlessInAppWebView? headlessWebView;
    bool isCloudflare = true;
    bool timedOut = false;
    int elapsed = 0;
    final completer = Completer<bool>();

    try {
      headlessWebView = HeadlessInAppWebView(
        webViewEnvironment: webViewEnvironment,
        initialUrlRequest: URLRequest(url: WebUri(url)),
        onLoadStop: (controller, loadedUrl) async {
          // Check if still on Cloudflare challenge page
          try {
            isCloudflare = await controller.evaluateJavascript(
                  source:
                      "document.head.innerHTML.includes('#challenge-success-text')",
                ) ??
                false;
          } catch (_) {
            isCloudflare = false;
          }

          // Poll until challenge is resolved
          while (isCloudflare && !timedOut) {
            await Future.delayed(const Duration(milliseconds: 300));
            try {
              isCloudflare = await controller.evaluateJavascript(
                    source:
                        "document.head.innerHTML.includes('#challenge-success-text')",
                  ) ??
                  false;
            } catch (_) {
              isCloudflare = false;
            }
          }

          if (!timedOut && !isCloudflare) {
            // Challenge solved! Extract cookies via native CookieManager
            final ua = await controller.evaluateJavascript(
                    source: "navigator.userAgent") ??
                '';
            await _extractAndStoreCookies(
                loadedUrl?.toString() ?? url, ua, controller);
            // Store the WebView's User-Agent — Cloudflare requires matching UA
            if (ua is String && ua.isNotEmpty) {
              await CookieStore().setUserAgent(ua);
            }
            _cleared.add(domain);
            debugPrint('[WebView] Cloudflare cleared for $domain');
          }
        },
      );

      await headlessWebView.run();

      // Wait for resolution with timeout
      while (isCloudflare && !timedOut) {
        await Future.delayed(const Duration(seconds: 1));
        elapsed++;
        timedOut = elapsed >= 15;
      }

      try {
        await headlessWebView.dispose();
      } catch (_) {}

      final success = !isCloudflare && !timedOut;
      debugPrint(
          '[WebView] Cloudflare resolution ${success ? "succeeded" : "failed"} for $domain');
      return success;
    } catch (e) {
      debugPrint('[WebView] Cloudflare resolution error: $e');
      try {
        await headlessWebView?.dispose();
      } catch (_) {}
      return false;
    }
  }

  /// Extract ALL cookies (including HttpOnly like cf_clearance)
  /// using flutter_inappwebview's native CookieManager API.
  ///
  /// Also extracts cookies for CDN domains that were set during page load
  /// (e.g., 2xstorage.com cookies set when natomanga.com loads images).
  Future<void> _extractAndStoreCookies(
      String url, String ua, InAppWebViewController controller) async {
    try {
      final cookieManager = CookieManager.instance(
        webViewEnvironment: webViewEnvironment,
      );

      // 1. Extract cookies for the page URL
      final cookies = await cookieManager.getCookies(
        url: WebUri(url),
        webViewController: controller,
      );

      if (cookies.isNotEmpty) {
        // Group cookies by domain
        final cookiesByDomain = <String, Map<String, String>>{};
        for (final cookie in cookies) {
          final domain = cookie.domain?.replaceAll(RegExp(r'^\.'), '') ??
              Uri.parse(url).host;
          cookiesByDomain.putIfAbsent(domain, () => {});
          cookiesByDomain[domain]![cookie.name] = cookie.value.toString();
          debugPrint(
              '[WebView] Cookie: ${cookie.name}=${cookie.value.toString().substring(0, (cookie.value.toString().length).clamp(0, 30))}... '
              '(httpOnly: ${cookie.isHttpOnly}, domain: ${cookie.domain})');
        }

        // Store cookies per domain
        for (final entry in cookiesByDomain.entries) {
          await CookieStore().setCookies(entry.key, entry.value);
          final normalized = normalizeDomain(entry.key);
          if (normalized != entry.key) {
            await CookieStore().setCookies(normalized, entry.value);
          }
        }
        debugPrint('[WebView] Extracted ${cookies.length} cookies for ${cookiesByDomain.keys.join(", ")}');
      } else {
        debugPrint('[WebView] WARNING: No cookies extracted for $url');
      }

      // 2. Also extract cookies for known image CDN domains
      //    When the page loads images from CDN, Cloudflare sets cookies on the CDN domain
      await _extractCdnCookies(controller, cookieManager, url);


      // Store User-Agent for consistency
      if (ua.isNotEmpty) {
        debugPrint('[WebView] UA: ${ua.substring(0, ua.length.clamp(0, 80))}...');
      }
    } catch (e) {
      debugPrint('[WebView] Cookie extraction error: $e');
    }
  }

  /// Extract cookies for CDN domains that were set during page load.
  /// When natomanga.com loads images from 2xstorage.com, Cloudflare sets
  /// cookies on the CDN domain. We need those cookies for direct image requests.
  Future<void> _extractCdnCookies(
    InAppWebViewController controller,
    CookieManager cookieManager,
    String pageUrl,
  ) async {
    // Find all image/resource domains loaded by the page
    try {
      final domainsJson = await controller.evaluateJavascript(source: '''
        (function() {
          var domains = new Set();
          document.querySelectorAll('img[src]').forEach(function(img) {
            try {
              var u = new URL(img.src);
              if (u.host !== window.location.host) domains.add(u.origin);
            } catch(e) {}
          });
          return JSON.stringify(Array.from(domains));
        })()
      ''');

      if (domainsJson == null) return;
      var domainsStr = domainsJson.toString();
      if (domainsStr.startsWith('"')) {
        domainsStr = domainsStr.substring(1, domainsStr.length - 1);
        domainsStr = domainsStr.replaceAll('\\"', '"');
      }

      final domains = List<String>.from(
          domainsStr.startsWith('[') ?
          (domainsStr.split('"').where((s) => s.startsWith('http')).toList()) :
          <String>[]);

      for (final cdnOrigin in domains) {
        try {
          final cdnCookies = await cookieManager.getCookies(
            url: WebUri(cdnOrigin),
            webViewController: controller,
          );
          if (cdnCookies.isNotEmpty) {
            final cdnHost = Uri.parse(cdnOrigin).host;
            final cookieMap = <String, String>{};
            for (final c in cdnCookies) {
              cookieMap[c.name] = c.value.toString();
            }
            await CookieStore().setCookies(cdnHost, cookieMap);
            // Unblock this domain in ImageLoader so images retry
            ImageLoader().unblockDomains();
            debugPrint(
                '[WebView] CDN cookies: ${cdnCookies.length} for $cdnHost '
                '(${cdnCookies.map((c) => '${c.name}(httpOnly:${c.isHttpOnly})').join(", ")})');
          }
        } catch (e) {
          debugPrint('[WebView] CDN cookie extraction failed for $cdnOrigin: $e');
        }
      }
    } catch (e) {
      debugPrint('[WebView] CDN domain scan failed: $e');
    }
  }

  /// Fetch HTML content from a URL, handling Cloudflare automatically.
  /// Used by the HTTP bridge for page content.
  Future<String?> fetchHtml(String url) async {
    // Ensure Cloudflare is resolved first
    final domain = normalizeDomain(Uri.parse(url).host);
    if (!_cleared.contains(domain)) {
      await resolveCloudflare(url);
    }

    // Now fetch via a headless WebView
    HeadlessInAppWebView? webView;
    String? html;
    bool loaded = false;

    try {
      webView = HeadlessInAppWebView(
        webViewEnvironment: webViewEnvironment,
        initialUrlRequest: URLRequest(url: WebUri(url)),
        onLoadStop: (controller, loadedUrl) async {
          try {
            html = await controller.evaluateJavascript(
                source: "document.documentElement.outerHTML");
            // Also extract cookies on every page load
            await _extractAndStoreCookies(
                loadedUrl?.toString() ?? url, '', controller);
          } catch (_) {}
          loaded = true;
        },
      );

      await webView.run();

      // Wait for page to load
      for (var i = 0; i < 40 && !loaded; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
      }

      await webView.dispose();

      if (html != null) {
        debugPrint('[WebView] Fetched HTML: ${html!.length} chars');
      }
      return html;
    } catch (e) {
      debugPrint('[WebView] fetchHtml error: $e');
      try {
        await webView?.dispose();
      } catch (_) {}
      return null;
    }
  }

  /// Load a URL in WebView and capture the first outgoing AJAX request matching [pattern].
  /// Uses JS injection (XMLHttpRequest + fetch override) for cross-platform support.
  /// Returns the full captured URL string, or null on timeout.
  Future<String?> captureRequest(String url, String pattern, {int timeoutSeconds = 15}) async {
    debugPrint('[WebView] captureRequest: loading $url, watching for "$pattern"');
    HeadlessInAppWebView? webView;
    String? captured;
    bool done = false;

    // JS that overrides XMLHttpRequest.open and fetch to capture matching URLs
    const captureJs = '''
      (function() {
        if (window.__vrfCaptured) return;
        window.__vrfCaptured = '';
        var origOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
          if (url && url.toString().indexOf('PATTERN') !== -1 && !window.__vrfCaptured) {
            window.__vrfCaptured = url.toString();
            if (!window.__vrfCaptured.startsWith('http')) {
              window.__vrfCaptured = window.location.origin + window.__vrfCaptured;
            }
          }
          return origOpen.apply(this, arguments);
        };
        var origFetch = window.fetch;
        window.fetch = function(url, opts) {
          var s = (typeof url === 'string') ? url : (url && url.url ? url.url : '');
          if (s.indexOf('PATTERN') !== -1 && !window.__vrfCaptured) {
            window.__vrfCaptured = s;
            if (!window.__vrfCaptured.startsWith('http')) {
              window.__vrfCaptured = window.location.origin + window.__vrfCaptured;
            }
          }
          return origFetch.apply(this, arguments);
        };
      })();
    ''';

    try {
      final ua = await CookieStore().getUserAgent();
      final jsToInject = captureJs.replaceAll('PATTERN', pattern);

      webView = HeadlessInAppWebView(
        webViewEnvironment: webViewEnvironment,
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          userAgent: ua,
        ),
        onWebViewCreated: (controller) {
          // Inject capture script as early as possible
          controller.addUserScript(userScript: UserScript(
            source: jsToInject,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ));
        },
        onLoadStop: (controller, loadedUrl) async {
          // Re-inject in case it didn't take
          await controller.evaluateJavascript(source: jsToInject);
          await _extractAndStoreCookies(
              loadedUrl?.toString() ?? url, '', controller);
        },
      );

      await webView.run();

      // Poll for the captured URL
      for (var i = 0; i < timeoutSeconds * 4 && !done; i++) {
        await Future.delayed(const Duration(milliseconds: 250));
        try {
          final result = await webView!.webViewController?.evaluateJavascript(
              source: 'window.__vrfCaptured || ""');
          if (result != null && result.toString().isNotEmpty && result.toString() != '""' && result.toString() != 'null') {
            captured = result.toString();
            // Strip surrounding quotes if present
            if (captured!.startsWith('"') && captured!.endsWith('"')) {
              captured = captured!.substring(1, captured!.length - 1);
            }
            if (captured!.isNotEmpty) {
              done = true;
              debugPrint('[WebView] Captured: $captured');
            }
          }
        } catch (_) {}
      }

      try { await webView.dispose(); } catch (_) {}

      if (captured == null) {
        debugPrint('[WebView] captureRequest timed out after ${timeoutSeconds}s');
      }
      return captured;
    } catch (e) {
      debugPrint('[WebView] captureRequest error: $e');
      try { await webView?.dispose(); } catch (_) {}
      return null;
    }
  }

  bool get isSupported => Platform.isWindows || Platform.isAndroid || Platform.isIOS;
}
