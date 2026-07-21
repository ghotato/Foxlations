import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';

/// Opens an OAuth authorize URL in a WebView and captures the result:
///  - token/implicit flow (AniList): reads `#access_token=…` from the pin page.
///  - code/PKCE flow (MAL): intercepts the `foxlations://auth?code=…` redirect.
/// Pops with the captured token or code string, or null if the user backs out.
class TrackerOAuthScreen extends StatefulWidget {
  final String authorizeUrl;
  final String trackerName;
  final bool usesCode;
  final String redirectUri;

  const TrackerOAuthScreen({
    super.key,
    required this.authorizeUrl,
    required this.trackerName,
    this.usesCode = false,
    this.redirectUri = '',
  });

  @override
  State<TrackerOAuthScreen> createState() => _TrackerOAuthScreenState();
}

class _TrackerOAuthScreenState extends State<TrackerOAuthScreen> {
  bool _done = false;

  void _finish(String value) {
    if (_done) return;
    _done = true;
    if (mounted) Navigator.pop(context, value);
  }

  /// Code flow: watch for a navigation to the redirect URI carrying `?code=`.
  bool _captureCode(String url) {
    if (_done || !widget.usesCode || widget.redirectUri.isEmpty) return false;
    if (!url.startsWith(widget.redirectUri)) return false;
    final code = Uri.tryParse(url)?.queryParameters['code'];
    if (code != null && code.isNotEmpty) {
      _finish(code);
      return true;
    }
    return false;
  }

  /// Token flow: read the access token from the page fragment.
  Future<void> _captureToken(InAppWebViewController controller) async {
    if (_done || widget.usesCode) return;
    try {
      final hash =
          (await controller.evaluateJavascript(source: 'window.location.hash'))
                  ?.toString() ??
              '';
      final m = RegExp(r'access_token=([^&]+)').firstMatch(hash);
      if (m != null) _finish(Uri.decodeComponent(m.group(1)!));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Connect ${widget.trackerName}',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: cs.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            'Log in and press Authorize. You’ll be signed in automatically.',
            style: GoogleFonts.manrope(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.authorizeUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              clearCache: false,
              useShouldOverrideUrlLoading: true,
            ),
            shouldOverrideUrlLoading: (controller, action) async {
              final url = action.request.url?.toString() ?? '';
              return _captureCode(url)
                  ? NavigationActionPolicy.CANCEL
                  : NavigationActionPolicy.ALLOW;
            },
            onLoadStart: (controller, url) {
              _captureCode(url?.toString() ?? '');
            },
            onLoadStop: (controller, url) async {
              await _captureToken(controller);
            },
            onUpdateVisitedHistory: (controller, url, __) async {
              if (!_captureCode(url?.toString() ?? '')) {
                await _captureToken(controller);
              }
            },
          ),
        ),
      ]),
    );
  }
}
