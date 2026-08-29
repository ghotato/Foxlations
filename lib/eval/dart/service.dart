import 'package:flutter/foundation.dart';
import 'package:d4rt/d4rt.dart';
import 'bridge/registrer.dart';
import '../../core/utils/url_utils.dart';
import '../model/filter.dart';
import '../model/m_manga.dart';
import '../model/m_pages.dart';
import '../model/m_source.dart';
import '../model/m_video.dart';
import '../model/page_url.dart';
import '../model/source_preference.dart';
import '../model/preferences.dart';
import '../interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/cookie_store.dart';
import 'bridge/m_provider.dart';

class DartExtensionService implements ExtensionService {
  final MSource _mSource;
  final String _sourceCode;
  final String _baseUrl;
  D4rt? _interpreter;
  String? _initError;

  DartExtensionService({
    required MSource mSource,
    required String sourceCode,
    required String baseUrl,
  })  : _mSource = mSource,
        _sourceCode = sourceCode,
        _baseUrl = baseUrl {
    _interpreter = D4rt();
    RegistrerBridge.registerBridge(_interpreter!);

    // Client(source) is now supported directly (the bridge reads the source's
    // baseUrl for relative-URL resolution), so no rewrite is needed.
    final code = _sourceCode;
    if (code.trim().isEmpty) {
      // An empty program has no `main`, which d4rt reports as the confusing
      // "Undefined variable: main". Say what actually happened.
      _initError = 'This source has no code to run (it may be a Tachiyomi / '
          'Mihon Kotlin extension, which is not supported). Reinstall it from a '
          'Mangayomi-compatible repo.';
      debugPrint('[D4rt] empty source for ${mSource.name}');
      return;
    }
    try {
      _interpreter!.execute(
        source: code,
        positionalArgs: [_mSource],
      );
      debugPrint('[D4rt] Extension loaded for ${mSource.name}');
    } catch (e, st) {
      _initError = e.toString();
      debugPrint('[D4rt] EXECUTE ERROR for ${mSource.name}: $e');
      debugPrint('[D4rt] Stack: $st');
    }
  }

  @override
  void dispose() {
    _interpreter = null;
  }

  @override
  Map<String, String> getHeaders() {
    try {
      return _interpreter!.invoke('headers', []) as Map<String, String>;
    } catch (_) {
      try {
        return _interpreter!.invoke('getHeader', [_baseUrl])
            as Map<String, String>;
      } catch (_) {
        return {};
      }
    }
  }

  @override
  String get sourceBaseUrl {
    try {
      final baseUrl = _interpreter!.invoke('baseUrl', []) as String?;
      return (baseUrl == null || baseUrl.isEmpty) ? _baseUrl : baseUrl;
    } catch (_) {
      return _baseUrl;
    }
  }

  @override
  bool get supportsLatest {
    try {
      return _interpreter!.invoke('supportsLatest', []) as bool? ?? true;
    } catch (_) {
      return true;
    }
  }

  void _checkReady() {
    if (_initError != null) throw Exception(_initError);
  }

