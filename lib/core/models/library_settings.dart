import 'package:shared_preferences/shared_preferences.dart';

/// How the library list is ordered.
///
/// "Latest chapter" is still absent: it needs a parsed per-chapter upload date,
/// and `LibraryChapter.dateUpload` is an unparsed source-supplied String whose
/// format varies per site. Sorting by it would be wrong more often than right.
enum LibrarySort {
  alphabetical('Alphabetical'),
  lastRead('Last Read'),
  unread('Unread'),
  totalChapters('Total chapters'),
  chapterFetchDate('Chapter fetch date'),
  dateAdded('Date Added');

  const LibrarySort(this.label);
  final String label;
}

/// How each entry is drawn.
enum LibraryDisplayMode {
  grid('Grid'),
  list('List'),
  descriptiveList('Descriptive List');

  const LibraryDisplayMode(this.label);
  final String label;
}

/// User-controlled library filter / sort / display state.
///
/// Persisted globally (not per-category) — a single set of preferences applies
/// to every tab, which is the simpler contract and matches how the rest of the
/// app stores settings. Changing this to per-category later only requires
/// suffixing the pref keys with the category name.
class LibrarySettings {
  // Filters
  final bool filterUnread;
  final bool filterCompleted;
  final bool filterDownloaded;
  final Set<String> filterSourceIds;

  // Sort
  final LibrarySort sort;
  final bool sortAscending;

  // Display
  final LibraryDisplayMode displayMode;
  final int itemsPerRow;
  final bool badgeUnread;
  final bool badgeDownloaded;
  final bool showTabCounts;

  const LibrarySettings({
    this.filterUnread = false,
    this.filterCompleted = false,
    this.filterDownloaded = false,
    this.filterSourceIds = const {},
    this.sort = LibrarySort.alphabetical,
    this.sortAscending = true,
    this.displayMode = LibraryDisplayMode.grid,
    this.itemsPerRow = 3,
    this.badgeUnread = true,
    this.badgeDownloaded = true,
    this.showTabCounts = false,
  });

  bool get hasActiveFilter =>
      filterUnread ||
      filterCompleted ||
      filterDownloaded ||
      filterSourceIds.isNotEmpty;

  int get activeFilterCount =>
      (filterUnread ? 1 : 0) +
      (filterCompleted ? 1 : 0) +
      (filterDownloaded ? 1 : 0) +
      (filterSourceIds.isEmpty ? 0 : 1);

  LibrarySettings copyWith({
    bool? filterUnread,
    bool? filterCompleted,
    bool? filterDownloaded,
    Set<String>? filterSourceIds,
    LibrarySort? sort,
    bool? sortAscending,
    LibraryDisplayMode? displayMode,
    int? itemsPerRow,
    bool? badgeUnread,
    bool? badgeDownloaded,
    bool? showTabCounts,
  }) {
    return LibrarySettings(
      filterUnread: filterUnread ?? this.filterUnread,
      filterCompleted: filterCompleted ?? this.filterCompleted,
      filterDownloaded: filterDownloaded ?? this.filterDownloaded,
      filterSourceIds: filterSourceIds ?? this.filterSourceIds,
      sort: sort ?? this.sort,
      sortAscending: sortAscending ?? this.sortAscending,
      displayMode: displayMode ?? this.displayMode,
      itemsPerRow: itemsPerRow ?? this.itemsPerRow,
      badgeUnread: badgeUnread ?? this.badgeUnread,
      badgeDownloaded: badgeDownloaded ?? this.badgeDownloaded,
      showTabCounts: showTabCounts ?? this.showTabCounts,
    );
  }

  // ── persistence ───────────────────────────────────────────────────────────
  static const _kFilterUnread = 'lib_filter_unread';
  static const _kFilterCompleted = 'lib_filter_completed';
  static const _kFilterDownloaded = 'lib_filter_downloaded';
  static const _kFilterSources = 'lib_filter_sources';
  static const _kSort = 'lib_sort';
  static const _kSortAsc = 'lib_sort_asc';
  static const _kDisplayMode = 'lib_display_mode';
  static const _kItemsPerRow = 'lib_items_per_row';
  static const _kBadgeUnread = 'lib_badge_unread';
  static const _kBadgeDownloaded = 'lib_badge_downloaded';
  static const _kTabCounts = 'lib_tab_counts';

  static Future<LibrarySettings> load() async {
    final p = await SharedPreferences.getInstance();
    T byName<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);

    return LibrarySettings(
      filterUnread: p.getBool(_kFilterUnread) ?? false,
      filterCompleted: p.getBool(_kFilterCompleted) ?? false,
      filterDownloaded: p.getBool(_kFilterDownloaded) ?? false,
      filterSourceIds: (p.getStringList(_kFilterSources) ?? const []).toSet(),
      sort: byName(LibrarySort.values, p.getString(_kSort), LibrarySort.alphabetical),
      sortAscending: p.getBool(_kSortAsc) ?? true,
      displayMode: byName(LibraryDisplayMode.values, p.getString(_kDisplayMode),
          LibraryDisplayMode.grid),
      itemsPerRow: (p.getInt(_kItemsPerRow) ?? 3).clamp(2, 6),
      badgeUnread: p.getBool(_kBadgeUnread) ?? true,
      badgeDownloaded: p.getBool(_kBadgeDownloaded) ?? true,
      showTabCounts: p.getBool(_kTabCounts) ?? false,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kFilterUnread, filterUnread);
    await p.setBool(_kFilterCompleted, filterCompleted);
    await p.setBool(_kFilterDownloaded, filterDownloaded);
    await p.setStringList(_kFilterSources, filterSourceIds.toList());
    await p.setString(_kSort, sort.name);
    await p.setBool(_kSortAsc, sortAscending);
    await p.setString(_kDisplayMode, displayMode.name);
    await p.setInt(_kItemsPerRow, itemsPerRow);
    await p.setBool(_kBadgeUnread, badgeUnread);
    await p.setBool(_kBadgeDownloaded, badgeDownloaded);
    await p.setBool(_kTabCounts, showTabCounts);
  }

  /// Clears every stored preference so the next [load] returns the defaults.
  static Future<void> resetToDefaults() async {
    final p = await SharedPreferences.getInstance();
    for (final k in const [
      _kFilterUnread, _kFilterCompleted, _kFilterDownloaded, _kFilterSources,
      _kSort, _kSortAsc, _kDisplayMode, _kItemsPerRow, _kBadgeUnread,
      _kBadgeDownloaded, _kTabCounts,
    ]) {
      await p.remove(k);
    }
  }
}
