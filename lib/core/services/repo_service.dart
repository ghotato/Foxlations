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
  ///
  /// Keiyoushi (and forks) moved their real index to `index.pb` (gzipped protobuf
  /// this app can't parse) and left `index.min.json` as a 2-entry "Outdated App"
  /// deprecation stub. The full JSON index is still served as `index.json` in the
  /// same directory — rewrite a pasted `.pb` URL to it. (A `.min.json` stub is
  /// handled AFTER parsing, since for other repos `.min.json` is the real index.)
  String _asJsonIndexUrl(String url) {
    final q = url.indexOf('?');
    final path = q >= 0 ? url.substring(0, q) : url;
    final query = q >= 0 ? url.substring(q) : '';
    if (path.endsWith('.pb')) {
      final slash = path.lastIndexOf('/');
      final dir = slash <= 0 ? '' : path.substring(0, slash);
      return '$dir/index.json$query';
    }
    return url;
  }

  /// The `index.json` sibling (same directory) of a repo index URL, or null.
  String? _fullJsonSibling(String url) {
    final q = url.indexOf('?');
    final path = q >= 0 ? url.substring(0, q) : url;
    final query = q >= 0 ? url.substring(q) : '';
    final slash = path.lastIndexOf('/');
    if (slash <= 0) return null;
    final sib = '${path.substring(0, slash)}/index.json$query';
    return sib == url ? null : sib;
  }

  bool _isDeprecationStub(List<MangaSource> sources) =>
      sources.isNotEmpty &&
      sources.every((s) => s.name.trim().toLowerCase() == 'outdated app');

  Future<RepoIndexResult> fetchRepoIndex(String repoUrl) async {
    // The URL the caller/saved-list holds, before any .pb→index.json rewrite or
    // deprecation-stub→sibling upgrade. Startup reads getCachedIndex(savedUrl), so the
    // cache MUST be keyed by this or keiyoushi/NovelSourcery show nothing until a manual
    // refresh (their saved .pb/.min.json differs from the index.json we actually fetch).
    final originalUrl = repoUrl;
    repoUrl = _asJsonIndexUrl(repoUrl);
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
      var result = _parseIndex(data, repoUrl);
      // Keiyoushi's index.min.json is a 2-entry "Outdated App" stub nudging old
      // apps to the new format; the real data is index.json in the same dir.
      // Transparently upgrade so a pasted stub URL still gets the full catalogue.
      if (_isDeprecationStub(result.sources)) {
        final full = _fullJsonSibling(repoUrl);
        if (full != null) {
          try {
            final resp = await _dio.get<dynamic>(_effectiveUrl(full));
            final upgraded = _parseIndex(resp.data, full);
            if (upgraded.sources.isNotEmpty && !_isDeprecationStub(upgraded.sources)) {
              result = upgraded;
              repoUrl = full;
              await logger.info(
                  'Upgraded deprecation stub → $full (${upgraded.sources.length} sources)',
                  category: LogCategory.repo);
            }
          } catch (_) {}
        }
      }
      final allSources = List<MangaSource>.from(result.sources);

      // Repos split content across sibling index files (index.json = manga,
      // plus anime/novel siblings). This used to run only when the main index
      // was a bare JSON array, on the assumption that the object-shaped
      // Foxlations format never has siblings. That assumption was wrong:
      // Foxtensions is object-shaped AND ships anime-index.min.json, so all of
      // its anime sources were unreachable — the app never asked for the file.
      // Shape tells us nothing about whether siblings exist, so always look.
      if (!_isLocalPath(repoUrl)) {
        final base = _effectiveUrl(repoUrl);
        final seen = allSources.map((s) => s.id).toSet();
        for (final kind in const ['anime', 'novel']) {
          for (final sib in siblingIndexUrls(base, kind)) {
            try {
              final resp = await _dio.get<dynamic>(sib);
              final parsed = _parseIndex(resp.data, sib, defaultType: kind);
              if (parsed.sources.isEmpty) continue;
              // A repo may publish both spellings, and a source could already
              // be listed in the main index — keep the first of each id.
              final fresh =
                  parsed.sources.where((s) => seen.add(s.id)).toList();
              allSources.addAll(fresh);
              await logger.info(
                  'Imported ${fresh.length} $kind sources from $sib',
                  category: LogCategory.repo);
              break; // this kind resolved; don't try the other spelling
            } catch (_) {
              // Not present under this spelling — try the next, then give up.
            }
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
      // cached read returns every type without re-fetching siblings. Key it under BOTH
      // the URL actually fetched AND the URL the user saved (they differ after a .pb /
      // deprecation-stub rewrite), so startup's getCachedIndex(savedUrl) hits.
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        'repoName': combined.repoName,
        'repoVersion': combined.repoVersion,
        'sources': allSources.map((s) => s.toJson()).toList(),
      });
      for (final key in {originalUrl, repoUrl}) {
        await prefs.setString('$_indexCachePrefix${_cacheKey(key)}', encoded);
      }
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
  /// Candidate URLs for a repo's `kind` (anime/novel) sibling index.
  ///
  /// Neither the separator nor the `.min` suffix is standardised, and a repo's
  /// sibling need not match the spelling of its own main index — Foxtensions
  /// serves `index.json` alongside `anime-index.min.json`. Only
  /// `anime_index.json` was tried before, so those siblings were never found
  /// and every source inside them was invisible to the app.
  ///
  /// So try the whole cross product, main index's own suffix first (the most
  /// likely match), and stop at the first one that parses. Misses cost a 404.
  @visibleForTesting
  static List<String> siblingIndexUrls(String url, String kind) {
    final m = RegExp(r'^(.*/)index(\.min)?\.json(\?.*)?$', caseSensitive: false)
        .firstMatch(url);
    if (m == null) return const [];
    final dir = m.group(1)!;
    final own = m.group(2) ?? ''; // '.min' when the main index is minified
    final other = own.isEmpty ? '.min' : '';
    final query = m.group(3) ?? '';
    return [
      for (final suffix in [own, other])
        for (final sep in const ['_', '-']) '$dir$kind${sep}index$suffix.json$query',
    ];
  }

  /// The content type implied by a Mangayomi-style index filename, so anime /
  /// novel indexes tag their sources correctly even when a row omits itemType.
  static String _typeFromUrl(String url) {
    final u = url.toLowerCase();
    if (u.contains('anime_index') || u.contains('anime-index')) return 'anime';
    if (u.contains('novel_index') || u.contains('novel-index')) return 'novel';
    return 'manga';
  }

  /// A friendly repo name for indexes that don't carry one.
  ///
  /// Mangayomi/keiyoushi-style indexes are a bare array with no `repoName`
  /// field, so every source installed from one had an empty repoName and the
  /// browse list fell back to showing its framework — which is "custom" for
  /// anything unrecognised. Git hosts name the repo after its owner (yuzono,
  /// keiyoushi, NovelSourcery), which is what users actually recognise;
  /// anything else falls back to the bare host.
  static String _repoNameFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (host.isEmpty) return ''; // a local file path, not a URL
      const gitHosts = {
        'raw.githubusercontent.com',
        'github.com',
        'gitlab.com',
        'codeberg.org',
      };
      if (gitHosts.contains(host) && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
      return host.startsWith('www.') ? host.substring(4) : host;
    } catch (_) {
      return '';
    }
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
      // An explicit repoName wins; an absent or blank one falls back to the URL
      // so the browse list never has to show the framework instead.
      final declared = (data['repoName'] as String? ?? '').trim();
      final name = declared.isNotEmpty ? declared : _repoNameFromUrl(repoUrl);
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
        repoName: name,
        repoVersion: data['repoVersion'] as String? ?? '',
        sources: sources,
      );
    }

    // keiyoushi / Aniyomi "extensionList" shape:
    //   { name, badgeLabel, ..., extensionList: { extensions: [...] } }
    // (or a top-level `extensions` array). Unwrap to the entry list, keeping the
    // repo's own `name`, then expand each entry's nested sources like the array path.
    List? nested;
    if (data is Map) {
      final el = data['extensionList'];
      if (el is Map && el['extensions'] is List) {
        nested = el['extensions'] as List;
      } else if (data['extensions'] is List) {
        nested = data['extensions'] as List;
      }
    }
    if (nested != null) {
      final declared =
          (data is Map ? (data['name'] as String? ?? '') : '').trim();
      final name = declared.isNotEmpty ? declared : _repoNameFromUrl(repoUrl);
      final sources = nested
          .whereType<Map<String, dynamic>>()
          .expand(_expandSourceRows)
          .map((e) => MangaSource.fromJson(e, repoUrl,
              repoName: name, defaultType: dt))
          .where((s) => s.name.isNotEmpty)
          .toList();
      return RepoIndexResult(repoName: name, sources: sources);
    }

    // Fallback: bare array (Mangayomi / yuzono index.min.json is a top-level array)
    if (data is List) {
      // No repoName in this format — derive one so installed sources are
      // labelled by where they came from rather than by their framework.
      final name = _repoNameFromUrl(repoUrl);
      final sources = data
          .whereType<Map<String, dynamic>>()
          .expand(_expandSourceRows)
          .map((e) => MangaSource.fromJson(e, repoUrl,
              repoName: name, defaultType: dt))
          .where((s) => s.name.isNotEmpty)
          .toList();
      return RepoIndexResult(repoName: name, sources: sources);
    }

    throw Exception('Unrecognised index format');
  }

  String _cacheKey(String url) => url.hashCode.abs().toString();
}
