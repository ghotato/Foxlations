import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/portable_path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/source_model.dart';
import '../models/installed_source_model.dart';
import '../../eval/kotlin/jvm_bridge.dart';
import 'app_logger.dart';

class SourceManager {
  static const _installedKey = 'installed_sources_v1';
  static const _sourceCodePrefix = 'source_code_';

  /// Dev-only hot-loading of source code from a local checkout, keyed by source
  /// id. MUST be empty in shipped builds: it previously held a developer's
  /// Windows checkout paths (D:/projects/foxlations-extensions/…), which don't
  /// exist on any user's machine. Those entries were guarded by File.exists()
  /// so they failed silently — but they are exactly the kind of hardcoded path
  /// that has no business in a release, so they're gone. Sources load from
  /// their repo's sourceCodeUrl instead.
  static const Map<String, String> _devOverrides = <String, String>{};

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
        var source = MangaSource.fromJson(map, repoUrl);
        // Re-expand the Kotlin jar path to the current app container. iOS moves the
        // Documents container (new UUID) on every re-sign, so a persisted absolute
        // path goes stale — PortablePath repairs both the tokenised form and a legacy
        // absolute path whose file still exists under today's container.
        final storedJar = source.config['jar'];
        if (source.isKotlinBased && storedJar is String && storedJar.isNotEmpty) {
          final resolved = await PortablePath.resolve(storedJar);
          if (resolved != storedJar) {
            source = source.copyWith(
                config: {...source.config, 'jar': resolved});
          }
        }
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
    final list = <String>[];
    for (final inst in _installed) {
      final map = inst.source.toJson();
      map['_repoUrl'] = inst.source.repoUrl;
      map['_installedAt'] = inst.installedAt.toIso8601String();
      // Persist the container-specific Kotlin jar path in tokenised form so it
      // survives an iOS re-sign. Copy the config first — toJson reuses the live
      // config map, and mutating it would tokenise the in-memory (absolute) path too.
      final jar = inst.source.config['jar'];
      if (jar is String && jar.isNotEmpty) {
        final cfg = Map<String, dynamic>.from(inst.source.config);
        cfg['jar'] = await PortablePath.store(jar);
        map['config'] = cfg;
      }
      list.add(jsonEncode(map));
    }
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

    // Kotlin / Tachiyomi / Aniyomi extension: a compiled artifact, not
    // interpretable code. Download the apk/jar, convert an apk to a loadable jar
    // via the embedded JVM (which also decodes the entry class from the binary
    // manifest), record {jar,entry} on the source, and route by the manifest's
    // real content type. This is what makes anime (Aniyomi) sources work — the
    // app is a compatibility layer; the user supplies the source.
    if (source.isKotlinBased) {
      return _installKotlin(source);
    }

    final resolvedUrl = _resolveSourceCodeUrl(source);

    // No interpretable code AND no URL to fetch it from. A JS/Dart repo entry that
    // ships neither code nor a URL has nothing to execute (Kotlin artifacts are
    // handled above). Refuse at install time with an honest message.
    if (sourceCode.isEmpty && resolvedUrl.isEmpty) {
      throw Exception(
          'This source has no runnable code — no source URL and no Kotlin '
          'apk/jar to convert. Try a Mangayomi- or Aniyomi-compatible repo.');
    }

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
          // Reject cleartext: the fetched bytes ARE executed as an extension,
          // so an on-path attacker rewriting an http:// response would deliver
          // arbitrary code. https only.
          if (resolvedUrl.startsWith('http://')) {
            throw Exception(
                'Refusing to load a source over plain HTTP (use https): '
                '$resolvedUrl');
          }
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

