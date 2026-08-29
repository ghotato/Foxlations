import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Heuristically extracts real listing selectors from a page's HTML, so
/// RepoForge can generate a **site-specific** scraper for custom/unknown sites
/// instead of falling back to generic defaults.
///
/// Strategy: manga/anime listing pages render a grid of "cards", each a small
/// container holding a cover `<img>` and a titled `<a href>`. We find the
/// container class that repeats most across such image+title pairs, then derive
/// the item / title / cover selectors (and which attribute holds the cover URL)
/// from a representative card.
///
/// Returns an empty map when no confident repeating structure is found — the
/// caller then keeps its framework-canonical or default selectors.
class SelectorExtractor {
  /// Minimum number of repeating cards to trust a detected listing.
  static const int _minCards = 4;

  static const Set<String> _classStoplist = {
    'row', 'col', 'container', 'container-fluid', 'clearfix', 'active',
    'selected', 'hidden', 'show', 'wrapper', 'content', 'main', 'inner',
    'grid', 'flex', 'list', 'items', 'box', 'card', 'item',
  };

  static const List<String> _coverAttrs = [
    'data-src', 'data-lazy-src', 'data-original', 'data-cfsrc', 'data-url',
    'srcset', 'src',
  ];

  // High-population canonical reader-page selectors (cover the most sites — they
  // come from the shared theme parsers, so they aren't in the per-site corpus).
  static const List<String> _canonPage = [
    'div#readerarea img', 'div.reading-content img',
    'div.container-chapter-reader img', '#chapter-images img',
    '.reading-content img', '.page-break img', '#all img',
  ];
  static const List<String> _canonChapter = [
    'li.wp-manga-chapter', '#chapterlist li', 'ul.row-content-chapter li',
    'div.bxcl li', 'div.eplister li', 'ul.chapters li',
  ];

  static Map<String, String> extract(String html) {
    if (html.trim().length < 200) return const {};
    Document doc;
    try {
      doc = html_parser.parse(html);
    } catch (_) {
      return const {};
    }

    // 1. Find each cover image's "card" (lowest classed ancestor that holds a
    //    titled link), and tally card classes.
    final classCount = <String, int>{};
    final classTag = <String, Map<String, int>>{};
    final cardOfClass = <String, Element>{};

    for (final img in doc.querySelectorAll('img')) {
      final card = _cardFor(img);
      if (card == null) continue;
      final tag = card.localName;
      if (tag == null) continue;
      for (final c in card.classes.where(_stableClass)) {
        classCount[c] = (classCount[c] ?? 0) + 1;
        (classTag[c] ??= {})[tag] = (classTag[c]![tag] ?? 0) + 1;
        cardOfClass.putIfAbsent(c, () => card);
      }
    }
    if (classCount.isEmpty) return const {};

    // 2. Pick the most-repeated card class (must clear the confidence bar).
    final best = classCount.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (best.value < _minCards) return const {};
    final cls = best.key;
    final tag = classTag[cls]!.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    final itemSel = '$tag.$cls';

    // 3. Derive title / cover / coverAttr from a representative card.
    final card = cardOfClass[cls]!;
    final titleA = _titleAnchor(card);
    final img = card.querySelector('img');

    var titleSel = 'a';
    if (titleA != null) {
      final tc = titleA.classes.where(_stableClass).toList();
      if (tc.isNotEmpty) titleSel = 'a.${tc.first}';
    }

    var coverSel = 'img';
    var coverAttr = 'src';
    if (img != null) {
      final ic = img.classes.where(_stableClass).toList();
      if (ic.isNotEmpty) coverSel = 'img.${ic.first}';
      coverAttr = _coverAttr(img);
    }

    final result = <String, String>{
      'item': itemSel,
      'popular': itemSel,
      'title': titleSel,
      'link': titleSel,
      'cover': coverSel,
      'coverAttr': coverAttr,
    };

    // Optional: a next-page selector if an obvious one exists.
    for (final sel in const ['a[rel=next]', 'a.next', 'a.next-page', '.pagination .next a']) {
      if (doc.querySelector(sel) != null) {
        result['nextPage'] = sel;
        break;
      }
    }
    return result;
  }

  /// Extract the chapter-list selector from a **detail page's** HTML. Tries the
  /// ranked KB [candidates] first, then falls back to finding the repeating row
  /// that holds chapter-like links. Returns `{chapters: sel}` or `{}`.
  static Map<String, String> extractChapters(
    String html, {
    List<String> candidates = const [],
  }) {
    if (html.trim().length < 200) return const {};
    Document doc;
    try {
      doc = html_parser.parse(html);
    } catch (_) {
      return const {};
    }
    for (final sel in [..._canonChapter, ...candidates]) {
      try {
        final els = doc.querySelectorAll(sel);
        final chap = els.where((e) {
          final a = e.localName == 'a' ? e : e.querySelector('a');
          return a != null && _looksChapterLink(a);
        }).length;
        if (els.length >= 3 && chap >= 2) return {'chapters': sel};
      } catch (_) {}
    }
    final links = doc
        .querySelectorAll('a[href]')
        .where(_looksChapterLink)
        .toList();
    final sel = _repeatingRowSelector(links);
    return sel != null ? {'chapters': sel} : const {};
  }

