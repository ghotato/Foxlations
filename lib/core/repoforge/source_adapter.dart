import '../models/source_model.dart';
import 'mangayomi_js_generator.dart';

/// Bridges RepoForge's `Map`-based extension records to this app's
/// [MangaSource] model and JS source contract.
///
/// The vendored [MangayomiJsGenerator] emits a Mangayomi-shaped index row; this
/// adapter reconciles the field differences with what [MangaSource.fromJson]
/// expects (see ROADMAP §5c):
///   - `sourceCodeLanguage`: Mangayomi encodes JS as the int `1`; we use the
///     string `'js'` (passing the int would crash `fromJson`'s `as String?`).
///   - `framework`: absent from the Mangayomi row — carried from the ext map.
///   - `config`: Mangayomi's `additionalParams` maps to our `config`.
class RepoForgeSourceAdapter {
  /// The generated `.js` source text (a `class DefaultExtension extends
  /// MProvider`), ready to run in this app's `flutter_js` runtime.
  static String generateSourceCode(Map<String, dynamic> ext) =>
      MangayomiJsGenerator.generateSource(ext);

  /// Repo-relative path the JS should live at and be referenced from in
  /// index.json, e.g. `manga/src/en/foo.js`.
  static String pkgPath(Map<String, dynamic> ext) =>
      MangayomiJsGenerator.pkgPath(ext);

  /// A [MangaSource]-shaped index row for the generated source. [sourceCodeUrl]
  /// is typically the repo-relative [pkgPath] for local repos (resolved against
  /// the index.json directory at install time).
  static Map<String, dynamic> toIndexRow(
    Map<String, dynamic> ext, {
    String sourceCodeUrl = '',
  }) {
    final row = MangayomiJsGenerator.generateIndexEntry(
      ext,
      sourceCodeUrl: sourceCodeUrl,
    );

    // id: Mangayomi uses an int hashCode; our model uses a readable string slug.
    row['id'] = _slugId(
      (row['name'] as String?) ?? 'source',
      (row['lang'] as String?) ?? 'en',
    );

    // itemType: generator emits an int (0 manga / 1 anime / 2 novel); we use a
    // string.
    final it = row['itemType'];
    if (it is int) {
      row['itemType'] = it == 1 ? 'anime' : (it == 2 ? 'novel' : 'manga');
    } else if (it is! String) {
      row['itemType'] = 'manga';
    }

    // sourceCodeLanguage: Mangayomi int 1 -> our string 'js'.
    final scl = row['sourceCodeLanguage'];
    row['sourceCodeLanguage'] =
        (scl == 1 || scl == '1' || scl == 'js' || scl == 'javascript')
            ? 'js'
            : 'dart';

    // framework: not in the Mangayomi row — carry it from detection.
    final fw = ext['framework'];
    row['framework'] = (fw is String && fw.isNotEmpty) ? fw : 'custom';

    // additionalParams (Mangayomi) -> config (ours); may be an empty string.
    final addl = row['additionalParams'];
    row['config'] =
        addl is Map ? Map<String, dynamic>.from(addl) : <String, dynamic>{};

    return row;
  }

  /// Readable, stable id slug, e.g. `test-madara-en`.
  static String _slugId(String name, String lang) {
    final base = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final l = lang.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    final slug = base.isEmpty ? 'source' : base;
    return l.isEmpty ? slug : '$slug-$l';
  }

  /// Build a [MangaSource] directly from a detection/edit [ext] map.
  static MangaSource toMangaSource(
    Map<String, dynamic> ext, {
    String sourceCodeUrl = '',
    String repoUrl = '',
    String repoName = '',
  }) {
    return MangaSource.fromJson(
      toIndexRow(ext, sourceCodeUrl: sourceCodeUrl),
      repoUrl,
      repoName: repoName,
    );
  }
}
