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
        // The value is embedded as a JS object LITERAL, not inside a quoted
        // string. jsonEncode output is already valid JS, so there is no
        // surrounding quote for source-controlled metadata (name/baseUrl/…) to
        // break out of — the previous JSON.parse('…') wrapper put it inside a
        // single-quoted string that jsonEncode does not escape ' for, making
        // the source's own index.json metadata an arbitrary-code vector.
        return ${jsonEncode(_mSource.toJson())};
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
    final result = _extensionApply<Map>('getHeaders', [_baseUrl], {});
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
    return MPages.fromJson(await _extensionApplyAsync('getPopular', [page]));
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    return MPages.fromJson(
        await _extensionApplyAsync('getLatestUpdates', [page]));
  }

  @override
  Future<MPages> search(String query, int page, List<dynamic> filters) async {
    return MPages.fromJson(
      await _extensionApplyAsync(
        'search',
        [query, page, filterValuesListToJson(filters)],
      ),
    );
  }

  @override
  Future<MManga> getDetail(String url) async {
    return MManga.fromJson(
        await _extensionApplyAsync('getDetail', [url]));
  }

  @override
  Future<List<PageUrl>> getPageList(String url) async {
    final pages = LinkedHashSet<PageUrl>(
      equals: (a, b) => a.url == b.url,
      hashCode: (p) => p.url.hashCode,
    );

    for (final e
        in await _extensionApplyAsync<List>('getPageList', [url])) {
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
    final raw =
        await _extensionApplyAsync<List>('getVideoList', [url]);
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
    return MPages.fromJson(
        await _extensionApplyAsync('getListing', [listingUrl, page]));
  }

  @override
  Future<String> getHtmlContent(String url) async {
    try {
      final r = await _extensionApplyAsync('getHtmlContent', [url]);
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

  // JS sources run in-process and read their prefs from the app's own store
  // (written by the settings UI), so the schema is synchronous and the host has
  // nothing to persist.
  @override
  Future<List<SourcePreference>> fetchSourcePreferences() async =>
      getSourcePreferences();

  @override
  Future<void> setSourcePreference(String key, dynamic value) async {}

  /// Decodes a JSON payload coming back from the JS engine.
  ///
  /// flutter_js uses a different engine per platform — QuickJS on Android,
  /// JavaScriptCore on iOS — and they resolve promises differently. QuickJS
  /// hands the resolved value back as a Dart Future and stringifies it once
  /// (`"$res"`), but JSC reports `[object Promise]` and takes the branch in
  /// flutter_js `handle_promises.dart` that runs `JSON.stringify()` over the
  /// value a SECOND time. Since `jsonStringify()` already returns a string,
  /// iOS payloads arrive double-encoded and a single decode yields a String
  /// instead of the Map/List the caller expects.
  ///
  /// Detect that structurally: only a re-encoded payload decodes to a string
  /// that itself starts with a JSON delimiter. Real string results (page HTML)
  /// start with `<` or plain text, so they're left alone on both platforms.
  T _decodeJsResult<T>(String raw) {
    dynamic value = jsonDecode(raw);
    if (value is String) {
      // Re-decode when the caller wants something other than a String (the
      // string is clearly a wrapper), or — when T is dynamic, as it is for
      // getHtmlContent — when the payload still looks like encoded JSON.
      final trimmed = value.trimLeft();
      final looksEncoded = trimmed.startsWith('{') ||
          trimmed.startsWith('[') ||
          trimmed.startsWith('"');
      if (value is! T || looksEncoded) {
        try {
          value = jsonDecode(value);
        } catch (_) {
          // Not double-encoded after all — keep the string as-is.
        }
      }
    }
    return value as T;
  }

  T _extensionCall<T>(String call, T defaultValue) {
    _init();
    try {
      final res = runtime.evaluate('JSON.stringify(extention.$call)');
      return _decodeJsResult<T>(res.stringResult);
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
    return _decodeJsResult<T>(promised.stringResult);
  }

  /// Invokes an extension method by passing [args] as a JSON array and calling
  /// `.apply()`, instead of interpolating each argument into the call string.
  ///
  /// This is the injection-safe path: `jsonEncode` of the argument list is a
  /// valid JS array literal, so a source name, URL, or search query containing
  /// a quote, backtick, `${…}` or `');` cannot break out of the expression and
  /// run attacker JS. The old string-built calls escaped only some delimiters
  /// for the wrong quoting context.
  String _applyExpr(String method, List<dynamic> args) =>
      'extention.$method.apply(extention, ${jsonEncode(args)})';

  T _extensionApply<T>(String method, List<dynamic> args, T defaultValue) {
    _init();
    try {
      final res = runtime.evaluate('JSON.stringify(${_applyExpr(method, args)})');
      return _decodeJsResult<T>(res.stringResult);
    } catch (_) {
      return defaultValue;
    }
  }

  Future<T> _extensionApplyAsync<T>(String method, List<dynamic> args) async {
    _init();
    final jsResult = await runtime.evaluateAsync(
      'jsonStringify(() => ${_applyExpr(method, args)})',
    );
    final promised = await runtime.handlePromise(jsResult);
    return _decodeJsResult<T>(promised.stringResult);
  }
}
