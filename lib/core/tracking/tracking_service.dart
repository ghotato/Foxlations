import 'package:hive/hive.dart';

import 'anilist_tracker.dart';
import 'kitsu_tracker.dart';
import 'mal_tracker.dart';
import 'tracker.dart';
import 'tracker_models.dart';

/// Owns the tracker instances, persists their sessions + the user's per-manga
/// bindings, and holds OAuth client IDs. Backed by a single Hive box.
class TrackingService {
  static const _boxName = 'tracking';

  // Built-in OAuth client IDs (overridable in settings). Filled in when the
  // user registers their app(s). Empty = the user must paste one in settings.
  static const Map<String, String> _defaultClientIds = {
    'anilist': '46429',
    'myanimelist': '224eeb47107d2e0b1a253b92230e092b',
  };

  late Box _box;
  final Map<String, Tracker> trackers = {};

  List<Tracker> get all => trackers.values.toList();

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    for (final t in [AniListTracker(), MalTracker(), KitsuTracker()]) {
      trackers[t.id] = t;
      final s = _box.get('session_${t.id}');
      if (s is Map) t.restoreSession(Map<String, dynamic>.from(s));
    }
  }

  Tracker? tracker(String id) => trackers[id];

  // ── OAuth client IDs ──

  String clientId(String trackerId) =>
      (_box.get('clientId_$trackerId') as String?)?.trim().isNotEmpty == true
          ? (_box.get('clientId_$trackerId') as String).trim()
          : (_defaultClientIds[trackerId] ?? '');

  Future<void> setClientId(String trackerId, String value) =>
      _box.put('clientId_$trackerId', value.trim());

  // ── sessions ──

  Future<void> saveSession(Tracker t) =>
      _box.put('session_${t.id}', t.exportSession());

  Future<void> clearSession(Tracker t) async {
    t.logout();
    await _box.delete('session_${t.id}');
  }

  // ── per-manga bindings ──

  String _bindKey(String mangaKey) => 'bind_$mangaKey';

  List<TrackRecord> bindingsFor(String mangaKey) {
    final raw = _box.get(_bindKey(mangaKey));
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => TrackRecord.fromJson(e))
          .toList();
    }
    return const [];
  }

  Future<void> saveBinding(String mangaKey, TrackRecord record) async {
    final list = bindingsFor(mangaKey).toList()
      ..removeWhere((e) => e.trackerId == record.trackerId)
      ..add(record);
    await _box.put(
        _bindKey(mangaKey), list.map((e) => e.toJson()).toList());
  }

  Future<void> removeBinding(String mangaKey, String trackerId) async {
    final list = bindingsFor(mangaKey).toList()
      ..removeWhere((e) => e.trackerId == trackerId);
    if (list.isEmpty) {
      await _box.delete(_bindKey(mangaKey));
    } else {
      await _box.put(
          _bindKey(mangaKey), list.map((e) => e.toJson()).toList());
    }
  }
}
