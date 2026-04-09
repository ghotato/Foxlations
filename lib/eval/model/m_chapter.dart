class MChapter {
  String? name;
  String? url;
  String? dateUpload;
  String? scanlator;

  MChapter({
    this.name,
    this.url,
    this.dateUpload,
    this.scanlator,
  });

  factory MChapter.fromJson(Map<String, dynamic> json) {
    return MChapter(
      name: json['name'] as String?,
      url: json['url'] as String?,
      dateUpload: json['dateUpload']?.toString(),
      scanlator: json['scanlator'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'dateUpload': dateUpload,
        'scanlator': scanlator,
      };
}
