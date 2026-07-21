import 'dart:convert';
import 'package:http/http.dart' as http;

import 'tracker.dart';
import 'tracker_models.dart';

/// Kitsu (kitsu.io) — OAuth password grant, so it needs no app registration:
/// the user just enters their Kitsu email + password.
class KitsuTracker extends Tracker {
  static const _oauth = 'https://kitsu.io/api/oauth/token';
  static const _api = 'https://kitsu.io/api/edge';
  static const _jsonApi = 'application/vnd.api+json';

  String? _accessToken;
  String? _refreshToken;
  String? _userId;
  String? _username;

  @override
  String get id => 'kitsu';
  @override
  String get name => 'Kitsu';
  @override
  int get colorValue => 0xFFF75239;
  @override
  TrackerAuthType get authType => TrackerAuthType.credentials;

  @override
  bool get isAuthenticated => _accessToken != null && _userId != null;
  @override
  String? get username => _username;

  @override
  Map<String, dynamic> exportSession() => {
        'accessToken': _accessToken,
        'refreshToken': _refreshToken,
        'userId': _userId,
        'username': _username,
      };

  @override
  void restoreSession(Map<String, dynamic> data) {
    _accessToken = data['accessToken'] as String?;
    _refreshToken = data['refreshToken'] as String?;
    _userId = data['userId'] as String?;
    _username = data['username'] as String?;
  }

  @override
  void logout() {
    _accessToken = _refreshToken = _userId = _username = null;
  }

  Map<String, String> get _authHeaders => {
        'Accept': _jsonApi,
        'Content-Type': _jsonApi,
        if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
      };

  @override
  Future<bool> authenticateWithCredentials(
      String username, String password) async {
    final res = await http.post(
      Uri.parse(_oauth),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'password',
        'username': username,
        'password': password,
      },
    );
    if (res.statusCode != 200) return false;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String?;
    _refreshToken = data['refresh_token'] as String?;
    if (_accessToken == null) return false;
    return _fetchSelf();
  }

  Future<bool> _fetchSelf() async {
    final res = await http.get(
      Uri.parse('$_api/users?filter[self]=true'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) return false;
    final list = (jsonDecode(res.body)['data'] as List?) ?? const [];
    if (list.isEmpty) return false;
    final u = list.first as Map<String, dynamic>;
    _userId = u['id']?.toString();
    _username = (u['attributes']?['name'] ?? u['attributes']?['slug'])?.toString();
    return _userId != null;
  }

  @override
  Future<List<TrackSearchResult>> search(String query) async {
    final res = await http.get(
      Uri.parse(
          '$_api/manga?filter[text]=${Uri.encodeQueryComponent(query)}&page[limit]=15'),
      headers: {'Accept': _jsonApi},
    );
    if (res.statusCode != 200) return [];
    final list = (jsonDecode(res.body)['data'] as List?) ?? const [];
    return list.map((raw) {
      final m = raw as Map<String, dynamic>;
      final a = (m['attributes'] as Map?) ?? {};
      return TrackSearchResult(
        mediaId: m['id'].toString(),
        title: (a['canonicalTitle'] ?? a['slug'] ?? 'Unknown').toString(),
        coverUrl: (a['posterImage']?['small'] ?? a['posterImage']?['original'] ?? '')
            .toString(),
        totalChapters: (a['chapterCount'] as num?)?.toInt() ?? 0,
        summary: (a['synopsis'] ?? '').toString(),
        url: 'https://kitsu.io/manga/${a['slug'] ?? m['id']}',
      );
    }).toList();
  }

  /// The user's library-entry id for [mediaId] (needed to PATCH), or null.
  Future<String?> _entryId(String mediaId) async {
    final res = await http.get(
      Uri.parse(
          '$_api/library-entries?filter[userId]=$_userId&filter[mangaId]=$mediaId&filter[kind]=manga'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) return null;
    final list = (jsonDecode(res.body)['data'] as List?) ?? const [];
    return list.isEmpty ? null : (list.first as Map)['id']?.toString();
  }

  @override
  Future<TrackRecord?> refresh(String mediaId) async {
    if (!isAuthenticated) return null;
    final res = await http.get(
      Uri.parse(
          '$_api/library-entries?filter[userId]=$_userId&filter[mangaId]=$mediaId&filter[kind]=manga'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) return null;
    final list = (jsonDecode(res.body)['data'] as List?) ?? const [];
    if (list.isEmpty) return null;
    final a = ((list.first as Map)['attributes'] as Map?) ?? {};
    return TrackRecord(
      trackerId: id,
      mediaId: mediaId,
      status: _fromKitsuStatus(a['status']?.toString()),
      lastChapterRead: (a['progress'] as num?)?.toInt() ?? 0,
      score: ((a['ratingTwenty'] as num?)?.toDouble() ?? 0) / 2,
    );
  }

  @override
  Future<bool> push(TrackRecord r) async {
    if (!isAuthenticated) return false;
    final attributes = <String, dynamic>{
      'status': _toKitsuStatus(r.status),
      'progress': r.lastChapterRead,
      if (r.score > 0) 'ratingTwenty': (r.score * 2).round().clamp(2, 20),
    };
    final existing = await _entryId(r.mediaId);
    if (existing != null) {
      final res = await http.patch(
        Uri.parse('$_api/library-entries/$existing'),
        headers: _authHeaders,
        body: jsonEncode({
          'data': {
            'id': existing,
            'type': 'libraryEntries',
            'attributes': attributes,
          }
        }),
      );
      return res.statusCode == 200;
    }
    final res = await http.post(
      Uri.parse('$_api/library-entries'),
      headers: _authHeaders,
      body: jsonEncode({
        'data': {
          'type': 'libraryEntries',
          'attributes': attributes,
          'relationships': {
            'user': {
              'data': {'type': 'users', 'id': _userId}
            },
            'media': {
              'data': {'type': 'manga', 'id': r.mediaId}
            },
          },
        }
      }),
    );
    return res.statusCode == 200 || res.statusCode == 201;
  }

  String _toKitsuStatus(TrackStatus s) {
    switch (s) {
      case TrackStatus.reading:
      case TrackStatus.rereading:
        return 'current';
      case TrackStatus.planToRead:
        return 'planned';
      case TrackStatus.completed:
        return 'completed';
      case TrackStatus.onHold:
        return 'on_hold';
      case TrackStatus.dropped:
        return 'dropped';
    }
  }

  TrackStatus _fromKitsuStatus(String? s) {
    switch (s) {
      case 'planned':
        return TrackStatus.planToRead;
      case 'completed':
        return TrackStatus.completed;
      case 'on_hold':
        return TrackStatus.onHold;
      case 'dropped':
        return TrackStatus.dropped;
      default:
        return TrackStatus.reading;
    }
  }
}
