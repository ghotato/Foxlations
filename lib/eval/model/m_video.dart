class MVideo {
  String url;
  String quality;
  String originalUrl;
  Map<String, String>? headers;
  List<MTrack>? subtitles;
  List<MTrack>? audios;

  /// Source-provided intro/outro markers (Aniyomi `timestamps`), used for
  /// Skip Intro / Skip Outro. Usually empty — few sources supply them.
  List<MTimeStamp>? timestamps;

  MVideo(
    this.url,
    this.quality,
    this.originalUrl, {
    this.headers,
    this.subtitles,
    this.audios,
    this.timestamps,
  });
}

class MTrack {
  String? file;
  String? label;

  MTrack({this.file, this.label});
}

class MTimeStamp {
  final double start; // seconds
  final double end; // seconds
  final String name; // e.g. "Intro"
  final String type; // "Opening" / "Ending" / "Recap" / "MixedOp" / "Other"

  MTimeStamp({
    required this.start,
    required this.end,
    this.name = '',
    this.type = '',
  });

  bool get isOutro =>
      type == 'Ending' || name.toLowerCase().contains('outro') ||
      name.toLowerCase().contains('ending');
}
