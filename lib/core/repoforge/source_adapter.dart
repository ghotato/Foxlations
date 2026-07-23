import '../models/source_model.dart';
import 'mangayomi_dart_generator.dart';
import 'mangayomi_js_generator.dart';

/// Bridges RepoForge's `Map`-based extension records to this app's
/// [MangaSource] model and source contract.
///
/// Generated sources are **Dart**, not JavaScript. The JS path was replaced
/// because its HTTP bridge returned a response whose body never reached the
/// source — verified by running a generated JS source against a live site,
/// where the fetch reported no body and every selector consequently matched
/// nothing, making every generated JS source non-functional on both platforms.
/// Dart also avoids `flutter_js`'s per-platform engine split (QuickJS on
/// Android, JavaScriptCore on iOS) and is what `lib/eval/lib.dart` already
/// defaults to, so generated sources now run on the same runtime as the
/// hand-written ones.
///
/// [MangayomiJsGenerator] is still used for the index row and detection spec;
/// only code emission moved.
class RepoForgeSourceAdapter {
  /// The generated `.dart` source text (a `class … extends MProvider`), ready
  /// to run in this app's d4rt runtime.
  static String generateSourceCode(Map<String, dynamic> ext) =>
      MangayomiDartGenerator.generateSource(ext);

  /// Repo-relative path the source should live at and be referenced from in
  /// index.json, e.g. `manga/src/en/foo.dart`.
  static String pkgPath(Map<String, dynamic> ext) =>
      MangayomiDartGenerator.pkgPath(ext);

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

    // Always 'dart': the emitted code is Dart regardless of what the Mangayomi
    // row says, and this field decides which runtime lib/eval/lib.dart hands
    // the source to. Leaving the row's value here would route Dart code into
    // the JS engine.
    row['sourceCodeLanguage'] = 'dart';

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
