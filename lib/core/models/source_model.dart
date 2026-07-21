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
      // Nothing on the row — fall back to the type implied by the index file.
      return defaultType;
    }

    String parseSourceLang() {
      final scl = json['sourceCodeLanguage'];
      if (scl is int) return scl == 1 ? 'js' : 'dart';
      if (scl is String && scl.trim().isNotEmpty) {
        final l = scl.trim().toLowerCase();
        return l == '1' ? 'js' : (l == '0' ? 'dart' : l);
      }
      return 'dart';
    }

    return MangaSource(
      id: asStr(json['id']),
      name: asStr(json['name'], 'Unknown'),
      baseUrl: asStr(json['baseUrl']),
      lang: asStr(json['lang'], 'en'),
      framework: asStr(json['framework'] ?? json['typeSource'], 'custom'),
      iconUrl: asStr(json['iconUrl']),
      sourceCodeUrl: asStr(json['sourceCodeUrl']),
      sourceCodeLanguage: parseSourceLang(),
      version: asStr(json['version'], '0.1.0'),
      isNsfw: asBool(json['isNsfw']),
      hasCloudflare: asBool(json['hasCloudflare']),
      dateFormat: asStr(json['dateFormat']),
      dateFormatLocale: asStr(json['dateFormatLocale']),
      apiUrl: asStr(json['apiUrl']),
      appMinVerReq: asStr(json['appMinVerReq'], '0.0.1'),
      config: (json['config'] as Map<String, dynamic>?) ?? {},
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

  String get displayName => name;
  bool get hasSourceCode => sourceCodeUrl.isNotEmpty;
  bool get isJsBased => sourceCodeLanguage == 'js' || sourceCodeLanguage == 'javascript';
  bool get isDartBased => sourceCodeLanguage == 'dart';
  bool get isAnime => itemType == 'anime';
  bool get isNovel => itemType == 'novel';
}
