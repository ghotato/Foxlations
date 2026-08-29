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

  /// Ask the site for its desktop layout instead of its phone one.
  ///
  /// Some sites serve phones a stripped page that builds its content in the
  /// browser, so a scraper sees an empty shell — webtoons.com is the known
  /// case: its episode list is absent from the phone page but present in the
  /// desktop one. Off by default, because the phone layout is usually lighter
  /// and every other site works fine with it.
  final bool requestDesktopSite;

  const SourceSettings({
    this.baseUrlOverride = '',
    this.pinned = false,
    this.excludeFromGlobalSearch = false,
    this.excludeFromUpdates = false,
    this.requestDesktopSite = false,
  });

  bool get isDefault =>
      baseUrlOverride.isEmpty &&
      !pinned &&
      !excludeFromGlobalSearch &&
      !excludeFromUpdates &&
      !requestDesktopSite;

  SourceSettings copyWith({
    String? baseUrlOverride,
    bool? pinned,
    bool? excludeFromGlobalSearch,
    bool? excludeFromUpdates,
    bool? requestDesktopSite,
  }) =>
      SourceSettings(
        baseUrlOverride: baseUrlOverride ?? this.baseUrlOverride,
        pinned: pinned ?? this.pinned,
        excludeFromGlobalSearch:
            excludeFromGlobalSearch ?? this.excludeFromGlobalSearch,
        excludeFromUpdates: excludeFromUpdates ?? this.excludeFromUpdates,
        requestDesktopSite: requestDesktopSite ?? this.requestDesktopSite,
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
      requestDesktopSite: p.getBool(_k(sourceId, 'desktop_ua')) ?? false,
    );
  }

  /// Hosts whose requests should carry a desktop User-Agent.
  ///
  /// Kept as a flat host set rather than looked up per source because the HTTP
  /// layer has no idea which source is driving a request — both the JS and Dart
  /// bridges only ever see a URL. Writing the host here at save time lets that
  /// layer answer the question with what it already has.
  static const _desktopHostsKey = 'desktop_ua_hosts';

  static String? _hostOf(String url) {
    try {
      final h = Uri.parse(url).host.toLowerCase();
      if (h.isEmpty) return null;
      return h.startsWith('www.') ? h.substring(4) : h;
    } catch (_) {
      return null;
    }
  }

  /// Add or remove [baseUrl]'s host from the desktop-UA set.
  static Future<void> _syncDesktopHost(String baseUrl, bool wants) async {
    final host = _hostOf(baseUrl);
    if (host == null) return;
    final p = await SharedPreferences.getInstance();
    final hosts = (p.getStringList(_desktopHostsKey) ?? <String>[]).toSet();
    if (wants) {
      hosts.add(host);
    } else {
      hosts.remove(host);
    }
    await p.setStringList(_desktopHostsKey, hosts.toList());
    _desktopHosts
      ..clear()
      ..addAll(hosts);
  }

  static final Set<String> _desktopHosts = {};

  /// True when [url]'s host has desktop mode turned on. Synchronous because it
  /// sits in the request path.
  static bool wantsDesktopUA(String url) {
    if (_desktopHosts.isEmpty) return false;
    final host = _hostOf(url);
    return host != null && _desktopHosts.contains(host);
  }

  static Future<void> preloadDesktopHosts() async {
    final p = await SharedPreferences.getInstance();
    _desktopHosts
      ..clear()
      ..addAll(p.getStringList(_desktopHostsKey) ?? const []);
  }

  /// [baseUrl] is the source's effective base URL, needed to register its host
  /// in the desktop-UA set. Pass the override when one is set.
  Future<void> save(String sourceId, {String baseUrl = ''}) async {
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
    await p.setBool(_k(sourceId, 'desktop_ua'), requestDesktopSite);
    final effective =
        baseUrlOverride.isNotEmpty ? baseUrlOverride : baseUrl;
    if (effective.isNotEmpty) {
      await _syncDesktopHost(effective, requestDesktopSite);
    }
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
