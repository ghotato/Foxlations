class MSource {
  final int id;
  final String name;
  final String baseUrl;
  final String lang;
  final bool hasCloudflare;
  final String? apiUrl;
  final String? dateFormat;
  final String? dateFormatLocale;
  final String? additionalParams;
  final String? notes;

  const MSource({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.lang,
    this.hasCloudflare = false,
    this.apiUrl,
    this.dateFormat,
    this.dateFormatLocale,
    this.additionalParams,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'lang': lang,
        'hasCloudflare': hasCloudflare,
        'apiUrl': apiUrl,
        'dateFormat': dateFormat,
        'dateFormatLocale': dateFormatLocale,
        'additionalParams': additionalParams,
        'notes': notes,
      };

  factory MSource.fromJson(Map<String, dynamic> json) {
    return MSource(
      id: json['id'] as int? ?? 0,
      name: json['name'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      lang: json['lang'] as String? ?? 'en',
      hasCloudflare: json['hasCloudflare'] as bool? ?? false,
      apiUrl: json['apiUrl'] as String?,
      dateFormat: json['dateFormat'] as String?,
      dateFormatLocale: json['dateFormatLocale'] as String?,
      additionalParams: json['additionalParams'] as String?,
      notes: json['notes'] as String?,
    );
  }
}
