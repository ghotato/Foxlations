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
  });

  factory MangaSource.fromJson(Map<String, dynamic> json, String repoUrl, {String repoName = ''}) {
    return MangaSource(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      baseUrl: json['baseUrl'] as String? ?? '',
      lang: json['lang'] as String? ?? 'en',
      framework: json['framework'] as String? ?? 'custom',
      iconUrl: json['iconUrl'] as String? ?? '',
      sourceCodeUrl: json['sourceCodeUrl'] as String? ?? '',
      sourceCodeLanguage: json['sourceCodeLanguage'] as String? ?? 'dart',
      version: json['version'] as String? ?? '0.1.0',
      isNsfw: json['isNsfw'] as bool? ?? false,
      hasCloudflare: json['hasCloudflare'] as bool? ?? false,
      dateFormat: json['dateFormat'] as String? ?? '',
      dateFormatLocale: json['dateFormatLocale'] as String? ?? '',
      apiUrl: json['apiUrl'] as String? ?? '',
      appMinVerReq: json['appMinVerReq'] as String? ?? '0.0.1',
      config: (json['config'] as Map<String, dynamic>?) ?? {},
      notes: json['notes'] as String? ?? '',
      repoUrl: repoUrl,
      repoName: repoName,
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
      };

  String get displayName => name;
  bool get hasSourceCode => sourceCodeUrl.isNotEmpty;
  bool get isJsBased => sourceCodeLanguage == 'js' || sourceCodeLanguage == 'javascript';
  bool get isDartBased => sourceCodeLanguage == 'dart';
}