  /// Install a compiled Kotlin (Tachiyomi / Aniyomi / keiyoushi) extension.
  ///
  /// Downloads the artifact from config['apkUrl'] (Aniyomi anime, dex) or
  /// config['jarUrl'] (keiyoushi, already a jar) into the app's writable
  /// extensions dir. An apk is handed to the embedded JVM's `convertApk`, which
  /// runs Suwayomi's own dex→jar and reads the entry class + real content type
  /// (anime/manga/novel) from the binary manifest. The resulting jar path + entry
  /// are recorded on the source's config so `getExtensionService` builds a
  /// `KotlinExtensionService` that loads it.
  Future<InstalledSource> _installKotlin(MangaSource source) async {
    final cfg = Map<String, dynamic>.from(source.config);
    final apkUrl = (cfg['apkUrl'] ?? '').toString();
    final jarUrl = (cfg['jarUrl'] ?? '').toString();
    if (apkUrl.isEmpty && jarUrl.isEmpty) {
      throw Exception(
          'This Kotlin extension has no apk/jar download URL in its repo entry.');
    }

    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/extensions');
    await dir.create(recursive: true);
    final safeId = source.id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final jarPath = '${dir.path}/$safeId.jar';

    String entry = (cfg['entry'] ?? '').toString();
    String itemType = source.itemType;

    if (Platform.isAndroid) {
      // Android loads the extension APK's dex DIRECTLY on ART (Mihon-style) — no jar and
      // no dex2jar. keiyoushi's jarUrl is JVM bytecode (not loadable on ART), so always
      // use the apk; the native host reads the entry class from the apk manifest.
      final apkPath = '${dir.path}/$safeId.apk';
      final url = apkUrl.isNotEmpty ? apkUrl : jarUrl;
      if (url.isEmpty) {
        throw Exception('This extension has no APK to load on Android.');
      }
      await _download(url, apkPath);
      cfg['jar'] = apkPath;
    } else if (jarUrl.isNotEmpty) {
      // Embedded-JVM platforms (iOS/desktop): keiyoushi 1.6 ships a ready-to-load jar
      // with a plaintext AndroidManifest — no on-device dex→jar needed.
      await _download(jarUrl, jarPath);
      cfg['jar'] = jarPath;
    } else {
      final apkPath = '${dir.path}/$safeId.apk';
      await _download(apkUrl, apkPath);
      final res = await FoxJvm.invoke(
          {'method': 'convertApk', 'apk': apkPath, 'out': jarPath});
      final m = Map<String, dynamic>.from(res as Map);
      final e = (m['entry'] ?? '').toString();
      if (e.isNotEmpty) entry = e;
      final kind = (m['kind'] ?? '').toString();
      if (kind == 'anime' || kind == 'novel' || kind == 'manga') itemType = kind;
      try {
        await File(apkPath).delete(); // the jar is what we keep
      } catch (_) {}
      // Absolute path in memory (the sync getExtensionService reads it directly);
      // _saveInstalled tokenises it and _ensureLoaded re-expands it so it survives the
      // iOS container UUID changing on every re-sign.
      cfg['jar'] = jarPath;
    }
    if (entry.isNotEmpty) cfg['entry'] = entry;
    final updated = source.copyWith(config: cfg, itemType: itemType);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_sourceCodePrefix${source.id}', '');

    _installed.removeWhere((s) => s.source.id == source.id);
    final installed = InstalledSource(
      source: updated,
      sourceCode: '',
      installedAt: DateTime.now(),
    );
    _installed.add(installed);
    await _saveInstalled();

    await logger.info(
        'Installed Kotlin $itemType source "${source.name}" '
        '(jar=$jarPath, entry=$entry)',
        category: LogCategory.install);
    return installed;
  }

  Future<void> _download(String url, String outPath) async {
    // The bytes become a loadable jar/dex, so refuse an on-path-rewritable http://.
    if (url.startsWith('http://')) {
      throw Exception('Refusing to download an extension over plain HTTP: $url');
    }
    final bust = DateTime.now().millisecondsSinceEpoch;
    final sep = url.contains('?') ? '&' : '?';
    final resp = await _dio.get<List<int>>(
      '$url${sep}_=$bust',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = resp.data ?? const <int>[];
    if (bytes.isEmpty) throw Exception('Empty download from $url');
    // A previously-loaded extension apk was marked read-only (Android 14+ won't load
    // a writable dex — see ExtensionHost), so overwriting it in place would fail.
    // Delete first: removing a read-only file is allowed (the parent dir is writable).
    final out = File(outPath);
    if (await out.exists()) {
      try {
        await out.delete();
      } catch (_) {}
    }
    await out.writeAsBytes(bytes);
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