  /// Extract the page-image selector from a **reader page's** HTML. Tries the
  /// ranked KB [candidates], then the classed container holding the most
  /// content images. Returns `{page_images: sel, lazyAttr: attr}` or `{}`.
  static Map<String, String> extractPages(
    String html, {
    List<String> candidates = const [],
  }) {
    if (html.trim().length < 200) return const {};
    Document doc;
    try {
      doc = html_parser.parse(html);
    } catch (_) {
      return const {};
    }
    // 1. Canonical + KB candidates, skipping over-generic ones (e.g. img[src]).
    for (final sel in [..._canonPage, ...candidates]) {
      if (_tooGeneric(sel)) continue;
      try {
        final imgs = doc.querySelectorAll(sel).where(_hasImageUrl).toList();
        if (imgs.length >= 3) {
          return {'page_images': sel, 'lazyAttr': _coverAttr(imgs.first)};
        }
      } catch (_) {}
    }
    final imgs = doc.querySelectorAll('img').where(_hasImageUrl).toList();
    if (imgs.length < 3) return const {};
    final attr = _coverAttr(imgs.first);

    // 2a. A class shared by most page images (e.g. img.ts-main-image).
    final imgClass = <String, int>{};
    for (final img in imgs) {
      for (final c in img.classes.where(_stableClass)) {
        imgClass[c] = (imgClass[c] ?? 0) + 1;
      }
    }
    if (imgClass.isNotEmpty) {
      final b = imgClass.entries.reduce((a, b) => a.value >= b.value ? a : b);
      if (b.value >= 3 && b.value >= imgs.length * 0.5) {
        return {'page_images': 'img.${b.key}', 'lazyAttr': attr};
      }
    }

    // 2b. The container (class or id) holding the most images.
    final count = <String, int>{};
    final selOf = <String, String>{};
    for (final img in imgs) {
      Element? c = img.parent;
      var hops = 0;
      while (c != null && hops < 5) {
        final id = c.id;
        final classes = c.classes.where(_stableClass).toList();
        if (id.isNotEmpty && _stableClass(id)) {
          final key = '#$id';
          count[key] = (count[key] ?? 0) + 1;
          selOf[key] = '#$id img';
          break;
        }
        if (classes.isNotEmpty) {
          final key = '${c.localName}.${classes.first}';
          count[key] = (count[key] ?? 0) + 1;
          selOf[key] = '$key img';
          break;
        }
        c = c.parent;
        hops++;
      }
    }
    if (count.isNotEmpty) {
      final best = count.entries.reduce((a, b) => a.value >= b.value ? a : b);
      if (best.value >= 3) {
        return {'page_images': selOf[best.key]!, 'lazyAttr': attr};
      }
    }
    return {'page_images': 'img', 'lazyAttr': attr};
  }

  /// True for selectors too generic to trust for page detection (`img`,
  /// `img[src]`, `a[href]` …) — no class, id, or combinator.
  static bool _tooGeneric(String sel) => RegExp(
    r'^[a-z0-9]+(\[[^\]]*\])?$',
    caseSensitive: false,
  ).hasMatch(sel.trim());

  /// Extract category / genre / tag navigation links (name + path) so the
  /// generated source can offer a "Category" filter to browse by. Common on
  /// tube and manga sites alike.
  static List<Map<String, String>> extractCategories(String html, String baseUrl) {
    if (html.trim().length < 200) return const [];
    Document doc;
    try {
      doc = html_parser.parse(html);
    } catch (_) {
      return const [];
    }
    final re = RegExp(
      r'/(categor(?:y|ies)|genres?|tags?|channels?)/[^/?#]+',
      caseSensitive: false,
    );
    final byPath = <String, String>{}; // path -> name
    for (final a in doc.querySelectorAll('a[href]')) {
      final text = a.text.trim();
      if (text.isEmpty || text.length > 30) continue;
      final href = a.attributes['href'] ?? '';
      if (!re.hasMatch(href)) continue;
      String path;
      try {
        final u = Uri.parse(_resolve(baseUrl, href));
        path = u.path + (u.hasQuery ? '?${u.query}' : '');
      } catch (_) {
        continue;
      }
      if (path.isEmpty || byPath.containsKey(path)) continue;
      byPath[path] = text;
      if (byPath.length >= 40) break;
    }
    return byPath.entries
        .map((e) => {'name': e.value, 'path': e.key})
        .toList();
  }

