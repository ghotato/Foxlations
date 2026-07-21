import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/app_navigator.dart';
import '../../core/services/webview_service.dart';

/// In-progress interactive solves, keyed by domain, so concurrent extension
/// requests to the same site don't stack multiple challenge screens.
final Map<String, Future<bool>> _interactiveLocks = {};

/// Show the interactive Cloudflare challenge screen for [url] (a visible
/// WebView the user completes, e.g. a Turnstile checkbox). Returns true once
/// the challenge is solved and cookies are captured. De-duplicated per domain.
Future<bool> solveCloudflareInteractively(String url) {
  final nav = rootNavigatorKey.currentState;
  if (nav == null) return Future.value(false);
  final domain = WebViewService().normalizeDomain(Uri.parse(url).host);
  final existing = _interactiveLocks[domain];
  if (existing != null) return existing;

  final future = nav
      .push<bool>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CfChallengeScreen(url: url),
      ))
      .then((v) => v ?? false)
      .whenComplete(() => _interactiveLocks.remove(domain));
  _interactiveLocks[domain] = future;
  return future;
}

class CfChallengeScreen extends StatefulWidget {
  final String url;
  const CfChallengeScreen({super.key, required this.url});

  @override
  State<CfChallengeScreen> createState() => _CfChallengeScreenState();
}

class _CfChallengeScreenState extends State<CfChallengeScreen> {
  bool _done = false;
  InAppWebViewController? _controller;

  Future<bool> _isChallenge(InAppWebViewController c) async {
    try {
      final title =
          (await c.evaluateJavascript(source: 'document.title'))?.toString() ??
              '';
      final t = title.toLowerCase();
      if (t.contains('just a moment') ||
          t.contains('checking your browser') ||
          t.contains('please wait')) {
        return true;
      }
      final hasEl = await c.evaluateJavascript(
          source: "!!(document.getElementById('challenge-form') || "
              "document.getElementById('cf-please-wait') || "
              "document.querySelector('#challenge-stage') || "
              "document.querySelector('[class*=\"cf-\"]'))");
      return hasEl == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _check() async {
    if (_done || _controller == null) return;
    if (!await _isChallenge(_controller!)) {
      _done = true;
      await WebViewService().storeCookiesFrom(widget.url, _controller!);
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Verify you are human',
            style:
                GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          color: cs.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            'Complete the site’s check below. It closes automatically and won’t '
            'ask again while the verification lasts.',
            style: GoogleFonts.manrope(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              clearCache: false,
            ),
            onWebViewCreated: (c) => _controller = c,
            onLoadStop: (c, _) async => _check(),
            onUpdateVisitedHistory: (c, _, __) async => _check(),
          ),
        ),
      ]),
    );
  }
}
