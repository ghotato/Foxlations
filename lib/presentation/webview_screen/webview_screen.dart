import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/cookie_store.dart';
import '../../core/services/webview_service.dart';
import '../../core/utils/adblock.dart';

class WebViewScreen extends StatefulWidget {
  final String url;
  final String title;
  final bool cloudflareMode;

  const WebViewScreen({
    super.key,
    required this.url,
    required this.title,
    this.cloudflareMode = false,
  });

  /// Preference key for adblock toggle.
  static const adBlockKey = 'webview_adblock_enabled';

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  bool _adBlockEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadAdBlockPref();
  }

  Future<void> _loadAdBlockPref() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _adBlockEnabled = prefs.getBool(WebViewScreen.adBlockKey) ?? true;
    });
  }

  Future<void> _injectAdBlock(InAppWebViewController controller) async {
    if (_adBlockEnabled) {
      await controller.evaluateJavascript(source: adBlockScript);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => _controller?.goBack(),
            tooltip: 'Back',
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_rounded),
            onPressed: () => _controller?.goForward(),
            tooltip: 'Forward',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller?.reload(),
            tooltip: 'Reload',
          ),
          if (widget.cloudflareMode)
            IconButton(
              icon: const Icon(Icons.check_circle),
              onPressed: _extractCookiesAndClose,
              tooltip: 'Done — save cookies',
            ),
        ],
        bottom: _isLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      body: InAppWebView(
        webViewEnvironment: webViewEnvironment,
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
        ),
        onWebViewCreated: (controller) => _controller = controller,
        onLoadStart: (_, __) {
          if (mounted) setState(() => _isLoading = true);
        },
        onLoadStop: (controller, url) async {
          if (mounted) setState(() => _isLoading = false);
          // Inject adblock script
          await _injectAdBlock(controller);
          // Extract cookies on every page load
          if (url != null) {
            final cookies = await CookieManager.instance(webViewEnvironment: webViewEnvironment).getCookies(
              url: WebUri(url.toString()),
              webViewController: controller,
            );
            if (cookies.isNotEmpty) {
              final domain = url.host;
              final cookieMap = <String, String>{};
              for (final c in cookies) {
                cookieMap[c.name] = c.value.toString();
              }
              await CookieStore().setCookies(domain, cookieMap);
            }
          }
        },
      ),
    );
  }

  Future<void> _extractCookiesAndClose() async {
    if (_controller != null) {
      final url = await _controller!.getUrl();
      if (url != null) {
        final domain = url.host;
        final cookies = await CookieManager.instance(webViewEnvironment: webViewEnvironment).getCookies(
          url: WebUri(url.toString()),
          webViewController: _controller,
        );
        if (cookies.isNotEmpty) {
          final cookieMap = <String, String>{};
          for (final c in cookies) {
            cookieMap[c.name] = c.value.toString();
          }
          await CookieStore().setCookies(domain, cookieMap);
          // Also store for normalized domain
          final normalized = WebViewService().normalizeDomain(domain);
          if (normalized != domain) {
            await CookieStore().setCookies(normalized, cookieMap);
          }
        }
      }
    }
    if (mounted) Navigator.pop(context, true);
  }
}
