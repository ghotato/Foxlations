import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/source_model.dart';
import '../services/repo_service.dart';
import 'source_adapter.dart';

/// Writes in-app-generated sources into a single on-device "My Sources" repo
/// and registers it like any other extension repo.
///
/// The repo is a normal Mangayomi/Foxlations tree:
///   {docs}/Foxlations/local_repos/my_sources/
///     index.json                       ← { repoName, repoVersion, sources:[…] }
///     manga/src/{lang}/{pkg}.dart       ← generated source (relative sourceCodeUrl)
///
/// Because `sourceCodeUrl` is stored **relative**, the existing install path
/// (`SourceManager._resolveSourceCodeUrl` + local-file loading) resolves it
/// against the index.json directory — no server needed.
class LocalRepoService {
  static const repoDisplayName = 'My Sources';

  final RepoService _repoService;
  LocalRepoService({RepoService? repoService})
      : _repoService = repoService ?? RepoService();

  Future<Directory> _repoDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir =
        Directory('${docs.path}/Foxlations/local_repos/my_sources');
    await dir.create(recursive: true);
    return dir;
  }

  /// Absolute path to the local repo's index.json (created lazily).
  Future<String> indexPath() async => '${(await _repoDir()).path}/index.json';

  Map<String, dynamic> _emptyIndex() => {
        'repoName': repoDisplayName,
        'repoVersion': '1.0.0',
        'sources': <Map<String, dynamic>>[],
      };

  Future<Map<String, dynamic>> _readIndex(Directory dir) async {
    final file = File('${dir.path}/index.json');
    if (!await file.exists()) return _emptyIndex();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic> && decoded['sources'] is List) {
        return decoded;
      }
    } catch (_) {}
    return _emptyIndex();
  }

  /// Generate + write a source from a detection/edit [ext] map, merge it into
  /// index.json (replacing any existing source with the same id), and register
  /// the repo. Returns the resulting [MangaSource].
  Future<MangaSource> createOrUpdateSource(Map<String, dynamic> ext) async {
    final dir = await _repoDir();
    final rel = RepoForgeSourceAdapter.pkgPath(ext); // manga/src/en/foo.dart
    final js = RepoForgeSourceAdapter.generateSourceCode(ext);

    // Write the JS at its repo-relative path.
    final jsFile = File('${dir.path}/$rel');
    await jsFile.parent.create(recursive: true);
    await jsFile.writeAsString(js);

    // Build the index row with a RELATIVE sourceCodeUrl.
    final row = RepoForgeSourceAdapter.toIndexRow(ext, sourceCodeUrl: rel);

    // Merge into index.json (replace by id).
    final index = await _readIndex(dir);
    final sources = (index['sources'] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    sources.removeWhere((s) => s['id'] == row['id']);
    sources.add(row);
    index['sources'] = sources;

    final idxFile = File('${dir.path}/index.json');
    await idxFile
        .writeAsString(const JsonEncoder.withIndent('  ').convert(index));

    // Register the repo (idempotent) and prime its cache.
    await _repoService.addRepo(idxFile.path);
    await _repoService.fetchRepoIndex(idxFile.path);

    return RepoForgeSourceAdapter.toMangaSource(
      ext,
      sourceCodeUrl: rel,
      repoUrl: idxFile.path,
      repoName: repoDisplayName,
    );
  }

  /// All sources currently in the local repo.
  Future<List<MangaSource>> listSources() async {
    final dir = await _repoDir();
    final idxFile = File('${dir.path}/index.json');
    if (!await idxFile.exists()) return [];
    final result = await _repoService.fetchRepoIndex(idxFile.path);
    return result.sources;
  }

  /// Export the whole local repo as a single portable bundle: every index row
  /// with its generated JS embedded inline (`code`). Shareable / backup-able.
  Future<String> exportBundle() async {
    final dir = await _repoDir();
    final index = await _readIndex(dir);
    final rows = (index['sources'] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    for (final row in rows) {
      final rel = row['sourceCodeUrl'];
      if (rel is String && rel.isNotEmpty && !rel.startsWith('http')) {
        final f = File('${dir.path}/$rel');
        row['code'] = await f.exists() ? await f.readAsString() : '';
      }
    }
    return const JsonEncoder.withIndent('  ').convert({
      'repoName': index['repoName'] ?? repoDisplayName,
      'repoVersion': index['repoVersion'] ?? '1.0.0',
      'exportedFrom': 'Foxlations RepoForge',
      'sources': rows,
    });
  }

  /// Import a bundle produced by [exportBundle]: write each embedded JS back to
  /// its path and merge the rows into index.json. Returns the count imported.
  Future<int> importBundle(String jsonStr) async {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! Map || decoded['sources'] is! List) {
      throw const FormatException('Not a RepoForge source bundle.');
    }
    final dir = await _repoDir();
    final index = await _readIndex(dir);
    final sources = (index['sources'] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    var imported = 0;
    for (final raw in (decoded['sources'] as List)) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      final code = row.remove('code');
      final rel = row['sourceCodeUrl'];
      if (rel is String && rel.isNotEmpty && !rel.startsWith('http') &&
          code is String && code.isNotEmpty) {
        final f = File('${dir.path}/$rel');
        await f.parent.create(recursive: true);
        await f.writeAsString(code);
      }
      sources.removeWhere((s) => s['id'] == row['id']);
      sources.add(row);
      imported++;
    }
    index['sources'] = sources;
    final idxFile = File('${dir.path}/index.json');
    await idxFile
        .writeAsString(const JsonEncoder.withIndent('  ').convert(index));
    await _repoService.addRepo(idxFile.path);
    await _repoService.fetchRepoIndex(idxFile.path);
    return imported;
  }

  /// Remove a generated source (its index row + JS file) by id.
  Future<void> deleteSource(String id) async {
    final dir = await _repoDir();
    final index = await _readIndex(dir);
    final sources = (index['sources'] as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    final removed = sources.where((s) => s['id'] == id).toList();
    sources.removeWhere((s) => s['id'] == id);
    index['sources'] = sources;

    final idxFile = File('${dir.path}/index.json');
    await idxFile
        .writeAsString(const JsonEncoder.withIndent('  ').convert(index));

    // Best-effort delete of the JS file(s).
    for (final s in removed) {
      final rel = s['sourceCodeUrl'];
      if (rel is String && rel.isNotEmpty && !rel.startsWith('http')) {
        final f = File('${dir.path}/$rel');
        if (await f.exists()) await f.delete();
      }
    }

    // Refresh the registered repo cache.
    await _repoService.fetchRepoIndex(idxFile.path);
  }
}
