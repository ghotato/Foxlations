import 'dart:io' show Platform;

import '../../core/services/cookie_store.dart';
import '../../core/services/webview_service.dart';
import '../interface.dart';
import '../model/filter.dart';
import '../model/m_manga.dart';
import '../model/m_pages.dart';
import '../model/m_video.dart';
import '../model/page_url.dart';
import '../model/source_preference.dart';
import 'jvm_bridge.dart';

/// Runs a Kotlin/Keiyoushi extension through the embedded JVM (Suwayomi host),
/// implementing the same [ExtensionService] contract as the Dart/JS services so it
/// drops into `getExtensionService`'s `sourceCodeLanguage` switch. Each call becomes
/// a JSON request to `SourceRunner.invoke` over the `foxlations/jvm` MethodChannel;
/// the JSON response maps straight onto the app's MPages / MManga / PageUrl models.
///
/// NOTE: platform channels can't run in a background isolate, so callers must run
/// Kotlin sources on the root isolate (see withExtensionService / isolate routing).
class KotlinExtensionService implements ExtensionService {
  /// Absolute path or a bundled jar name (resolved against `foxlations.jarsDir`).
  final String jar;

  /// For multi-language `SourceFactory` extensions (e.g. MangaDex), which sub-source
  /// language to use; null picks the first.
  final String? lang;

  final String baseUrl;

  /// Entry class (`eu.kanade.tachiyomi.animeextension…`/`…extension…`). Anime jars come
  /// from dex2jar, which drops the AndroidManifest, so the app decodes the binary manifest
  /// at import time and passes the entry class here; SourceRunner falls back to a manifest
  /// scan when this is null (manga/novel jars keep a plaintext manifest).
  final String? entry;

  KotlinExtensionService({required this.baseUrl, required this.jar, this.lang, this.entry});

  @override
  String get sourceBaseUrl => baseUrl;

  @override
  bool get supportsLatest => true;

  @override
  void dispose() {}

  @override
  Map<String, String> getHeaders() => {};

  Future<Map<String, dynamic>> _req(String method,
      [Map<String, dynamic> extra = const {}]) async {
    final req = <String, dynamic>{
      'method': method,
      'jar': jar,
      if (lang != null) 'lang': lang,
      if (entry != null) 'entry': entry,
      ...extra,
    };
    // Android's Mihon-style host (ApkBridge NetworkHelper) has no CloudflareInterceptor
    // /FlareSolverr — hand it every clearance the app holds so its OkHttp requests carry
    // cf_clearance + the matching User-Agent. iOS/desktop drive CF through the embedded
    // JVM's loopback FlareSolverr instead, so they skip this.
    if (Platform.isAndroid) {
      final cookies = await CookieStore().allCookieHeaders();
      if (cookies.isNotEmpty) req['cookies'] = cookies;
      req['userAgent'] = await CookieStore().getUserAgent();
    }
    return req;
  }

  /// Send [req] to the host. On Android, if the call fails in a way that looks like a
  /// Cloudflare block and we haven't already retried, solve the challenge headlessly
  /// (WebViewService) and retry once with the fresh cookies. iOS/desktop never reach
  /// the retry branch (the JVM host solves CF itself).
  Future<dynamic> _send(Map<String, dynamic> req, {bool allowCfRetry = true}) async {
    try {
      return await FoxJvm.invoke(req);
    } catch (e) {
      if (allowCfRetry && Platform.isAndroid && _looksLikeCloudflare(e.toString())) {
        final solved = await WebViewService().resolveCloudflare(baseUrl);
        if (solved) {
          final fresh = Map<String, dynamic>.from(req);
          final cookies = await CookieStore().allCookieHeaders();
          if (cookies.isNotEmpty) fresh['cookies'] = cookies;
          fresh['userAgent'] = await CookieStore().getUserAgent();
          return _send(fresh, allowCfRetry: false);
        }
      }
      rethrow;
    }
  }

  bool _looksLikeCloudflare(String message) {
    final m = message.toLowerCase();
    return m.contains('403') ||
        m.contains('503') ||
        m.contains('cloudflare') ||
        m.contains('just a moment') ||
        m.contains('attention required') ||
        m.contains('cf-') ||
        m.contains('captcha');
  }

