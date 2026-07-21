import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:html/parser.dart' as html_parser;

/// Fetches page HTML for the Scraping Studio's live selector testing and counts
/// CSS-selector matches. Mirrors the detector's fetch strategy: a headless
/// WebView (JS/Cloudflare-capable) with a plain-HTTP fallback.
class RepoForgeFetcher {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers: const {'User-Agent': _ua},
  ));

  /// Fetch rendered HTML for [url]. Prefers the WebView (handles JS/Cloudflare);
  /// falls back to a raw GET. Returns '' if both fail.
  static Future<String> fetchHtml(String url) async {
    final viaWeb = await _fetchViaWebView(url);
    if (viaWeb.trim().length > 200) return viaWeb;
    try {
      final res = await _dio.get<String>(url);
      final body = res.data ?? '';
      return body.length > viaWeb.length ? body : viaWeb;
    } catch (_) {
      return viaWeb;
    }
  }

  static Future<String> _fetchViaWebView(String url) async {
    final completer = Completer<String>();
    HeadlessInAppWebView? web;
    final timeout = Timer(const Duration(seconds: 20), () {
      if (!completer.isCompleted) completer.complete('');
    });
    try {
      web = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          userAgent: _ua,
          blockNetworkImage: true,
          loadsImagesAutomatically: false,
        ),
        onLoadStop: (controller, loadedUrl) async {
          if (completer.isCompleted) return;
          try {
            // Let JS finish rendering after load.
            await Future.delayed(const Duration(milliseconds: 800));
            final r = await controller.evaluateJavascript(
                source: 'document.documentElement.outerHTML');
            timeout.cancel();
            completer.complete(r?.toString() ?? '');
          } catch (_) {
            if (!completer.isCompleted) completer.complete('');
          }
        },
        onReceivedError: (controller, request, error) {
          if (!completer.isCompleted) completer.complete('');
        },
      );
      await web.run();
      return await completer.future;
    } catch (_) {
      return '';
    } finally {
      timeout.cancel();
      try {
        await web?.dispose();
      } catch (_) {}
    }
  }

  /// Count elements matching [selector] in [html]. Returns -1 if the selector
  /// is invalid (so the UI can distinguish "0 matches" from "bad selector").
  static int countMatches(String html, String selector) {
    if (selector.trim().isEmpty) return 0;
    if (html.isEmpty) return 0;
    try {
      return html_parser.parse(html).querySelectorAll(selector).length;
    } catch (_) {
      return -1;
    }
  }
}
