import 'package:flutter/foundation.dart';
import 'package:d4rt/d4rt.dart';
import 'bridge/registrer.dart';
import '../model/filter.dart';
import '../model/m_manga.dart';
import '../model/m_pages.dart';
import '../model/m_source.dart';
import '../model/m_video.dart';
import '../model/page_url.dart';
import '../model/source_preference.dart';
import '../interface.dart';
import '../../core/services/cookie_store.dart';

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

    final code = _sourceCode.replaceAll('Client(source)', 'Client()');
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

  @override
  Future<MPages> getPopular(int page) async {
    _checkReady();
    return await _interpreter!.invoke('getPopular', [page]) as MPages;
  }

  @override
  Future<MPages> getLatestUpdates(int page) async =>
      await _interpreter!.invoke('getLatestUpdates', [page]) as MPages;

  @override
  Future<MPages> search(
      String query, int page, List<dynamic> filters) async {
    return await _interpreter!.invoke('search', [
      query,
      page,
      FilterList(filters),
    ]) as MPages;
  }

  @override
  Future<MManga> getDetail(String url) async =>
      await _interpreter!.invoke('getDetail', [url]) as MManga;

  @override
  Future<List<PageUrl>> getPageList(String url) async {
    final result =
        await _interpreter!.invoke('getPageList', [url]) as List;

    // Merge source-level headers with per-page headers
    final sourceHeaders = getHeaders();
    final parsedUrl = Uri.tryParse(url);
    final referer = (parsedUrl != null && parsedUrl.hasScheme)
        ? parsedUrl.origin
        : _baseUrl;
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
      final result = _interpreter!.invoke('getSourcePreferences', []);
      return (result as List).cast<SourcePreference>();
    } catch (_) {
      return const [];
    }
  }
}