  // Sources may read a stored preference synchronously while building their
  // first request, so the async pref store must be pulled into the sync cache
  // before any source method runs. Done once per service.
  bool _prefsLoaded = false;
  Future<void> _ensurePrefs() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    try {
      final store = await SharedPreferences.getInstance();
      final prefix = 'source_pref_${_mSource.id}_';
      final vals = <String, dynamic>{};
      // 1) Stored user overrides win — load them first.
      for (final k in store.getKeys()) {
        if (k.startsWith(prefix)) {
          final v = store.get(k);
          if (v != null) vals[k.substring(prefix.length)] = v;
        }
      }
      // 2) Point every base-URL override key at the index's baseUrl. Sources
      // hardcode a default domain in their declared prefs, but those go stale
      // (gogoanime alone has moved domains many times); the index is what we
      // keep current, so seed it here where it out-ranks the declared default
      // seeded in step 3.
      for (final key in [
        'override_baseurl',
        'overrideBaseUrl',
        'preferred_domain',
        'domain',
        // Aniyomi/keiyoushi-style sources suffix the key with the source id.
        'override_baseurl_v${_mSource.id}',
      ]) {
        vals.putIfAbsent(key, () => _mSource.baseUrl);
      }
      // 3) Seed the source's OWN declared defaults (preferred quality/server,
      // the enabled-hosts multi-select, etc.) so getVideoList's host filtering
      // and quality sorting work before the user ever opens settings. Guarded
      // so a source without getSourcePreferences can't skip the cache write.
      try {
        for (final pref in getSourcePreferences()) {
          if (pref.key.isNotEmpty && pref.defaultValue != null) {
            vals.putIfAbsent(pref.key, () => pref.defaultValue);
          }
        }
      } catch (_) {}
      SourcePrefCache.put(_mSource.id, vals);
    } catch (_) {
      // No prefs / store unavailable — sources fall back to their defaults.
    }
  }

  @override
  Future<MPages> getPopular(int page) async {
    _checkReady();
    await _ensurePrefs();
    return await _interpreter!.invoke('getPopular', [page]) as MPages;
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    await _ensurePrefs();
    return await _interpreter!.invoke('getLatestUpdates', [page]) as MPages;
  }

  @override
  Future<MPages> search(
      String query, int page, List<dynamic> filters) async {
    await _ensurePrefs();
    return await _interpreter!.invoke('search', [
      query,
      page,
      FilterList(filters),
    ]) as MPages;
  }

  @override
  Future<MManga> getDetail(String url) async {
    await _ensurePrefs();
    return await _interpreter!.invoke('getDetail', [url]) as MManga;
  }

  @override
  Future<List<PageUrl>> getPageList(String url) async {
    await _ensurePrefs();
    final result =
        await _interpreter!.invoke('getPageList', [url]) as List;

    // Merge source-level headers with per-page headers
    final sourceHeaders = getHeaders();
    // safeOrigin guards Uri.origin, which throws on non-http(s) or hostless
    // URLs (hasScheme alone isn't enough — ftp:// or a scheme with no host
    // still throw).
    final referer = safeOrigin(url) ?? _baseUrl;
    final storedUA = await CookieStore().getUserAgent();
    var finalReferer = referer;
    final refererUri = Uri.tryParse(referer);
    if (refererUri != null && !refererUri.host.startsWith('www.')) {
      finalReferer = referer.replaceFirst(
          '://${refererUri.host}', '://www.${refererUri.host}');
    }
    if (!finalReferer.endsWith('/')) finalReferer = '$finalReferer/';
    final defaultHeaders = <String, String>{
      'Referer': finalReferer,
      'User-Agent': storedUA,
      ...sourceHeaders,
    };

    debugPrint('[Service] getPageList raw result: ${result.length} items');
    if (result.isNotEmpty) {
      debugPrint('[Service] First item type: ${result.first.runtimeType}, value: "${result.first.toString().substring(0, result.first.toString().length.clamp(0, 100))}"');
    }
    final pages = result.map((e) {
      if (e is String) {
        return PageUrl(e.trim(),
            headers: Map<String, String>.from(defaultHeaders));
      }
      final pageUrl = PageUrl.fromJson(
          (e as Map).map((k, v) => MapEntry(k.toString(), v)));
      pageUrl.headers = {
        ...defaultHeaders,
        ...?pageUrl.headers,
      };
      return pageUrl;
    }).toList();

    return pages;
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final result = await _interpreter!.invoke('getVideoList', [url]) as List;
    return result.cast<MVideo>();
  }

  @override
  Future<List<Map<String, String>>> getCategories() async {
    try {
      final result = await _interpreter!.invoke('getCategories', []) as List;
      return result
          .whereType<Map>()
          .map((e) => {
                'name': (e['name'] ?? '').toString(),
                'link': (e['link'] ?? e['url'] ?? '').toString(),
              })
          .where((c) =>
              (c['name'] ?? '').isNotEmpty && (c['link'] ?? '').isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<MPages> getListing(String listingUrl, int page) async {
    try {
      final result = await _interpreter!.invoke('getListing', [listingUrl, page]);
      return result as MPages;
    } catch (_) {
      return MPages(list: const [], hasNextPage: false);
    }
  }

  @override
  Future<String> getHtmlContent(String url) async {
    try {
      final result = await _interpreter!.invoke('getHtmlContent', [url]);
      return result?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  FilterList getFilterList() {
    List<dynamic> list = [];
    try {
      list = _interpreter!.invoke('getFilterList', []) as List;
    } catch (_) {}
    return FilterList(list);
  }

  @override
  List<SourcePreference> getSourcePreferences() {
    try {
      final result = _interpreter!.invoke('getSourcePreferences', []) as List;
      return result
          .map(_toSourcePreference)
          .whereType<SourcePreference>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // Dart sources run in-process and read prefs from the app's own store, so the
  // schema is synchronous and there's nothing to persist host-side.
  @override
  Future<List<SourcePreference>> fetchSourcePreferences() async =>
      getSourcePreferences();

  @override
  Future<void> setSourcePreference(String key, dynamic value) async {}

  // Sources build their preferences as EditTextPreference / ListPreference /
  // MultiSelectListPreference / CheckBox / Switch objects (m2k3a style); each
  // knows how to collapse into a SourcePreference carrying its default.
  static SourcePreference? _toSourcePreference(dynamic p) {
    if (p is SourcePreference) return p;
    if (p is EditTextPreference) return p.toPref();
    if (p is ListPreference) return p.toPref();
    if (p is MultiSelectListPreference) return p.toPref();
    if (p is CheckBoxPreference) return p.toPref();
    if (p is SwitchPreferenceCompat) return p.toPref();
    return null;
  }
}
