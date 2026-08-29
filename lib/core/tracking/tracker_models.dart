/// Shared tracking data types used across all tracker services (AniList, Kitsu, …).

/// A reading status, normalized across services. Each tracker maps these to its
/// own vocabulary in its implementation.
enum TrackStatus {
  reading,
  planToRead,
  completed,
  onHold,
  dropped,
  rereading;

  String get label {
    switch (this) {
      case TrackStatus.reading:
        return 'Reading';
      case TrackStatus.planToRead:
        return 'Plan to read';
      case TrackStatus.completed:
        return 'Completed';
      case TrackStatus.onHold:
        return 'On hold';
      case TrackStatus.dropped:
        return 'Dropped';
      case TrackStatus.rereading:
        return 'Rereading';
    }
  }
}

/// A single search hit from a tracker's catalog.
class TrackSearchResult {
  final String mediaId;
  final String title;
  final String coverUrl;
  final int totalChapters; // 0 = unknown
  final String summary;
  final String url; // public link to the entry

  const TrackSearchResult({
    required this.mediaId,
    required this.title,
    this.coverUrl = '',
    this.totalChapters = 0,
    this.summary = '',
    this.url = '',
  });
}

/// The binding + current sync state for one manga on one tracker. Persisted per
/// library manga (keyed by the manga's uniqueKey + trackerId).
class TrackRecord {
  final String trackerId;
  final String mediaId;
  String title;
  String coverUrl;
  String url;
  TrackStatus status;
  int lastChapterRead;
  int totalChapters; // 0 = unknown
  double score; // 0–10 scale (normalized)

  TrackRecord({
    required this.trackerId,
    required this.mediaId,
    this.title = '',
    this.coverUrl = '',
    this.url = '',
    this.status = TrackStatus.reading,
    this.lastChapterRead = 0,
    this.totalChapters = 0,
    this.score = 0,
  });

  TrackRecord copyWith({
    TrackStatus? status,
    int? lastChapterRead,
    int? totalChapters,
    double? score,
    String? title,
    String? coverUrl,
    String? url,
  }) =>
      TrackRecord(
        trackerId: trackerId,
        mediaId: mediaId,
        title: title ?? this.title,
        coverUrl: coverUrl ?? this.coverUrl,
        url: url ?? this.url,
        status: status ?? this.status,
        lastChapterRead: lastChapterRead ?? this.lastChapterRead,
        totalChapters: totalChapters ?? this.totalChapters,
        score: score ?? this.score,
      );

  Map<String, dynamic> toJson() => {
        'trackerId': trackerId,
        'mediaId': mediaId,
        'title': title,
        'coverUrl': coverUrl,
        'url': url,
        'status': status.name,
        'lastChapterRead': lastChapterRead,
        'totalChapters': totalChapters,
        'score': score,
      };

  factory TrackRecord.fromJson(Map<dynamic, dynamic> j) => TrackRecord(
        trackerId: (j['trackerId'] ?? '').toString(),
        mediaId: (j['mediaId'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        coverUrl: (j['coverUrl'] ?? '').toString(),
        url: (j['url'] ?? '').toString(),
        status: TrackStatus.values.firstWhere(
          (s) => s.name == j['status'],
          orElse: () => TrackStatus.reading,
        ),
        lastChapterRead: (j['lastChapterRead'] as num?)?.toInt() ?? 0,
        totalChapters: (j['totalChapters'] as num?)?.toInt() ?? 0,
        score: (j['score'] as num?)?.toDouble() ?? 0,
      );
}
