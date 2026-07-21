import 'package:d4rt/d4rt.dart';
import '../../../core/services/webview_service.dart';

/// Bridges WebView capabilities (captureRequest, fetchHtml) for extensions.
/// Extensions can use this to extract dynamically-loaded video URLs.
class WebViewBridge {
  static BridgedClass get bridgedClass {
    return BridgedClass(
      nativeType: _ExtWebView,
      name: 'WebView',
      constructors: {
        '': (visitor, positionalArgs, namedArgs) => _ExtWebView(),
      },
      methods: {
        /// Loads [url] in a headless WebView and returns the first outgoing
        /// XHR/fetch request URL whose path contains [pattern].
        /// Useful for capturing dynamically-loaded HLS manifest URLs.
        'captureRequest': (visitor, instance, positionalArgs, namedArgs) async {
          final url = positionalArgs[0] as String;
          final pattern = positionalArgs[1] as String;
          final timeout = (namedArgs['timeout'] as int?) ?? 15;
          return await WebViewService().captureRequest(url, pattern,
              timeoutSeconds: timeout);
        },

        /// Fetches the fully-rendered HTML of [url] via a headless WebView,
        /// including Cloudflare bypass. Returns null on failure.
        'fetchHtml': (visitor, instance, positionalArgs, namedArgs) async {
          final url = positionalArgs[0] as String;
          return await WebViewService().fetchHtml(url);
        },
      },
      getters: {},
      setters: {},
    );
  }
}

class _ExtWebView {}
