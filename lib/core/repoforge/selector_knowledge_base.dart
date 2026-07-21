import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// The distilled reverse-engineering of the whole reader ecosystem, mined from
/// the community extension corpus (keiyoushi + Mangayomi) and shipped as
/// `assets/selector_kb.json`.
///
/// Two things it provides so RepoForge works on differently-built sites without
/// crawling them:
///  1. **Per-site lookup** — for ~960 known sites, the exact theme or the exact
///     custom selectors the community verified (chapters / pages / cover / …).
///  2. **Ranked candidate selectors per role** — a statistical prior used by the
///     heuristic extractor for brand-new/unknown sites.
class SelectorKnowledgeBase {
  static Map<String, dynamic>? _kb;

  static Future<void> _ensureLoaded() async {
    if (_kb != null) return;
    try {
      final raw = await rootBundle.loadString('assets/selector_kb.json');
      _kb = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      _kb = {'sites': <String, dynamic>{}, 'candidates': <String, dynamic>{}};
    }
  }

  static String _host(String url) {
    try {
      final h = Uri.parse(url).host.toLowerCase();
      return h.startsWith('www.') ? h.substring(4) : h;
    } catch (_) {
      return '';
    }
  }

  /// Raw KB entry for a site: `{theme: ...}` or `{selectors: {...}}` or null.
  static Future<Map<String, dynamic>?> lookup(String url) async {
    await _ensureLoaded();
    final sites = _kb!['sites'] as Map<String, dynamic>? ?? const {};
    final e = sites[_host(url)];
    return e is Map<String, dynamic> ? e : null;
  }

  /// Exact per-site selectors, when this host is a known custom source.
  static Future<Map<String, String>?> selectorsFor(String url) async {
    final e = await lookup(url);
    final sel = e?['selectors'];
    if (sel is Map) {
      return sel.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return null;
  }

  /// The keiyoushi theme name for a host, if known (e.g. `madara`).
  static Future<String?> themeFor(String url) async {
    final t = (await lookup(url))?['theme'];
    return t is String ? t : null;
  }

  /// True if this host is a known API/JSON source (CSS scraping won't apply —
  /// the extension needs API calls, not selectors).
  static Future<bool> isApiSource(String url) async {
    return (await lookup(url))?['api'] == true;
  }

  /// Ranked candidate selectors for a role: `chapters`, `page_images`, `item`.
  static Future<List<String>> candidatesFor(String role) async {
    await _ensureLoaded();
    final c = (_kb!['candidates'] as Map<String, dynamic>?)?[role];
    if (c is List) {
      return c
          .whereType<List>()
          .map((e) => e.isNotEmpty ? e.first.toString() : '')
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }

  /// Total sites the KB can resolve (for diagnostics / UI).
  static Future<int> siteCount() async {
    await _ensureLoaded();
    return (_kb!['sites'] as Map?)?.length ?? 0;
  }

  // ---- Light-novel framework KB ----
  // `assets/novel_kb.json`: {domain: {framework, name, template}}. Built by
  // studying the LNReader plugin site lists as REFERENCE (classification data
  // only — which framework each novel site uses). Lets RepoForge pick the right
  // novel body (Madara / MangaThemesia / generic) for known light-novel sites.
  static Map<String, dynamic>? _novelKb;

  static Future<void> _ensureNovelLoaded() async {
    if (_novelKb != null) return;
    try {
      final raw = await rootBundle.loadString('assets/novel_kb.json');
      _novelKb = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      _novelKb = <String, dynamic>{};
    }
  }

  /// Novel-site entry `{framework, name, template}` for a host, or null.
  static Future<Map<String, dynamic>?> novelLookup(String url) async {
    await _ensureNovelLoaded();
    final e = _novelKb![_host(url)];
    return e is Map<String, dynamic> ? e : null;
  }

  /// True if this host is a known light-novel site.
  static Future<bool> isKnownNovel(String url) async =>
      (await novelLookup(url)) != null;

  /// Total known light-novel sites in the novel KB (for diagnostics / UI).
  static Future<int> novelSiteCount() async {
    await _ensureNovelLoaded();
    return _novelKb!.length;
  }
}
