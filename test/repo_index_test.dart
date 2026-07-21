import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:manga_reader/core/models/source_model.dart';

/// A trimmed sample of the real keiyoushi index.min.json shape: entries describe
/// an *extension* with no top-level `id`, and the real ids live in `sources[]`.
const _keiyoushiSample = '''
[
  {"name":"Tachiyomi: AHottie","pkg":"eu.kanade.tachiyomi.extension.all.ahottie",
   "apk":"ahottie.apk","lang":"all","code":3,"version":"1.4.3","nsfw":1,
   "sources":[{"name":"AHottie","lang":"en","id":"8765","baseUrl":"https://ahottie.net"}]},
  {"name":"Tachiyomi: Akuma","pkg":"eu.kanade.tachiyomi.extension.all.akuma",
   "apk":"akuma.apk","lang":"all","code":3,"version":"1.4.10","nsfw":1,
   "sources":[{"name":"Akuma","lang":"en","id":"4321","baseUrl":"https://akuma.moe"}]},
  {"name":"Tachiyomi: MultiSrc","pkg":"eu.kanade.tachiyomi.extension.all.multi",
   "apk":"multi.apk","lang":"all","code":3,"version":"2.0.0","nsfw":0,
   "sources":[
     {"name":"Multi EN","lang":"en","id":"111","baseUrl":"https://m.example/en"},
     {"name":"Multi ES","lang":"es","id":"222","baseUrl":"https://m.example/es"},
     {"name":"Multi FR","lang":"fr","id":"333","baseUrl":"https://m.example/fr"}
   ]},
  {"name":"NoSources Ext","pkg":"eu.kanade.tachiyomi.extension.all.nosrc",
   "apk":"nosrc.apk","lang":"en","version":"1.0.0"}
]
''';

/// Mirrors RepoService._expandSourceRows (private), so the expansion contract
/// is pinned by a test even though the method itself isn't exported.
List<Map<String, dynamic>> expandRows(Map<String, dynamic> entry) {
  final nested = entry['sources'];
  if (nested is! List || nested.isEmpty) return [entry];
  final rows = <Map<String, dynamic>>[];
  for (final child in nested.whereType<Map>()) {
    rows.add(Map<String, dynamic>.from(entry)
      ..remove('sources')
      ..addAll(child.map((k, v) => MapEntry(k.toString(), v))));
  }
  return rows.isEmpty ? [entry] : rows;
}

List<MangaSource> parseAll(String raw) => (jsonDecode(raw) as List)
    .whereType<Map<String, dynamic>>()
    .expand(expandRows)
    .map((e) => MangaSource.fromJson(e, 'https://example/index.json'))
    .where((s) => s.name.isNotEmpty)
    .toList();

void main() {
  group('keiyoushi-style index', () {
    final sources = parseAll(_keiyoushiSample);

    test('multi-source extensions expand into one row per source', () {
      // 2 single-source (AHottie, Akuma) + 3 from MultiSrc + 1 with no
      // sources[] (NoSources Ext) = 6
      expect(sources.length, 6);
      expect(sources.where((s) => s.name.startsWith('Multi')).length, 3);
    });

    test('every source gets a non-empty id', () {
      expect(sources.where((s) => s.id.isEmpty), isEmpty);
    });

    test('ids are UNIQUE — the bug that flipped the whole catalogue', () {
      final ids = sources.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'duplicate ids make isInstalled() match unrelated sources');
    });

    test('nested ids are used verbatim when present', () {
      expect(sources.map((s) => s.id), containsAll(['8765', '4321', '111', '222', '333']));
    });

    test('an entry with no sources[] still gets a derived, stable id', () {
      final noSrc = sources.firstWhere((s) => s.name == 'NoSources Ext');
      expect(noSrc.id, isNotEmpty);
      // Re-parsing must yield the same id, or installs would orphan on restart.
      final again = parseAll(_keiyoushiSample)
          .firstWhere((s) => s.name == 'NoSources Ext');
      expect(again.id, noSrc.id);
    });

    test('child fields override the parent (name, lang, baseUrl)', () {
      final es = sources.firstWhere((s) => s.id == '222');
      expect(es.name, 'Multi ES');
      expect(es.lang, 'es');
      expect(es.baseUrl, 'https://m.example/es');
    });

    test('parent fields are inherited by each expanded source', () {
      final fr = sources.firstWhere((s) => s.id == '333');
      expect(fr.version, '2.0.0'); // from the parent extension entry
    });
  });
}