  Future<MPages> _pages(String method, Map<String, dynamic> extra) async {
    final r = await _send(await _req(method, extra));
    return MPages.fromJson(Map<String, dynamic>.from(r as Map));
  }

  @override
  Future<MPages> getPopular(int page) => _pages('getPopular', {'page': page});

  @override
  Future<MPages> getLatestUpdates(int page) => _pages('getLatestUpdates', {'page': page});

  @override
  Future<MPages> search(String query, int page, List<dynamic> filters) =>
      _pages('search', {'query': query, 'page': page});

  @override
  Future<MManga> getDetail(String url) async {
    final r = await _send(await _req('getDetail', {'url': url}));
    return MManga.fromJson(Map<String, dynamic>.from(r as Map));
  }

  @override
  Future<List<PageUrl>> getPageList(String url) async {
    final r = await _send(await _req('getPageList', {'url': url}));
    return (r as List)
        .map((e) => PageUrl.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Anime episode → playable videos. SourceRunner runs the extension's
  /// getVideoList(SEpisode) and returns the app's MVideo shape (stream url, quality,
  /// headers, subtitle/audio tracks). For manga sources the JVM returns an empty list.
  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final r = await _send(await _req('getVideoList', {'url': url}));
    if (r is! List) return [];
    return r.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      List<MTrack>? tracks(dynamic v) => (v as List?)
          ?.map((t) {
            final tm = Map<String, dynamic>.from(t as Map);
            return MTrack(file: tm['file'] as String?, label: tm['label'] as String?);
          })
          .toList();
      List<MTimeStamp>? stamps(dynamic v) => (v as List?)
          ?.map((t) {
            final tm = Map<String, dynamic>.from(t as Map);
            return MTimeStamp(
              start: (tm['start'] as num?)?.toDouble() ?? 0,
              end: (tm['end'] as num?)?.toDouble() ?? 0,
              name: tm['name'] as String? ?? '',
              type: tm['type'] as String? ?? '',
            );
          })
          .toList();
      return MVideo(
        (m['url'] as String?) ?? '',
        (m['quality'] as String?) ?? '',
        (m['originalUrl'] as String?) ?? (m['url'] as String?) ?? '',
        headers: (m['headers'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())),
        subtitles: tracks(m['subtitles']),
        audios: tracks(m['audios']),
        timestamps: stamps(m['timestamps']),
      );
    }).toList();
  }

  @override
  Future<List<Map<String, String>>> getCategories() async => [];

  @override
  Future<MPages> getListing(String listingUrl, int page) async => MPages(list: []);

  /// Light-novel chapter text. The JVM runs the novel extension's getPageList →
  /// NovelSource.fetchPageText and returns the chapter HTML, which the novel reader
  /// splits into paragraphs. Manga sources have no fetchPageText, so this is empty.
  @override
  Future<String> getHtmlContent(String url) async {
    final r = await _send(await _req('getHtmlContent', {'url': url}));
    if (r is Map) return (r['content'] as String?) ?? '';
    return r?.toString() ?? '';
  }

  @override
  FilterList getFilterList() => const FilterList([]);

  /// Filled by [fetchSourcePreferences]; the sync accessor returns the last fetch.
  List<SourcePreference> _prefsCache = const [];

  @override
  List<SourcePreference> getSourcePreferences() => _prefsCache;

  @override
  Future<List<SourcePreference>> fetchSourcePreferences() async {
    try {
      final r = await FoxJvm.invoke(await _req('getPreferences'));
      if (r is! List) return _prefsCache;
      _prefsCache = r
          .map((e) => SourcePreference.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      return _prefsCache;
    } catch (_) {
      // Host without the getPreferences route (older JVM build) → no source prefs.
      return _prefsCache;
    }
  }

  @override
  Future<void> setSourcePreference(String key, dynamic value) async {
    await FoxJvm.invoke(await _req('setPreference', {'key': key, 'value': value}));
  }
}
