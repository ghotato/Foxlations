import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/source_model.dart';
import '../utils/portable_path.dart';
import 'app_logger.dart';

class RepoIndexResult {
  final String repoName;
  final String repoVersion;
  final List<MangaSource> sources;

  const RepoIndexResult({
    this.repoName = '',
    this.repoVersion = '',
    required this.sources,
  });

  bool get isEmpty => sources.isEmpty;
  int get totalCount => sources.length;
}

class RepoService {
  static const _reposKey = 'extension_repo_urls';
  static const _indexCachePrefix = 'ext_index_cache_';
  static const _corsProxy = 'https://corsproxy.io/?url=';

  final Dio _dio;

  RepoService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: {
                'User-Agent': 'MangaReader/1.0',
                'Accept': 'application/json, text/plain, */*',
              },
            ));

  String _effectiveUrl(String repoUrl) {
    // Add cache-busting to avoid GitHub CDN caching stale index
    final bust = DateTime.now().millisecondsSinceEpoch;
    final separator = repoUrl.contains('?') ? '&' : '?';
    final url = '$repoUrl${separator}_=$bust';
    if (kIsWeb) {
      return '$_corsProxy${Uri.encodeComponent(url)}';
    }
    return url;
  }

  /// Whether a persisted entry is a filesystem path rather than a remote URL.
  bool _isStoredPath(String entry) =>
      !entry.startsWith('http://') && !entry.startsWith('https://');

  /// Saved repos, with local paths resolved for the current app container.
  ///
  /// RepoForge stores its own `index.json` path here alongside remote URLs, and
  /// the iOS container is re-created on every re-sign — see [PortablePath].
  /// Without this, every RepoForge-authored source disappears about weekly.
  Future<List<String>> getSavedRepos() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_reposKey) ?? [];
    return [
      for (final entry in stored)
        if (_isStoredPath(entry)) await PortablePath.resolve(entry) else entry,
    ];
  }

  Future<void> addRepo(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final repos = prefs.getStringList(_reposKey) ?? [];
    final entry = _isLocalPath(url) ? await PortablePath.store(url) : url;
    for (final existing in repos) {
      if (existing == entry) return;
      if (_isStoredPath(existing) &&
          await PortablePath.resolve(existing) == url) {
        return;
      }
    }
    repos.add(entry);
    await prefs.setStringList(_reposKey, repos);
    await logger.info('Added repo: $url', category: LogCategory.repo);
  }

  Future<void> removeRepo(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final repos = prefs.getStringList(_reposKey) ?? [];
    final kept = <String>[];
    for (final entry in repos) {
      final resolved =
          _isStoredPath(entry) ? await PortablePath.resolve(entry) : entry;
      if (entry != url && resolved != url) kept.add(entry);
    }
    await prefs.setStringList(_reposKey, kept);
    await prefs.remove('$_indexCachePrefix${_cacheKey(url)}');
    await logger.info('Removed repo: $url', category: LogCategory.repo);
  }

  /// Returns true if [url] is a local file path or file:// URI.
  bool _isLocalPath(String url) =>
      url.startsWith('file://') ||
      url.startsWith('/') ||
      RegExp(r'^[A-Za-z]:[/\\]').hasMatch(url);

  /// Fetches and parses our index.json format.
  /// Supports both HTTP URLs and local file paths.
  Future<RepoIndexResult> fetchRepoIndex(String repoUrl) async {
    await logger.info('Fetching repo: $repoUrl', category: LogCategory.network);
    try {
      dynamic data;

      if (_isLocalPath(repoUrl)) {
        // Local file path
        final path = repoUrl.startsWith('file://')
            ? Uri.parse(repoUrl.startsWith('file:///')
                    ? repoUrl
                    : repoUrl.replaceFirst('file://', 'file:///'))
                .toFilePath()
            : repoUrl;
        final file = File(path);
        if (!await file.exists()) {
          throw Exception('Local index file not found: $path');
        }
        final content = await file.readAsString();
        data = jsonDecode(content);
        await logger.info('Loaded local repo: $path',
            category: LogCategory.repo);
      } else {
        // HTTP fetch
        final fetchUrl = _effectiveUrl(repoUrl);
        final response = await _dio.get<dynamic>(fetchUrl);
        data = response.data;
      }

      await logger.info('Repo data type: ${data.runtimeType}, '
          'length: ${data is String ? data.length : (data is Map ? data.keys.length : '?')}',
          category: LogCategory.repo);
      final result = _parseIndex(data, repoUrl);
      final allSources = List<MangaSource>.from(result.sources);

      // Mangayomi/keiyoushi repos split content across sibling index files
      // (index.json = manga, anime_index.json, novel_index.json). Those indexes
      // are top-level JSON arrays; the Foxlations format is a `{sources:[…]}`
      // object with no siblings. So only chase siblings when we fetched a bare
      // array over HTTP — pulling the anime/novel sources with the right type.
      if (!_isLocalPath(repoUrl) && data is List) {
        final base = _effectiveUrl(repoUrl);
        for (final kind in const ['anime', 'novel']) {
          final sib = _siblingIndexUrl(base, kind);
          if (sib == null) continue;
          try {
            final resp = await _dio.get<dynamic>(sib);
            final parsed = _parseIndex(resp.data, sib, defaultType: kind);
            allSources.addAll(parsed.sources);
            await logger.info('Imported ${parsed.sources.length} $kind sources',
                category: LogCategory.repo);
          } catch (_) {
            // Sibling index not present (e.g. Foxlations single-file repo) — fine.
          }
        }
      }

      final combined = RepoIndexResult(
        repoName: result.repoName,
        repoVersion: result.repoVersion,
        sources: allSources,
      );
      await logger.info('Parsed ${combined.totalCount} sources '
          '(repo: ${combined.repoName})',
          category: LogCategory.repo);

      // Cache the combined, normalized set (itemType resolved to strings) so the
      // cached read returns every type without re-fetching siblings.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_indexCachePrefix${_cacheKey(repoUrl)}',
        jsonEncode({
          'repoName': combined.repoName,
          'repoVersion': combined.repoVersion,
          'sources': allSources.map((s) => s.toJson()).toList(),
        }),
      );
      return combined;
    } on DioException catch (e) {
      final msg = e.response?.statusCode != null
          ? 'HTTP ${e.response!.statusCode}'
          : e.message ?? 'Connection failed';
      await logger.error('Fetch failed: $msg', category: LogCategory.network);
      throw Exception(msg);
    } catch (e) {
      await logger.error('Parse error: $e', category: LogCategory.repo);
      throw Exception('Failed to parse repo: $e');
    }
  }

  Future<RepoIndexResult> getCachedIndex(String repoUrl) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_indexCachePrefix${_cacheKey(repoUrl)}');
    if (raw == null) return const RepoIndexResult(sources: []);
    try {
      final data = jsonDecode(raw);
      return _parseIndex(data, repoUrl);
    } catch (_) {
      return const RepoIndexResult(sources: []);
    }
  }

  /// Given a manga `index.json` / `index.min.json` URL, return the sibling
  /// `{kind}_index(.min).json` URL in the same directory, or null if the input
  /// isn't a base manga index (so we don't chase siblings for typed/other files).
  static String? _siblingIndexUrl(String url, String kind) {
    final m = RegExp(r'^(.*/)index(\.min)?\.json(\?.*)?$', caseSensitive: false)
        .firstMatch(url);
    if (m == null) return null;
    return '${m.group(1)}${kind}_index${m.group(2) ?? ''}.json${m.group(3) ?? ''}';
  }

  /// The content type implied by a Mangayomi-style index filename, so anime /
  /// novel indexes tag their sources correctly even when a row omits itemType.
  static String _typeFromUrl(String url) {
    final u = url.toLowerCase();
    if (u.contains('anime_index') || u.contains('anime-index')) return 'anime';
    if (u.contains('novel_index') || u.contains('novel-index')) return 'novel';
    return 'manga';
  }

  /// Expand one index row into the source rows it actually represents.
  ///
  /// A Tachiyomi/keiyoushi entry describes an *extension*, which may ship
  /// several sources in a nested `sources[]` array (75 of keiyoushi's 1368 do).
  /// Collapsing those to one row made the extra sources unreachable, so each
  /// nested source becomes its own row: parent fields (pkg, version, nsfw…) are
  /// inherited, and the child's own id/name/lang/baseUrl win.
  List<Map<String, dynamic>> _expandSourceRows(Map<String, dynamic> entry) {
    final nested = entry['sources'];
    if (nested is! List || nested.isEmpty) return [entry];

    final rows = <Map<String, dynamic>>[];
    for (final child in nested.whereType<Map>()) {
      final merged = Map<String, dynamic>.from(entry)
        ..remove('sources')
        ..addAll(child.map((k, v) => MapEntry(k.toString(), v)));
      rows.add(merged);
    }
    return rows.isEmpty ? [entry] : rows;
  }

  RepoIndexResult _parseIndex(dynamic data, String repoUrl,
      {String? defaultType}) {
    if (data is String) {
      data = jsonDecode(data);
    }
    final dt = defaultType ?? _typeFromUrl(repoUrl);

    // Our format: { repoName, repoVersion, sources: [...] }
    if (data is Map<String, dynamic> && data.containsKey('sources')) {
      final rawList = data['sources'] as List;
      final name = data['repoName'] as String? ?? '';
      debugPrint('[repo] sources array has ${rawList.length} items');
      final sources = rawList
          .whereType<Map<String, dynamic>>()
          .map((e) {
            final s = MangaSource.fromJson(e, repoUrl,
                repoName: name, defaultType: dt);
            debugPrint('[repo] Source: ${s.name} (${s.id}) [${s.itemType}], url: ${s.sourceCodeUrl.isNotEmpty}');
            return s;
          })
          .where((s) => s.name.isNotEmpty)
          .toList();
      return RepoIndexResult(
        repoName: data['repoName'] as String? ?? '',
        repoVersion: data['repoVersion'] as String? ?? '',
        sources: sources,
      );
    }

    // Fallback: bare array (Mangayomi/keiyoushi index.json is a top-level array)
    if (data is List) {
      final sources = data
          .whereType<Map<String, dynamic>>()
          .expand(_expandSourceRows)
          .map((e) => MangaSource.fromJson(e, repoUrl, defaultType: dt))
          .where((s) => s.name.isNotEmpty)
          .toList();
      return RepoIndexResult(sources: sources);
    }

    throw Exception('Unrecognised index format');
  }

  String _cacheKey(String url) => url.hashCode.abs().toString();
}
