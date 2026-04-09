import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/source_model.dart';
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

  Future<List<String>> getSavedRepos() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_reposKey) ?? [];
  }

  Future<void> addRepo(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final repos = prefs.getStringList(_reposKey) ?? [];
    if (repos.contains(url)) return;
    repos.add(url);
    await prefs.setStringList(_reposKey, repos);
    await logger.info('Added repo: $url', category: LogCategory.repo);
  }

  Future<void> removeRepo(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final repos = prefs.getStringList(_reposKey) ?? [];
    repos.remove(url);
    await prefs.setStringList(_reposKey, repos);
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
            ? Uri.parse(repoUrl).toFilePath()
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
      await logger.info('Parsed ${result.totalCount} sources '
          '(repo: ${result.repoName})',
          category: LogCategory.repo);

      // Cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_indexCachePrefix${_cacheKey(repoUrl)}',
        jsonEncode(data),
      );
      return result;
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

  RepoIndexResult _parseIndex(dynamic data, String repoUrl) {
    if (data is String) {
      data = jsonDecode(data);
    }

    // Our format: { repoName, repoVersion, sources: [...] }
    if (data is Map<String, dynamic> && data.containsKey('sources')) {
      final rawList = data['sources'] as List;
      final name = data['repoName'] as String? ?? '';
      debugPrint('[repo] sources array has ${rawList.length} items');
      final sources = rawList
          .whereType<Map<String, dynamic>>()
          .map((e) {
            final s = MangaSource.fromJson(e, repoUrl, repoName: name);
            debugPrint('[repo] Source: ${s.name} (${s.id}), url: ${s.sourceCodeUrl.isNotEmpty}');
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

    // Fallback: bare array
    if (data is List) {
      final sources = data
          .whereType<Map<String, dynamic>>()
          .map((e) => MangaSource.fromJson(e, repoUrl))
          .where((s) => s.name.isNotEmpty)
          .toList();
      return RepoIndexResult(sources: sources);
    }

    throw Exception('Unrecognised index format');
  }

  String _cacheKey(String url) => url.hashCode.abs().toString();
}
