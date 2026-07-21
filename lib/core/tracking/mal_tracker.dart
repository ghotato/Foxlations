import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

import 'tracker.dart';
import 'tracker_models.dart';

/// MyAnimeList (myanimelist.net) — OAuth2 with **PKCE** (plain), so no client
/// secret is embedded. The WebView captures an authorization `code` from the
/// `foxlations://auth` redirect, which we exchange for tokens. Search and all
/// list operations require the bearer token.
class MalTracker extends Tracker {
  static const _authBase = 'https://myanimelist.net/v1/oauth2';
  static const _api = 'https://api.myanimelist.net/v2';
  static const redirectUri = 'foxlations://auth';

  String? _accessToken;
  String? _refreshToken;
  String? _username;
  int _expiresAtMs = 0;
  String? _clientId; // needed for token exchange/refresh
  String? _codeVerifier; // held between authorizeUrl() and the code exchange

  @override
  String get id => 'myanimelist';
  @override
  String get name => 'MyAnimeList';
  @override
  int get colorValue => 0xFF2E51A2;
  @override
  TrackerAuthType get authType => TrackerAuthType.oauth;

  @override
  bool get oauthUsesCode => true;
  @override
  String get oauthRedirect => redirectUri;

  @override
  bool get isAuthenticated => _accessToken != null;
  @override
  String? get username => _username;

  @override
  Map<String, dynamic> exportSession() => {
        'accessToken': _accessToken,
        'refreshToken': _refreshToken,
        'username': _username,
        'expiresAtMs': _expiresAtMs,
        'clientId': _clientId,
      };

  @override
  void restoreSession(Map<String, dynamic> data) {
    _accessToken = data['accessToken'] as String?;
    _refreshToken = data['refreshToken'] as String?;
    _username = data['username'] as String?;
    _expiresAtMs = (data['expiresAtMs'] as num?)?.toInt() ?? 0;
    _clientId = data['clientId'] as String?;
  }

  @override
  void logout() {
    _accessToken = _refreshToken = _username = _clientId = _codeVerifier = null;
    _expiresAtMs = 0;
  }

  // ── PKCE + auth ──

  String _randomVerifier() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final r = Random.secure();
    return List.generate(96, (_) => chars[r.nextInt(chars.length)]).join();
  }

  @override
  String authorizeUrl(String clientId) {
    _clientId = clientId;
    _codeVerifier = _randomVerifier();
    // MAL only supports the "plain" challenge method (challenge == verifier).
    return '$_authBase/authorize'
        '?response_type=code'
        '&client_id=$clientId'
        '&code_challenge=$_codeVerifier'
        '&code_challenge_method=plain'
        '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
        '&state=foxlations';
  }

  @override
  Future<bool> authenticateWithCode(String code) async {
    if (_clientId == null || _codeVerifier == null) return false;
    final res = await http.post(
      Uri.parse('$_authBase/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': _clientId!,
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': _codeVerifier!,
        'redirect_uri': redirectUri,
      },
    );
    if (res.statusCode != 200) return false;
    _storeTokens(jsonDecode(res.body) as Map<String, dynamic>);
    return _fetchSelf();
  }

  void _storeTokens(Map<String, dynamic> data) {
    _accessToken = data['access_token'] as String?;
    _refreshToken = data['refresh_token'] as String? ?? _refreshToken;
    final expires = (data['expires_in'] as num?)?.toInt() ?? 2592000;
    _expiresAtMs = DateTime.now().millisecondsSinceEpoch + expires * 1000;
  }

  Future<bool> _refresh() async {
    if (_refreshToken == null || _clientId == null) return false;
    final res = await http.post(
      Uri.parse('$_authBase/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'client_id': _clientId!,
        'grant_type': 'refresh_token',
        'refresh_token': _refreshToken!,
      },
    );
    if (res.statusCode != 200) return false;
    _storeTokens(jsonDecode(res.body) as Map<String, dynamic>);
    return true;
  }

  Future<Map<String, String>> _headers() async {
    if (_accessToken != null &&
        _expiresAtMs != 0 &&
        DateTime.now().millisecondsSinceEpoch > _expiresAtMs - 60000) {
      await _refresh();
    }
    return {'Authorization': 'Bearer $_accessToken'};
  }

  Future<bool> _fetchSelf() async {
    final res = await http.get(Uri.parse('$_api/users/@me?fields=name'),
        headers: await _headers());
    if (res.statusCode != 200) return false;
    _username = (jsonDecode(res.body)['name'])?.toString();
    return _accessToken != null;
  }

  // ── operations ──

  @override
  Future<List<TrackSearchResult>> search(String query) async {
    if (!isAuthenticated) return [];
    final res = await http.get(
      Uri.parse(
          '$_api/manga?q=${Uri.encodeQueryComponent(query)}&limit=15&fields=num_chapters,main_picture,synopsis'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) return [];
    final list = (jsonDecode(res.body)['data'] as List?) ?? const [];
    return list.map((raw) {
      final node = ((raw as Map)['node'] as Map?) ?? {};
      return TrackSearchResult(
        mediaId: node['id'].toString(),
        title: (node['title'] ?? 'Unknown').toString(),
        coverUrl: (node['main_picture']?['medium'] ??
                node['main_picture']?['large'] ??
                '')
            .toString(),
        totalChapters: (node['num_chapters'] as num?)?.toInt() ?? 0,
        summary: (node['synopsis'] ?? '').toString(),
        url: 'https://myanimelist.net/manga/${node['id']}',
      );
    }).toList();
  }

  @override
  Future<TrackRecord?> refresh(String mediaId) async {
    if (!isAuthenticated) return null;
    final res = await http.get(
      Uri.parse('$_api/manga/$mediaId?fields=my_list_status,num_chapters'),
      headers: await _headers(),
    );
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final st = body['my_list_status'] as Map<String, dynamic>?;
    if (st == null) return null;
    return TrackRecord(
      trackerId: id,
      mediaId: mediaId,
      status: _fromMalStatus(st['status']?.toString()),
      lastChapterRead: (st['num_chapters_read'] as num?)?.toInt() ?? 0,
      totalChapters: (body['num_chapters'] as num?)?.toInt() ?? 0,
      score: ((st['score'] as num?)?.toDouble() ?? 0),
    );
  }

  @override
  Future<bool> push(TrackRecord r) async {
    if (!isAuthenticated) return false;
    final res = await http.patch(
      Uri.parse('$_api/manga/${r.mediaId}/my_list_status'),
      headers: {
        ...await _headers(),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'status': _toMalStatus(r.status),
        'num_chapters_read': '${r.lastChapterRead}',
        if (r.score > 0) 'score': '${r.score.round().clamp(1, 10)}',
      },
    );
    return res.statusCode == 200;
  }

  String _toMalStatus(TrackStatus s) {
    switch (s) {
      case TrackStatus.reading:
      case TrackStatus.rereading:
        return 'reading';
      case TrackStatus.planToRead:
        return 'plan_to_read';
      case TrackStatus.completed:
        return 'completed';
      case TrackStatus.onHold:
        return 'on_hold';
      case TrackStatus.dropped:
        return 'dropped';
    }
  }

  TrackStatus _fromMalStatus(String? s) {
    switch (s) {
      case 'plan_to_read':
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
