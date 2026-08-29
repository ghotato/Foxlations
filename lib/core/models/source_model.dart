/// FNV-1a (64-bit) over [seed].
///
/// Deliberately NOT `String.hashCode`: Dart makes no guarantee that it is
/// stable across runs or VM versions, and installed sources are persisted by
/// id — an id that changed between launches would orphan the user's installs.
String _stableHash(String seed) {
  var hash = 0xcbf29ce484222325;
  for (final unit in seed.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16);
}

/// A manga source from our extension repository index.json.
/// Uses our own Foxlations format.
class MangaSource {
  final String id; // readable slug e.g. "mangadex-en"
  final String name;
  final String baseUrl;
  final String lang;
  final String framework; // "madara", "mangathemesia", "mangabox", "mmrcms", "nepnep", "custom"
  final String iconUrl;
  final String sourceCodeUrl;
  final String sourceCodeLanguage; // "dart" or "js"
  final String version;
  final bool isNsfw;
  final bool hasCloudflare;
  final String dateFormat;
  final String dateFormatLocale;
  final String apiUrl;
  final String appMinVerReq;
  final Map<String, dynamic> config;
  final String notes;
  final String repoUrl; // which repo this came from
  final String repoName; // friendly name of the repo
  final String itemType; // 'manga' or 'anime'

  const MangaSource({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.lang,
    required this.framework,
    required this.sourceCodeUrl,
    this.iconUrl = '',
    this.sourceCodeLanguage = 'dart',
    this.version = '0.1.0',
    this.isNsfw = false,
    this.hasCloudflare = false,
    this.dateFormat = '',
    this.dateFormatLocale = '',
    this.apiUrl = '',
    this.appMinVerReq = '0.0.1',
    this.config = const {},
    this.notes = '',
    this.repoUrl = '',
    this.repoName = '',
    this.itemType = 'manga',
  });

