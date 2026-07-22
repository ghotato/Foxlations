import 'package:shared_preferences/shared_preferences.dart';

/// Per-source options that Foxlations itself provides.
///
/// Distinct from the preferences an extension declares via
/// `getSourcePreferences()`: those are defined by the source's own code and
/// most sources declare none, which left the Settings page empty. These apply
/// to every source regardless of what its author implemented.
class SourceSettings {
  /// Replaces the source's baseUrl — the fix when a site changes domain and
  /// the extension hasn't been updated yet.
  final String baseUrlOverride;

  /// Sort this source to the top of the sources list.
  final bool pinned;

  /// Skip this source when searching every source at once.
  final bool excludeFromGlobalSearch;

  /// Skip this source during library update checks.
  final bool excludeFromUpdates;

  const SourceSettings({
    this.baseUrlOverride = '',
    this.pinned = false,
    this.excludeFromGlobalSearch = false,
    this.excludeFromUpdates = false,
  });

  bool get isDefault =>
      baseUrlOverride.isEmpty &&
      !pinned &&
      !excludeFromGlobalSearch &&
      !excludeFromUpdates;

  SourceSettings copyWith({
    String? baseUrlOverride,
    bool? pinned,
    bool? excludeFromGlobalSearch,
    bool? excludeFromUpdates,
  }) =>
      SourceSettings(
        baseUrlOverride: baseUrlOverride ?? this.baseUrlOverride,
        pinned: pinned ?? this.pinned,
        excludeFromGlobalSearch:
            excludeFromGlobalSearch ?? this.excludeFromGlobalSearch,
        excludeFromUpdates: excludeFromUpdates ?? this.excludeFromUpdates,
      );

  // Namespaced separately from `source_pref_*`, which belongs to the extension
  // bridge — mixing them would let an app option collide with an extension key.
  /// Owned by the Sources tab; reused here so pinning stays a single state.
  static const _pinnedKey = 'pinned_source_ids';

  static String _k(String sourceId, String name) =>
      'source_opt_${sourceId}_$name';

  static Future<SourceSettings> load(String sourceId) async {
    final p = await SharedPreferences.getInstance();
    return SourceSettings(
      baseUrlOverride: p.getString(_k(sourceId, 'base_url')) ?? '',
      // Shares the Sources tab's existing key so there is ONE pin state, not two.
      pinned: (p.getStringList(_pinnedKey) ?? const []).contains(sourceId),
      excludeFromGlobalSearch:
          p.getBool(_k(sourceId, 'no_global_search')) ?? false,
      excludeFromUpdates: p.getBool(_k(sourceId, 'no_updates')) ?? false,
    );
  }

  Future<void> save(String sourceId) async {
    final p = await SharedPreferences.getInstance();
    if (baseUrlOverride.isEmpty) {
      await p.remove(_k(sourceId, 'base_url'));
    } else {
      await p.setString(_k(sourceId, 'base_url'), baseUrlOverride);
    }
    final pins = (p.getStringList(_pinnedKey) ?? <String>[]).toSet();
    pinned ? pins.add(sourceId) : pins.remove(sourceId);
    await p.setStringList(_pinnedKey, pins.toList());
    await p.setBool(_k(sourceId, 'no_global_search'), excludeFromGlobalSearch);
    await p.setBool(_k(sourceId, 'no_updates'), excludeFromUpdates);
  }

  /// Synchronous lookups for hot paths (list sorting, search fan-out) that
  /// can't await. Populated by [preload] at startup.
  static final Map<String, SourceSettings> _cache = {};

  static SourceSettings cached(String sourceId) =>
      _cache[sourceId] ?? const SourceSettings();

  static Future<void> preload(Iterable<String> sourceIds) async {
    for (final id in sourceIds) {
      _cache[id] = await load(id);
    }
  }

  static void updateCache(String sourceId, SourceSettings s) =>
      _cache[sourceId] = s;
}
