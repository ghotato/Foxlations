import 'dart:collection';
import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import 'dom_selector.dart';
import 'http.dart';
import 'preferences.dart';
import 'utils.dart';
import '../model/filter.dart';
import '../model/m_manga.dart';
import '../model/m_pages.dart';
import '../model/m_source.dart';
import '../model/m_video.dart';
import '../model/page_url.dart';
import '../model/source_preference.dart';
import '../interface.dart';

class JsExtensionService implements ExtensionService {
  late JavascriptRuntime runtime;
  final MSource _mSource;
  final String _sourceCode;
  final String _baseUrl;
  bool _isInitialized = false;
  late JsDomSelector _jsDomSelector;

  JsExtensionService({
    required MSource mSource,
    required String sourceCode,
    required String baseUrl,
  })  : _mSource = mSource,
        _sourceCode = sourceCode,
        _baseUrl = baseUrl;

  void _init() {
    if (_isInitialized) return;
    runtime = getJavascriptRuntime();
    JsHttpClient(runtime).init();
    _jsDomSelector = JsDomSelector(runtime)..init();
    JsUtils(runtime).init();
    JsPreferences(runtime, _mSource).init();

    // Inject MProvider base class
    runtime.evaluate('''
class MProvider {
    get source() {
        return JSON.parse('${jsonEncode(_mSource.toJson())}');
    }
    get baseUrl() {
        return this.source.baseUrl || "";
    }
    get supportsLatest() {
        return true;
    }
    getHeaders(url) {
        return {};
    }
    async getPopular(page) {
        throw new Error("getPopular not implemented");
    }
    async getLatestUpdates(page) {
        throw new Error("getLatestUpdates not implemented");
    }
    async search(query, page, filters) {
        throw new Error("search not implemented");
    }
    async getDetail(url) {
        throw new Error("getDetail not implemented");
    }
    async getPageList(url) {
        throw new Error("getPageList not implemented");
    }
    getFilterList() {
        return [];
    }
    getSourcePreferences() {
        return [];
    }
    async getCategories() {
        return [];
    }
    async getListing(url, page) {
        return { list: [], hasNextPage: false };
    }
    async getHtmlContent(url) {
        return "";
    }
}
async function jsonStringify(fn) {
    return JSON.stringify(await fn());
}
''');

    // Execute the extension source code
    runtime.evaluate('''$_sourceCode
var extention = new DefaultExtension();
''');
    _isInitialized = true;
  }

  @override
  void dispose() {
    if (!_isInitialized) return;
    _jsDomSelector.dispose();
    runtime.dispose();
    _isInitialized = false;
  }

  @override
  Map<String, String> getHeaders() {
    final result = _extensionCall<Map>('getHeaders(`$_baseUrl`)', {});
    return result.map((key, value) => MapEntry(key.toString(), value.toString()));
  }

  @override
  bool get supportsLatest {
    return _extensionCall<bool>('supportsLatest', true);
  }

  @override
  String get sourceBaseUrl => _baseUrl;

  @override
  Future<MPages> getPopular(int page) async {
    return MPages.fromJson(await _extensionCallAsync('getPopular($page)'));
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    return MPages.fromJson(
        await _extensionCallAsync('getLatestUpdates($page)'));
  }

  @override
  Future<MPages> search(String query, int page, List<dynamic> filters) async {
    final escapedQuery = query.replaceAll('"', '\\"');
    return MPages.fromJson(
      await _extensionCallAsync(
        'search("$escapedQuery",$page,${jsonEncode(filterValuesListToJson(filters))})',
      ),
    );
  }

  @override
  Future<MManga> getDetail(String url) async {
    final escapedUrl = url.replaceAll('`', '\\`');
    return MManga.fromJson(await _extensionCallAsync('getDetail(`$escapedUrl`)'));
  }

  @override
  Future<List<PageUrl>> getPageList(String url) async {
    final escapedUrl = url.replaceAll('`', '\\`');
    final pages = LinkedHashSet<PageUrl>(
      equals: (a, b) => a.url == b.url,
      hashCode: (p) => p.url.hashCode,
    );

    for (final e
        in await _extensionCallAsync<List>('getPageList(`$escapedUrl`)')) {
      if (e != null) {
        final page = e is String
            ? PageUrl(e.trim())
            : PageUrl.fromJson(
                (e as Map).map((k, v) => MapEntry(k.toString(), v)));
        pages.add(page);
      }
    }

    return pages.toList();
  }

  @override
  FilterList getFilterList() {
    List<dynamic> list;
    try {
      list =
          fromJsonFilterValuesToList(_extensionCall('getFilterList()', []));
    } catch (_) {
      list = [];
    }
    return FilterList(list);
  }

  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final escapedUrl = url.replaceAll('`', '\\`');
    final raw =
        await _extensionCallAsync<List>('getVideoList(`$escapedUrl`)');
    final videos = <MVideo>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = e.map((k, v) => MapEntry(k.toString(), v));
      final vurl = (m['url'] ?? '').toString();
      if (vurl.isEmpty) continue;
      videos.add(MVideo(
        vurl,
        (m['quality'] ?? 'Video').toString(),
        (m['originalUrl'] ?? vurl).toString(),
        headers: (m['headers'] is Map)
            ? (m['headers'] as Map)
                .map((k, v) => MapEntry(k.toString(), v.toString()))
            : null,
      ));
    }
    return videos;
  }

  @override
  Future<List<Map<String, String>>> getCategories() async {
    try {
      final raw = await _extensionCallAsync<List>('getCategories()');
      return raw
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
    final escaped = listingUrl.replaceAll('`', '\\`');
    return MPages.fromJson(
        await _extensionCallAsync('getListing(`$escaped`,$page)'));
  }

  @override
  Future<String> getHtmlContent(String url) async {
    try {
      final escaped = url.replaceAll('`', '\\`');
      final r = await _extensionCallAsync('getHtmlContent(`$escaped`)');
      return r?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  List<SourcePreference> getSourcePreferences() {
    try {
      final raw = _extensionCall<List>('getSourcePreferences()', []);
      return raw
          .map((e) =>
              SourcePreference.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  T _extensionCall<T>(String call, T defaultValue) {
    _init();
    try {
      final res = runtime.evaluate('JSON.stringify(extention.$call)');
      return jsonDecode(res.stringResult) as T;
    } catch (_) {
      return defaultValue;
    }
  }

  Future<T> _extensionCallAsync<T>(String call) async {
    _init();
    final jsResult = await runtime.evaluateAsync(
      'jsonStringify(() => extention.$call)',
    );
    final promised = await runtime.handlePromise(jsResult);
    return jsonDecode(promised.stringResult) as T;
  }
}