  /// Parse a source row from a repo index. Tolerant of two schemas:
  ///  - Foxlations: `itemType` string, `sourceCodeLanguage` string, `id` string.
  ///  - Mangayomi/keiyoushi: `itemType` int (0 manga / 1 anime / 2 novel) with an
  ///    `isManga` bool, `typeSource` (framework), `sourceCodeLanguage` int
  ///    (0 dart / 1 js), and a numeric `id`.
  /// [defaultType] is the content type inferred from the index filename (e.g.
  /// `anime_index.json` → anime), used when a row doesn't state its own type.
  factory MangaSource.fromJson(Map<String, dynamic> json, String repoUrl,
      {String repoName = '', String defaultType = 'manga'}) {
    String asStr(dynamic v, [String def = '']) =>
        v == null ? def : v.toString();
    bool asBool(dynamic v) => v is bool
        ? v
        : (v is int ? v != 0 : (v is String ? v.toLowerCase() == 'true' : false));

    // Two Kotlin-repo schemas to normalize:
    //  - Aniyomi / keiyoushi index.min.json stub: `pkg` + a bare `apk` filename.
    //  - keiyoushi FULL index.json: `packageName` + `resources.{apkUrl,jarUrl,
    //    iconUrl}` + `versionName`, with name/lang/baseUrl inside `sources[0]`.
    final pkgName = asStr(json['pkg']).isNotEmpty
        ? asStr(json['pkg'])
        : asStr(json['packageName']);
    final rawSources = json['sources'];
    final Map<String, dynamic>? firstSource =
        (rawSources is List && rawSources.isNotEmpty && rawSources.first is Map)
            ? Map<String, dynamic>.from(rawSources.first as Map)
            : null;
    final Map<String, dynamic>? resources = json['resources'] is Map
        ? Map<String, dynamic>.from(json['resources'] as Map)
        : null;
    // Prefer the top-level value; fall back to the first sub-source's.
    String field(String key, [String def = '']) {
      final v = json[key];
      if (v != null && v.toString().isNotEmpty) return v.toString();
      final fv = firstSource?[key];
      return (fv == null || fv.toString().isEmpty) ? def : fv.toString();
    }

    // Same, but tries several spellings — Mangayomi/Foxlations use `lang`/
    // `baseUrl`, while Aniyomi/keiyoushi sources use `language`/`homeUrl`. Read
    // all top-level keys first, then the first sub-source's, so an expanded
    // keiyoushi row (child `language`/`homeUrl` merged up) resolves correctly.
    String fieldMulti(List<String> keys, [String def = '']) {
      for (final k in keys) {
        final v = json[k];
        if (v != null && v.toString().isNotEmpty) return v.toString();
      }
      for (final k in keys) {
        final fv = firstSource?[k];
        if (fv != null && fv.toString().isNotEmpty) return fv.toString();
      }
      return def;
    }

    // keiyoushi tags every extension with a 3-value contentWarning enum
    // (CONTENT_WARNING_{SAFE,MIXED,NSFW}) — 100% of entries carry the field, so
    // treating any non-empty value as NSFW hid the entire catalogue behind the
    // "show NSFW" toggle. Only NSFW should hide; MIXED (e.g. MangaDex) and SAFE
    // stay visible. A free-text warning from another repo still counts if it
    // mentions NSFW/18+/adult.
    bool contentWarningIsNsfw() {
      final cw = asStr(json['contentWarning']).toUpperCase();
      return cw.contains('NSFW') || cw.contains('18+') || cw.contains('ADULT');
    }

    String parseItemType() {
      final it = json['itemType'];
      if (it is int) return it == 1 ? 'anime' : (it == 2 ? 'novel' : 'manga');
      if (it is String && it.trim().isNotEmpty) {
        final l = it.trim().toLowerCase();
        if (l == 'manga' || l == 'anime' || l == 'novel') return l;
        final n = int.tryParse(l);
        if (n != null) return n == 1 ? 'anime' : (n == 2 ? 'novel' : 'manga');
      }
      // Mangayomi flags anime rows with isManga=false (novels carry itemType=2).
      final isManga = json['isManga'];
      if (isManga is bool && !isManga) return 'anime';
      // Aniyomi/keiyoushi encode the type in the package name.
      final pkg = pkgName.toLowerCase();
      if (pkg.contains('animeextension')) return 'anime';
      if (pkg.contains('novelextension')) return 'novel';
      // Nothing on the row — fall back to the type implied by the index file.
      return defaultType;
    }

    // Tachiyomi/Aniyomi/keiyoushi rows are compiled Kotlin — they carry an `apk`
    // filename, a `resources.jarUrl`, or an `eu.kanade.tachiyomi.*` package, and
    // run in the embedded JVM (not the JS/Dart interpreters).
    bool looksKotlin() {
      final apk = asStr(json['apk']);
      final hasRes = resources != null &&
          (resources['jarUrl'] != null || resources['apkUrl'] != null);
      return apk.isNotEmpty ||
          hasRes ||
          pkgName.startsWith('eu.kanade.tachiyomi');
    }

    String parseSourceLang() {
      if (looksKotlin()) return 'kotlin';
      final scl = json['sourceCodeLanguage'];
      if (scl is int) return scl == 1 ? 'js' : 'dart';
      if (scl is String && scl.trim().isNotEmpty) {
        final l = scl.trim().toLowerCase();
        if (l == 'kotlin') return 'kotlin';
        return l == '1' ? 'js' : (l == '0' ? 'dart' : l);
      }
      return 'dart';
    }

    // Anime/keiyoushi repos serve the artifact next to the index — an Aniyomi
    // `apk` at `<repo-dir>/apk/<apk>`, keiyoushi a full `resources.jarUrl`. Stash
    // the download URL + package on config so installSource can fetch + convert.
    Map<String, dynamic> buildConfig() {
      final base = (json['config'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final cfg = Map<String, dynamic>.from(base);
      if (pkgName.isNotEmpty) cfg['pkg'] = pkgName;
      // keiyoushi index.json: full jar/apk URLs under `resources`.
      if (resources?['jarUrl'] != null) cfg['jarUrl'] = resources!['jarUrl'].toString();
      if (resources?['apkUrl'] != null) {
        cfg['apkUrl'] = resources!['apkUrl'].toString();
      } else {
        // Aniyomi index.min.json: a bare `apk` filename at `<repo-dir>/apk/<apk>`.
        final apk = asStr(json['apk']);
        if (apk.isNotEmpty) {
          if (apk.startsWith('http')) {
            cfg['apkUrl'] = apk;
          } else {
            final slash = repoUrl.lastIndexOf('/');
            final dir = slash <= 0 ? repoUrl : repoUrl.substring(0, slash);
            cfg['apkUrl'] = '$dir/apk/$apk';
          }
        }
      }
      return cfg;
    }

    // Tachiyomi/keiyoushi index entries carry NO top-level `id` — the real id
    // lives inside their `sources[]` array. Without a fallback every row parsed
    // to id '', so they all collided and installing one flipped the entire
    // catalogue to "installed". Derive a stable id from whatever identifies the
    // row instead.
    String resolveId() {
      final explicit = asStr(json['id']);
      if (explicit.isNotEmpty) return explicit;
      final seed = [
        pkgName,
        field('name'),
        field('lang'),
        field('baseUrl'),
      ].where((e) => e.isNotEmpty).join('|');
      return seed.isEmpty ? '' : _stableHash(seed);
    }

    // Where to find this source's icon.
    //
    // Mangayomi-style indexes carry `iconUrl` outright. Tachiyomi-style ones
    // (keiyoushi and its forks) carry none at all — 0 of keiyoushi's 1368
    // entries have the field — but they publish icons next to the index at
    // `<repo-root>/icon/<pkg>.png`, so derive it from the index URL. Left empty
    // when neither applies: the site's own favicon is an unreliable fallback
    // (sampled hosts returned 403 and 404 as often as an image), and the letter
    // tile the UI already draws beats a broken image.
    String resolveIconUrl() {
      final explicit = asStr(json['iconUrl']);
      if (explicit.isNotEmpty) return explicit;
      // keiyoushi index.json ships a full iconUrl under resources.
      if (resources?['iconUrl'] != null) return resources!['iconUrl'].toString();
      if (pkgName.isEmpty || repoUrl.isEmpty) return '';
      final slash = repoUrl.lastIndexOf('/');
      if (slash <= 0) return '';
      return '${repoUrl.substring(0, slash)}/icon/$pkgName.png';
    }

    return MangaSource(
      id: resolveId(),
      name: field('name', 'Unknown'),
      baseUrl: fieldMulti(const ['baseUrl', 'homeUrl']),
      lang: fieldMulti(const ['lang', 'language'], 'en'),
      framework: asStr(json['framework'] ?? json['typeSource'], 'custom'),
      iconUrl: resolveIconUrl(),
      sourceCodeUrl: asStr(json['sourceCodeUrl']),
      sourceCodeLanguage: parseSourceLang(),
      version: asStr(json['version']).isNotEmpty
          ? asStr(json['version'])
          : asStr(json['versionName'], '0.1.0'),
      isNsfw: asBool(json['isNsfw']) ||
          asBool(json['nsfw']) ||
          contentWarningIsNsfw(),
      hasCloudflare: asBool(json['hasCloudflare']),
      dateFormat: asStr(json['dateFormat']),
      dateFormatLocale: asStr(json['dateFormatLocale']),
      apiUrl: asStr(json['apiUrl']),
      appMinVerReq: asStr(json['appMinVerReq'], '0.0.1'),
      config: buildConfig(),
      notes: asStr(json['notes']),
      repoUrl: repoUrl,
      repoName: repoName,
      itemType: parseItemType(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'lang': lang,
        'framework': framework,
        'iconUrl': iconUrl,
        'sourceCodeUrl': sourceCodeUrl,
        'sourceCodeLanguage': sourceCodeLanguage,
        'version': version,
        'isNsfw': isNsfw,
        'hasCloudflare': hasCloudflare,
        'dateFormat': dateFormat,
        'dateFormatLocale': dateFormatLocale,
        'apiUrl': apiUrl,
        'appMinVerReq': appMinVerReq,
        'config': config,
        'notes': notes,
        'itemType': itemType,
      };

  MangaSource copyWith({
    Map<String, dynamic>? config,
    String? itemType,
    String? sourceCodeLanguage,
    String? baseUrl,
  }) {
    return MangaSource(
      id: id,
      name: name,
      baseUrl: baseUrl ?? this.baseUrl,
      lang: lang,
      framework: framework,
      iconUrl: iconUrl,
      sourceCodeUrl: sourceCodeUrl,
      sourceCodeLanguage: sourceCodeLanguage ?? this.sourceCodeLanguage,
      version: version,
      isNsfw: isNsfw,
      hasCloudflare: hasCloudflare,
      dateFormat: dateFormat,
      dateFormatLocale: dateFormatLocale,
      apiUrl: apiUrl,
      appMinVerReq: appMinVerReq,
      config: config ?? this.config,
      notes: notes,
      repoUrl: repoUrl,
      repoName: repoName,
      itemType: itemType ?? this.itemType,
    );
  }

  bool get isKotlinBased => sourceCodeLanguage == 'kotlin';

  String get displayName => name;
  bool get hasSourceCode => sourceCodeUrl.isNotEmpty;
  bool get isJsBased => sourceCodeLanguage == 'js' || sourceCodeLanguage == 'javascript';
  bool get isDartBased => sourceCodeLanguage == 'dart';
  bool get isAnime => itemType == 'anime';
  bool get isNovel => itemType == 'novel';
}
