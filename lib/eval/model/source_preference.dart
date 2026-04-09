class SourcePreference {
  final String key;
  final String title;
  final String? summary;
  final dynamic defaultValue;
  final String type; // 'switch', 'list', 'edit_text', 'multi_select'
  final List<SourcePreferenceEntry>? entries;

  const SourcePreference({
    required this.key,
    required this.title,
    this.summary,
    this.defaultValue,
    required this.type,
    this.entries,
  });

  factory SourcePreference.fromJson(Map<String, dynamic> json) {
    return SourcePreference(
      key: json['key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String?,
      defaultValue: json['defaultValue'],
      type: json['type'] as String? ?? 'switch',
      entries: (json['entries'] as List?)
          ?.map((e) => SourcePreferenceEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SourcePreferenceEntry {
  final String title;
  final dynamic value;

  const SourcePreferenceEntry({required this.title, required this.value});

  factory SourcePreferenceEntry.fromJson(Map<String, dynamic> json) {
    return SourcePreferenceEntry(
      title: json['title'] as String? ?? '',
      value: json['value'],
    );
  }
}
