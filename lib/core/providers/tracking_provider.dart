import 'package:flutter/foundation.dart';

import '../tracking/tracker.dart';
import '../tracking/tracker_models.dart';
import '../tracking/tracking_service.dart';

/// App-facing tracking state: which services are connected, per-manga bindings,
/// and the operations the UI calls (connect, search, bind, edit, auto-sync).
class TrackingProvider extends ChangeNotifier {
  final TrackingService _service = TrackingService();
  bool _initialized = false;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    await _service.init();
    _initialized = true;
    notifyListeners();
  }

  List<Tracker> get trackers => _service.all;
  Tracker? tracker(String id) => _service.tracker(id);
  List<Tracker> get connected =>
      _service.all.where((t) => t.isAuthenticated).toList();
  bool isConnected(String id) => _service.tracker(id)?.isAuthenticated ?? false;

  String clientId(String trackerId) => _service.clientId(trackerId);
  Future<void> setClientId(String trackerId, String value) async {
    await _service.setClientId(trackerId, value);
    notifyListeners();
  }

  /// OAuth trackers: the URL to open for the user to authorize.
  String? authorizeUrl(String trackerId) {
    final t = _service.tracker(trackerId);
    if (t == null || t.authType != TrackerAuthType.oauth) return null;
    final cid = _service.clientId(trackerId);
    if (cid.isEmpty) return null;
    return t.authorizeUrl(cid);
  }

  Future<bool> connectWithToken(String trackerId, String token) async {
    final t = _service.tracker(trackerId);
    if (t == null) return false;
    final ok = await t.authenticateWithToken(token);
    if (ok) await _service.saveSession(t);
    notifyListeners();
    return ok;
  }

  /// Finish an OAuth login with the value the WebView captured — an access
  /// token (implicit/AniList) or an authorization code (PKCE/MAL).
  Future<bool> completeOAuth(String trackerId, String captured) async {
    final t = _service.tracker(trackerId);
    if (t == null) return false;
    final ok = t.oauthUsesCode
        ? await t.authenticateWithCode(captured)
        : await t.authenticateWithToken(captured);
    if (ok) await _service.saveSession(t);
    notifyListeners();
    return ok;
  }

  Future<bool> connectWithCredentials(
      String trackerId, String username, String password) async {
    final t = _service.tracker(trackerId);
    if (t == null) return false;
    final ok = await t.authenticateWithCredentials(username, password);
    if (ok) await _service.saveSession(t);
    notifyListeners();
    return ok;
  }

  Future<void> disconnect(String trackerId) async {
    final t = _service.tracker(trackerId);
    if (t == null) return;
    await _service.clearSession(t);
    notifyListeners();
  }

  Future<List<TrackSearchResult>> search(String trackerId, String query) async {
    final t = _service.tracker(trackerId);
    if (t == null || query.trim().isEmpty) return [];
    return t.search(query.trim());
  }

  // ── bindings ──

  List<TrackRecord> bindingsFor(String mangaKey) =>
      _service.bindingsFor(mangaKey);

  /// Bind a manga to a search result on [trackerId], pull the current remote
  /// state if any, seed local progress with [localProgress], push, and save.
  Future<TrackRecord?> bind(
    String mangaKey,
    String trackerId,
    TrackSearchResult result, {
    int localProgress = 0,
  }) async {
    final t = _service.tracker(trackerId);
    if (t == null) return null;
    var record = await t.refresh(result.mediaId) ??
        TrackRecord(
          trackerId: trackerId,
          mediaId: result.mediaId,
          status: TrackStatus.reading,
        );
    record.title = result.title;
    record.coverUrl = result.coverUrl;
    record.url = result.url;
    if (record.totalChapters == 0) record.totalChapters = result.totalChapters;
    if (localProgress > record.lastChapterRead) {
      record.lastChapterRead = localProgress;
    }
    await t.push(record);
    await _service.saveBinding(mangaKey, record);
    notifyListeners();
    return record;
  }

  /// Edit a binding's status/progress/score and push it.
  Future<void> updateRecord(String mangaKey, TrackRecord record) async {
    final t = _service.tracker(record.trackerId);
    if (t == null) return;
    await t.push(record);
    await _service.saveBinding(mangaKey, record);
    notifyListeners();
  }

  Future<void> removeBinding(String mangaKey, String trackerId) async {
    await _service.removeBinding(mangaKey, trackerId);
    notifyListeners();
  }

  /// Auto-sync: the user just read chapter [chapterNumber] of [mangaKey]. Bumps
  /// every connected binding whose progress is behind and pushes it. Silent —
  /// never throws into the read path.
  Future<void> syncChapterRead(String mangaKey, int chapterNumber) async {
    if (chapterNumber <= 0) return;
    final bindings = _service.bindingsFor(mangaKey);
    var changed = false;
    for (final r in bindings) {
      final t = _service.tracker(r.trackerId);
      if (t == null || !t.isAuthenticated) continue;
      if (chapterNumber <= r.lastChapterRead) continue;
      r.lastChapterRead = chapterNumber;
      if (r.status == TrackStatus.planToRead) r.status = TrackStatus.reading;
      if (r.totalChapters > 0 && chapterNumber >= r.totalChapters) {
        r.status = TrackStatus.completed;
      }
      try {
        await t.push(r);
        await _service.saveBinding(mangaKey, r);
        changed = true;
      } catch (_) {}
    }
    if (changed) notifyListeners();
  }
}
