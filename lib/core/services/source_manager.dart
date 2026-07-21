import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/source_model.dart';
import '../models/installed_source_model.dart';
import 'app_logger.dart';

class SourceManager {
  static const _installedKey = 'installed_sources_v1';
  static const _sourceCodePrefix = 'source_code_';

  /// Dev mode: override source code with local file paths.
  /// Set to null or empty map to disable.
  static const _mangaboxFw =
      'D:/projects/foxlations-extensions/dart/manga/multisrc/mangabox/mangabox.dart';
  static const _madaraFw =
      'D:/projects/foxlations-extensions/dart/manga/multisrc/madara/madara.dart';
  static const _mangathemesiaFw =
      'D:/projects/foxlations-extensions/dart/manga/multisrc/mangathemesia/mangathemesia.dart';

  static const _animeBase =
      'D:/projects/foxlations-extensions/dart/anime/src';

  static const Map<String, String> _devOverrides = {
    // MangaBox framework
    'manganato-en': _mangaboxFw,
    'mangabat-en': _mangaboxFw,
    'mangakakalot-en': _mangaboxFw,
    // MangaThemesia framework
    'ravenscans-en': _mangathemesiaFw,
    'infernalvoid-en': _mangathemesiaFw,
    // Madara framework (every madara source resolves to the same file)
    'coffeemanga-en': _madaraFw,
    'dragontea-en': _madaraFw,
    'harimanga-en': _madaraFw,
    'mangagalaxy-en': _madaraFw,
    'mangaclash-en': _madaraFw,
    'mangakomi-en': _madaraFw,
    'mangasushi-en': _madaraFw,
    'manhuaus-en': _madaraFw,
    'manhwaclan-en': _madaraFw,
    'pmscans-en': _madaraFw,
    'readmanhua-en': _madaraFw,
    's2manga-en': _madaraFw,
    'tappytoon-en': _madaraFw,
    // Manga custom sources
    'asurascans-en': 'D:/projects/foxlations-extensions/dart/manga/src/en/asurascans/asurascans.dart',
    'flamecomics-en': 'D:/projects/foxlations-extensions/dart/manga/src/en/flamecomics/flamecomics.dart',
    'kemono-en': 'D:/projects/foxlations-extensions/dart/manga/src/en/kemono/kemono.dart',
    'coomer-en': 'D:/projects/foxlations-extensions/dart/manga/src/en/coomer/coomer.dart',
    'webtoons-en': 'D:/projects/foxlations-extensions/dart/manga/src/multi/webtoons/webtoons.dart',
    'mangafire-en': 'D:/projects/foxlations-extensions/dart/manga/src/en/mangafire/mangafire.dart',
    'mangageko-en': 'D:/projects/foxlations-extensions/dart/manga/src/en/mangageko/mangageko.dart',
    'luscious-en': 'D:/projects/foxlations-extensions/dart/manga/src/en/luscious/luscious.dart',
    'naver-ko': 'D:/projects/foxlations-extensions/dart/manga/src/ko/naver/naver.dart',
    'hitomi-all': 'D:/projects/foxlations-extensions/dart/manga/src/all/hitomi/hitomi.dart',
    // Anime sources
    'allanime-en': '$_animeBase/en/allanime/allanime.dart',
    'animepahe-en': '$_animeBase/en/animepahe/animepahe.dart',
    'hahomoe-en': '$_animeBase/en/hahomoe/hahomoe.dart',
    'hanime-en': '$_animeBase/en/hanime/hanime.dart',
    'hianime-en': '$_animeBase/en/hianime/hianime.dart',
    'hstream-en': '$_animeBase/en/hstream/hstream.dart',
    'jable-all': '$_animeBase/all/jable/jable.dart',
    'kawaiifu-en': '$_animeBase/en/kawaiifu/kawaiifu.dart',
    'missav-all': '$_animeBase/all/missav/missav.dart',
    'newgrounds-en': '$_animeBase/en/newgrounds/newgrounds.dart',
    'oppaistream-en': '$_animeBase/en/oppaistream/oppaistream.dart',
    'rule34video-en': '$_animeBase/en/rule34video/rule34video.dart',
    'supjav-all': '$_animeBase/all/supjav/supjav.dart',
    'xnxx-all': '$_animeBase/all/xnxx/xnxx.dart',
    'xvideos-all': '$_animeBase/all/xvideos/xvideos.dart',
  };

  final Dio _dio;
  List<InstalledSource> _installed = [];
  bool _loaded = false;