  /// First absolute detail-page URL from a listing page, using the detected
  /// [itemSel]/[titleSel] to pick a real content link.
  static String? firstDetailUrl(
    String html,
    String baseUrl, {
    String? itemSel,
    String? titleSel,
  }) {
    try {
      final doc = html_parser.parse(html);
      Element? a;
      if (itemSel != null && itemSel.isNotEmpty) {
        final item = doc.querySelector(itemSel);
        a = (titleSel != null && titleSel.isNotEmpty
                ? item?.querySelector(titleSel)
                : null) ??
            item?.querySelector('a[href]');
      }
      if (a == null && titleSel != null && titleSel.isNotEmpty) {
        a = doc.querySelector(titleSel);
      }
      final href = a?.attributes['href'] ?? '';
      if (href.isNotEmpty) return _resolve(baseUrl, href);
    } catch (_) {}
    return null;
  }

  /// First absolute chapter/reader URL on a detail page.
  static String? firstChapterUrl(String html, String baseUrl) {
    try {
      final doc = html_parser.parse(html);
      for (final a in doc.querySelectorAll('a[href]')) {
        if (_looksChapterLink(a)) {
          final href = a.attributes['href'] ?? '';
          if (href.isNotEmpty) return _resolve(baseUrl, href);
        }
      }
    } catch (_) {}
    return null;
  }

  static String _resolve(String base, String href) {
    try {
      return Uri.parse(base).resolve(href).toString();
    } catch (_) {
      return href;
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────

  static final RegExp _chapterText = RegExp(
    r'chapter|episode|\bch\.?\s*\d|^\s*\d+(\.\d+)?\s*$',
    caseSensitive: false,
  );
  static final RegExp _chapterHref = RegExp(
    r'chapter|/read/|-ch(apter)?-|/ch-|episode',
    caseSensitive: false,
  );

  static bool _looksChapterLink(Element a) {
    final t = a.text.trim();
    if (t.isNotEmpty && t.length < 60 && _chapterText.hasMatch(t)) return true;
    final href = a.attributes['href'] ?? '';
    return href.isNotEmpty && _chapterHref.hasMatch(href);
  }

  static bool _hasImageUrl(Element img) {
    for (final a in _coverAttrs) {
      final v = (img.attributes[a] ?? '').trim();
      if (v.isNotEmpty && !v.startsWith('data:')) return true;
    }
    return false;
  }

  /// Most common classed row-ancestor selector among [anchors] (a chapter row).
  static String? _repeatingRowSelector(List<Element> anchors) {
    final count = <String, int>{};
    final tagOf = <String, Map<String, int>>{};
    for (final a in anchors) {
      Element? row = a;
      var hops = 0;
      while (row != null && hops < 4) {
        final classes = row.classes.where(_stableClass).toList();
        if (classes.isNotEmpty) {
          final tag = row.localName!;
          for (final c in classes) {
            count[c] = (count[c] ?? 0) + 1;
            (tagOf[c] ??= {})[tag] = (tagOf[c]![tag] ?? 0) + 1;
          }
          break;
        }
        row = row.parent;
        hops++;
      }
    }
    if (count.isEmpty) return null;
    final best = count.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (best.value < 3) return null;
    final tag = tagOf[best.key]!.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    return '$tag.${best.key}';
  }

  /// Lowest classed ancestor of [img] that also contains a titled `<a href>`.
  static Element? _cardFor(Element img) {
    Element? anc = img.parent;
    var hops = 0;
    while (anc != null && hops < 6) {
      if (anc.classes.any(_stableClass) && _hasTitledLink(anc)) return anc;
      anc = anc.parent;
      hops++;
    }
    return null;
  }

  static bool _hasTitledLink(Element el) {
    for (final a in el.querySelectorAll('a[href]')) {
      if (a.text.trim().length >= 3) return true;
      if ((a.attributes['title'] ?? '').trim().length >= 3) return true;
    }
    return false;
  }

  /// The anchor most likely to be the title link (longest text, or a `title`).
  static Element? _titleAnchor(Element card) {
    Element? best;
    var bestLen = 0;
    for (final a in card.querySelectorAll('a[href]')) {
      final len = a.text.trim().length + (a.attributes['title'] ?? '').trim().length;
      if (len > bestLen) {
        bestLen = len;
        best = a;
      }
    }
    return best;
  }

  /// Which attribute on [img] actually holds a usable cover URL.
  static String _coverAttr(Element img) {
    for (final attr in _coverAttrs) {
      final v = (img.attributes[attr] ?? '').trim();
      if (v.isEmpty) continue;
      if (v.startsWith('data:')) continue; // inline placeholder
      if (attr == 'src' && v.contains('data:image')) continue;
      if (v.contains('http') || v.startsWith('/') || v.contains('.')) return attr;
    }
    return 'src';
  }

  /// Reject dynamic/hashed/utility classes; keep semantic ones.
  static bool _stableClass(String c) {
    if (c.length < 2 || c.length > 30) return false;
    if (_classStoplist.contains(c)) return false;
    if (RegExp(r'\d{2,}').hasMatch(c)) return false; // css-1a2b3c, col-12, …
    if (RegExp(r'^(col|row|d|p|m|mt|mb|ml|mr|px|py|w|h)-').hasMatch(c)) {
      return false; // bootstrap/utility grid classes
    }
    return true;
  }
}
