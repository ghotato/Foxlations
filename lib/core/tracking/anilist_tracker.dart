import 'dart:convert';
import 'package:http/http.dart' as http;

import 'tracker.dart';
import 'tracker_models.dart';

/// AniList (anilist.co) — GraphQL API, OAuth2 **implicit grant** (no client
/// secret). The user authorizes at [authorizeUrl]; the pin page shows an access
/// token they paste back via [authenticateWithToken]. Token is valid ~1 year.
class AniListTracker extends Tracker {
  static const _graphql = 'https://graphql.anilist.co';

  String? _token;
  String? _username;

  @override
  String get id => 'anilist';
  @override
  String get name => 'AniList';
  @override
  int get colorValue => 0xFF02A9FF;
  @override
  TrackerAuthType get authType => TrackerAuthType.oauth;

  @override
  bool get isAuthenticated => _token != null;
  @override
  String? get username => _username;

  @override
  Map<String, dynamic> exportSession() =>
      {'token': _token, 'username': _username};

  @override
  void restoreSession(Map<String, dynamic> data) {
    _token = data['token'] as String?;
    _username = data['username'] as String?;
  }

  @override
  void logout() {
    _token = _username = null;
  }

  @override
  String authorizeUrl(String clientId) =>
      'https://anilist.co/api/v2/oauth/authorize'
      '?client_id=$clientId&response_type=token';

  Future<Map<String, dynamic>?> _query(String query,
      Map<String, dynamic> variables) async {
    final res = await http.post(
      Uri.parse(_graphql),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'query': query, 'variables': variables}),
    );
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['data'] as Map<String, dynamic>?;
  }

  @override
  Future<bool> authenticateWithToken(String token) async {
    _token = token.trim();
    final data = await _query('query { Viewer { id name } }', const {});
    final viewer = data?['Viewer'] as Map<String, dynamic>?;
    if (viewer == null) {
      _token = null;
      return false;
    }
    _username = viewer['name']?.toString();
    return true;
  }

  @override
  Future<List<TrackSearchResult>> search(String query) async {
    const q = r'''
query ($s: String) {
  Page(perPage: 15) {
    media(search: $s, type: MANGA) {
      id
      title { romaji english }
      chapters
      coverImage { large medium }
      description(asHtml: false)
      siteUrl
    }
  }
}''';
    final data = await _query(q, {'s': query});
    final media = (data?['Page']?['media'] as List?) ?? const [];
    return media.map((raw) {
      final m = raw as Map<String, dynamic>;
      final title = (m['title']?['english'] ?? m['title']?['romaji'] ?? 'Unknown')
          .toString();
      return TrackSearchResult(
        mediaId: m['id'].toString(),
        title: title,
        coverUrl:
            (m['coverImage']?['large'] ?? m['coverImage']?['medium'] ?? '')
                .toString(),
        totalChapters: (m['chapters'] as num?)?.toInt() ?? 0,
        summary: (m['description'] ?? '')
            .toString()
            .replaceAll(RegExp(r'<[^>]+>'), ''),
        url: (m['siteUrl'] ?? '').toString(),
      );
    }).toList();
  }

  @override
  Future<TrackRecord?> refresh(String mediaId) async {
    if (!isAuthenticated) return null;
    const q = r'''
query ($id: Int) {
  Media(id: $id) {
    chapters
    mediaListEntry {
      status
      progress
      score(format: POINT_10_DECIMAL)
    }
  }
}''';
    final data = await _query(q, {'id': int.tryParse(mediaId) ?? 0});
    final media = data?['Media'] as Map<String, dynamic>?;
    final entry = media?['mediaListEntry'] as Map<String, dynamic>?;
    if (entry == null) return null;
    return TrackRecord(
      trackerId: id,
      mediaId: mediaId,
      status: _fromAniStatus(entry['status']?.toString()),
      lastChapterRead: (entry['progress'] as num?)?.toInt() ?? 0,
      totalChapters: (media?['chapters'] as num?)?.toInt() ?? 0,
      score: (entry['score'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Future<bool> push(TrackRecord r) async {
    if (!isAuthenticated) return false;
    const m = r'''
mutation ($id: Int, $status: MediaListStatus, $progress: Int, $score: Float) {
  SaveMediaListEntry(mediaId: $id, status: $status, progress: $progress, score: $score) {
    id
  }
}''';
    final data = await _query(m, {
      'id': int.tryParse(r.mediaId) ?? 0,
      'status': _toAniStatus(r.status),
      'progress': r.lastChapterRead,
      'score': r.score,
    });
    return data?['SaveMediaListEntry'] != null;
  }

  String _toAniStatus(TrackStatus s) {
    switch (s) {
      case TrackStatus.reading:
        return 'CURRENT';
      case TrackStatus.planToRead:
        return 'PLANNING';
      case TrackStatus.completed:
        return 'COMPLETED';
      case TrackStatus.onHold:
        return 'PAUSED';
      case TrackStatus.dropped:
        return 'DROPPED';
      case TrackStatus.rereading:
        return 'REPEATING';
    }
  }

  TrackStatus _fromAniStatus(String? s) {
    switch (s) {
      case 'PLANNING':
        return TrackStatus.planToRead;
      case 'COMPLETED':
        return TrackStatus.completed;
      case 'PAUSED':
        return TrackStatus.onHold;
      case 'DROPPED':
        return TrackStatus.dropped;
      case 'REPEATING':
        return TrackStatus.rereading;
      default:
        return TrackStatus.reading;
    }
  }
}
