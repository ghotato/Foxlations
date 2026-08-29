import 'dart:async';
import 'dart:convert';
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
    // WebView2 on Windows can't extract HttpOnly cf_clearance cookies and
    // crashes with modern Cloudflare Turnstile challenges. Skip on Windows.
    if (Platform.isWindows) {
      debugPrint('[WebView] Skipping CF resolution on Windows (HttpOnly cookies unsupported)');
      return false;
    }

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
          // Check if still on Cloudflare challenge page.
          // CF challenge pages have title "Just a moment..." or similar.
          Future<bool> isCfChallenge() async {
            try {
              final title = await controller.evaluateJavascript(
                    source: "document.title",
                  ) ??
                  '';
              final titleStr = title.toString().toLowerCase();
              if (titleStr.contains('just a moment') ||
                  titleStr.contains('checking your browser') ||
                  titleStr.contains('please wait')) {
                return true;
              }
              // Also check for CF challenge elements
              final hasCfEl = await controller.evaluateJavascript(
                    source:
                        "!!(document.getElementById('challenge-form') || "
                        "document.getElementById('cf-please-wait') || "
                        "document.querySelector('[class*=\"cf-\"]'))",
                  ) ??
                  false;
              return hasCfEl == true;
            } catch (_) {
              return false;
            }
          }

          isCloudflare = await isCfChallenge();

          // Poll until challenge is resolved
          while (isCloudflare && !timedOut) {
            await Future.delayed(const Duration(milliseconds: 500));
            isCloudflare = await isCfChallenge();
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
        timedOut = elapsed >= 30;
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

  /// Public entry for the interactive challenge screen: once the user has
  /// solved a challenge in a visible WebView, pull its cookies + User-Agent and
  /// mark the domain cleared so subsequent requests carry cf_clearance.
  Future<void> storeCookiesFrom(
      String url, InAppWebViewController controller) async {
    final ua =
        (await controller.evaluateJavascript(source: 'navigator.userAgent'))
                ?.toString() ??
            '';
    await _extractAndStoreCookies(url, ua, controller);
    if (ua.isNotEmpty) await CookieStore().setUserAgent(ua);
    _cleared.add(normalizeDomain(Uri.parse(url).host));
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
    if (Platform.isWindows) {
      debugPrint('[WebView] fetchHtml skipped on Windows');
      return null;
    }
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
    if (Platform.isWindows) {
      debugPrint('[WebView] captureRequest skipped on Windows');
      return null;
    }
    debugPrint('[WebView] captureRequest: loading $url, watching for "$pattern"');
    HeadlessInAppWebView? webView;
    String? captured;
    bool done = false;

    // JS that captures matching URLs from XHR, fetch, and <video src> changes.
    // The pattern is an extension-supplied string; injecting it raw into the JS
    // string literals below let a pattern containing a quote break out of the
    // script and run in the page. Define it once as a JSON-encoded constant and
    // reference the variable instead.
    const captureJs = '''
      (function() {
        if (window.__vrfCaptured) return;
        window.__vrfCaptured = '';
        var __PAT = __PATJSON__;

        function _capture(u) {
          if (!u || window.__vrfCaptured) return;
          var s = u.toString();
          if (s.indexOf(__PAT) === -1) return;
          if (!s.startsWith('http')) s = window.location.origin + s;
          window.__vrfCaptured = s;
        }

        // 1. XHR intercept
        var origOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
          _capture(url);
          return origOpen.apply(this, arguments);
        };

        // 2. fetch intercept
        var origFetch = window.fetch;
        window.fetch = function(url, opts) {
          var s = (typeof url === 'string') ? url : (url && url.url ? url.url : '');
          _capture(s);
          return origFetch.apply(this, arguments);
        };

        // 3. Check any existing <video> or <source> elements right now
        function _checkVideoEls() {
          document.querySelectorAll('video[src], video > source[src]').forEach(function(el) {
            _capture(el.src || el.getAttribute('src'));
          });
        }
        _checkVideoEls();

        // 4. MutationObserver to catch dynamically added/changed video src
        var obs = new MutationObserver(function(mutations) {
          _checkVideoEls();
          mutations.forEach(function(m) {
            if (m.type === 'attributes' && m.attributeName === 'src') {
              _capture(m.target.src || m.target.getAttribute('src'));
            }
          });
        });
        obs.observe(document.documentElement, {
          subtree: true,
          childList: true,
          attributes: true,
          attributeFilter: ['src'],
        });
      })();
    ''';

    try {
      final ua = await CookieStore().getUserAgent();
      // jsonEncode gives a safe, fully-escaped JS string literal for the var.
      final jsToInject =
          captureJs.replaceAll('__PATJSON__', jsonEncode(pattern));

      webView = HeadlessInAppWebView(
        webViewEnvironment: webViewEnvironment,
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          userAgent: ua,
        ),
        onWebViewCreated: (controller) {
          // Inject into ALL frames (including iframes) as early as possible.
          // Many video players embed in an iframe — forMainFrameOnly: false ensures
          // the XHR/fetch intercept fires inside the player iframe too.
          controller.addUserScript(userScript: UserScript(
            source: jsToInject,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            forMainFrameOnly: false,
          ));
        },
        onLoadStop: (controller, loadedUrl) async {
          // Re-inject in case it didn't take
          await controller.evaluateJavascript(source: jsToInject);
          await _extractAndStoreCookies(
              loadedUrl?.toString() ?? url, '', controller);
          // Trigger video playback so the player actually fetches the stream.
          // Many players require a user gesture; muting + play() bypasses that.
          await controller.evaluateJavascript(source: '''
            (function() {
              document.querySelectorAll('video').forEach(function(v) {
                v.muted = true;
                try { v.play(); } catch(e) {}
              });
              // Also click common play-button selectors
              var selectors = [
                '.play-btn', '[class*="play-btn"]', '.vjs-play-button',
                '.plyr__control--play', '[data-plyr="play"]',
                '.jw-icon-display', '.fp-play', '.mejs__play button',
              ];
              for (var i = 0; i < selectors.length; i++) {
                var btn = document.querySelector(selectors[i]);
                if (btn) { btn.click(); break; }
              }
            })();
          ''');
        },
      );

      await webView.run();

      // Poll for the captured URL; also check video.currentSrc each tick
      for (var i = 0; i < timeoutSeconds * 4 && !done; i++) {
        await Future.delayed(const Duration(milliseconds: 250));
        try {
          // Check both our hooked __vrfCaptured and video.currentSrc directly
          final result = await webView!.webViewController?.evaluateJavascript(
              source: '''
                (function() {
                  if (window.__vrfCaptured) return window.__vrfCaptured;
                  var __PAT = __PATJSON__;
                  // Also try reading currentSrc from any video element
                  var vids = document.querySelectorAll('video');
                  for (var i = 0; i < vids.length; i++) {
                    var cs = vids[i].currentSrc || vids[i].src;
                    if (cs && cs.indexOf(__PAT) !== -1 && !cs.startsWith('blob:')) return cs;
                  }
                  return '';
                })()
              '''.replaceAll('__PATJSON__', jsonEncode(pattern)));
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