  SourceManager({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
              headers: {
                'User-Agent': 'MangaReader/1.0',
                'Accept': 'text/plain, application/dart, application/javascript, */*',
              },
            ));

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_installedKey) ?? [];
    _installed = [];

    for (final jsonStr in raw) {
      try {
        final map = jsonDecode(jsonStr) as Map<String, dynamic>;
        final repoUrl = map['_repoUrl'] as String? ?? '';
        final source = MangaSource.fromJson(map, repoUrl);
        var sourceCode =
            prefs.getString('$_sourceCodePrefix${source.id}') ?? '';
        // Dev override: load from local file if available
        final devPath = _devOverrides[source.id];
        if (devPath != null) {
          try {
            final devFile = File(devPath);
            if (await devFile.exists()) {
              sourceCode = await devFile.readAsString();
            }
          } catch (_) {}
        }
        _installed.add(InstalledSource(
          source: source,
          sourceCode: sourceCode,
          installedAt: DateTime.parse(
            map['_installedAt'] as String? ?? DateTime.now().toIso8601String(),
          ),
        ));
      } catch (e) {
        await logger.error('Failed to load installed source',
            category: LogCategory.extension, detail: e.toString());
      }
    }

    await logger.info('Loaded ${_installed.length} installed sources',
        category: LogCategory.extension);
    _loaded = true;
  }

  Future<void> _saveInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _installed.map((inst) {
      final map = inst.source.toJson();
      map['_repoUrl'] = inst.source.repoUrl;
      map['_installedAt'] = inst.installedAt.toIso8601String();
      return jsonEncode(map);
    }).toList();
    await prefs.setStringList(_installedKey, list);
  }

  /// Resolves a sourceCodeUrl that may be relative against the repo base URL.
  String _resolveSourceCodeUrl(MangaSource source) {
    final url = source.sourceCodeUrl;
    if (url.isEmpty) return '';

    // Already absolute
    if (url.startsWith('http://') ||
        url.startsWith('https://') ||
        url.startsWith('file://') ||
        url.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[/\\]').hasMatch(url)) {
      return url;
    }

    // Relative path — resolve against the repo URL's directory
    final repoUrl = source.repoUrl;
    if (repoUrl.isEmpty) return url;

    // Strip the filename (index.json) from the repo URL to get the base dir
    final lastSlash = repoUrl.lastIndexOf('/');
    final baseUrl =
        lastSlash >= 0 ? repoUrl.substring(0, lastSlash + 1) : '$repoUrl/';
    return '$baseUrl$url';
  }

  Future<InstalledSource> installSource(MangaSource source) async {
    await _ensureLoaded();
    await logger.info('Installing "${source.name}"',
        category: LogCategory.install);

    String sourceCode = '';

    // Dev override: always load from local file if available (bypasses network).
    final devPath = _devOverrides[source.id];
    if (devPath != null) {
      try {
        final devFile = File(devPath);
        if (await devFile.exists()) {
          sourceCode = await devFile.readAsString();
          await logger.info(
              'Dev override: loaded ${sourceCode.length} chars for "${source.name}" from $devPath',
              category: LogCategory.install);
        }
      } catch (_) {}
    }

    final resolvedUrl = _resolveSourceCodeUrl(source);
    if (sourceCode.isEmpty && resolvedUrl.isNotEmpty) {
      try {
        if (resolvedUrl.startsWith('file://') ||
            resolvedUrl.startsWith('/') ||
            RegExp(r'^[A-Za-z]:[/\\]').hasMatch(resolvedUrl)) {
          // Local file path
          final path = resolvedUrl.startsWith('file://')
              ? Uri.parse(resolvedUrl).toFilePath()
              : resolvedUrl;
          final file = File(path);
          if (!await file.exists()) {
            throw Exception('Source file not found: $path');
          }
          sourceCode = await file.readAsString();
        } else {
          // HTTP download (cache-bust to avoid stale GitHub CDN)
          final bust = DateTime.now().millisecondsSinceEpoch;
          final sep = resolvedUrl.contains('?') ? '&' : '?';
          final response = await _dio.get<String>(
            '$resolvedUrl${sep}_=$bust',
            options: Options(responseType: ResponseType.plain),
          );
          sourceCode = response.data ?? '';
        }
        if (sourceCode.isEmpty) {
          throw Exception('Empty source code response');
        }
        await logger.info(
            'Loaded ${sourceCode.length} chars for "${source.name}" from $resolvedUrl',
            category: LogCategory.install);
      } catch (e) {
        await logger.error('Failed to download source code',
            category: LogCategory.install, detail: e.toString());
        throw Exception('Failed to download extension source code: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_sourceCodePrefix${source.id}', sourceCode);

    _installed.removeWhere((s) => s.source.id == source.id);

    final installed = InstalledSource(
      source: source,
      sourceCode: sourceCode,
      installedAt: DateTime.now(),
    );
    _installed.add(installed);
    await _saveInstalled();

    await logger.info('Installed "${source.name}"',
        category: LogCategory.install);
    return installed;
  }

  Future<void> uninstallSource(String sourceId) async {
    await _ensureLoaded();
    _installed.removeWhere((s) => s.source.id == sourceId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_sourceCodePrefix$sourceId');
    await _saveInstalled();
    await logger.info('Uninstalled source "$sourceId"',
        category: LogCategory.extension);
  }

  /// Re-downloads the source code for an installed source from its
  /// [sourceCodeUrl] and overwrites the SharedPreferences cache. Used to
  /// pick up upstream extension fixes without a full uninstall/reinstall.
  Future<void> refreshSourceCode(String sourceId) async {
    await _ensureLoaded();
    final idx = _installed.indexWhere((s) => s.source.id == sourceId);
    if (idx < 0) {
      throw Exception('Source not installed: $sourceId');
    }
    final installed = _installed[idx];
    final source = installed.source;
    await logger.info('Refreshing "${source.name}"',
        category: LogCategory.install);

    // Dev override: read from local file if present (preserves the Windows
    // dev flow where _ensureLoaded already hot-loads from disk).
    String newCode = '';
    final devPath = _devOverrides[sourceId];
    if (devPath != null) {
      try {
        final devFile = File(devPath);
        if (await devFile.exists()) {
          newCode = await devFile.readAsString();
        }
      } catch (_) {}
    }

    // Otherwise, (re)download from the resolved remote URL.
    if (newCode.isEmpty) {
      final resolvedUrl = _resolveSourceCodeUrl(source);
      if (resolvedUrl.isEmpty) {
        throw Exception('No source code URL for "${source.name}"');
      }
      try {
        if (resolvedUrl.startsWith('file://') ||
            resolvedUrl.startsWith('/') ||
            RegExp(r'^[A-Za-z]:[/\\]').hasMatch(resolvedUrl)) {
          final path = resolvedUrl.startsWith('file://')
              ? Uri.parse(resolvedUrl).toFilePath()
              : resolvedUrl;
          final file = File(path);
          if (!await file.exists()) {
            throw Exception('Source file not found: $path');
          }
          newCode = await file.readAsString();
        } else {
          final bust = DateTime.now().millisecondsSinceEpoch;
          final sep = resolvedUrl.contains('?') ? '&' : '?';
          final response = await _dio.get<String>(
            '$resolvedUrl${sep}_=$bust',
            options: Options(responseType: ResponseType.plain),
          );
          newCode = response.data ?? '';
        }
        if (newCode.isEmpty) {
          throw Exception('Empty source code response');
        }
      } catch (e) {
        await logger.error('Failed to refresh source code',
            category: LogCategory.install, detail: e.toString());
        throw Exception('Failed to refresh source code: $e');
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_sourceCodePrefix$sourceId', newCode);
    _installed[idx] = InstalledSource(
      source: source,
      sourceCode: newCode,
      installedAt: installed.installedAt,
    );

    await logger.info(
        'Refreshed "${source.name}" (${newCode.length} chars)',
        category: LogCategory.install);
  }

  /// Refreshes every installed source's code. Individual failures are logged
  /// but do not abort the batch. Returns the number of sources that updated.
  Future<int> refreshAllSourceCode() async {
    await _ensureLoaded();
    final ids = _installed.map((s) => s.source.id).toList();
    var count = 0;
    for (final id in ids) {
      try {
        await refreshSourceCode(id);
        count++;
      } catch (_) {
        // already logged inside refreshSourceCode
      }
    }
    return count;
  }

  bool isInstalled(String sourceId) =>
      _installed.any((s) => s.source.id == sourceId);

  Future<List<InstalledSource>> getInstalledSources() async {
    await _ensureLoaded();
    return List.unmodifiable(_installed);
  }

  Future<InstalledSource?> getInstalledSource(String sourceId) async {
    await _ensureLoaded();
    try {
      return _installed.firstWhere((s) => s.source.id == sourceId);
    } catch (_) {
      return null;
    }
  }
}
