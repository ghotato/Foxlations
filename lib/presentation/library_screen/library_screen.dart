import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/manga_model.dart';
import '../widgets/manga_image.dart';
import '../../core/providers/library_provider.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/providers/source_provider.dart';
import '../../core/services/library_update_service.dart';
import '../../core/models/library_settings.dart';
import '../../core/utils/library_query.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../manga_detail_screen/migrate_screen.dart';
import '../widgets/update_prompt.dart';
import './widgets/library_options_sheet.dart';
import './widgets/library_stats_widget.dart';

/// SharedPreferences key for the persisted set of `${sourceId}::${mangaUrl}`
/// strings the user has bookmarked at the manga level. Read by reader_screen
/// to honor the "Include Bookmarked Chapters" download setting.
const String kBookmarkedMangaIdsKey = 'bookmarked_manga_ids';

// Safely extract origin from a URL, returning null for relative paths.
String? _originOf(String? url) {
  if (url == null) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return null;
  try { return uri.origin; } catch (_) { return null; }
}

// ── Reading Status ────────────────────────────────────────────
enum MangaReadingStatus { all, reading, completed, onHold, dropped, planToRead }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with TickerProviderStateMixin {
  bool _isSearchActive = false;
  String _searchQuery = '';
  /// Derived from the Display tab so the sheet and the toolbar toggle can't
  /// disagree — previously this was independent state, which meant choosing a
  /// display mode in the sheet had no effect on what was actually rendered.
  bool get _isGridView =>
      _librarySettings.displayMode == LibraryDisplayMode.grid;
  bool _showStats = false;
  bool _showBookmarksOnly = false;
  final Set<String> _bookmarkedIds = {};
  String? _selectedCategory; // null = "All"
  bool _isRefreshing = false;
  LibrarySettings _librarySettings = const LibrarySettings();

  // Multi-select mode
  bool _isSelectMode = false;
  final Set<String> _selectedMangaIds = {};

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool get _isVaultMode => context.watch<VaultProvider>().vaultActive;

  // Helpers to get data from the active provider (vault or normal)
  List<LibraryManga> _activeManga(BuildContext context) {
    final vault = context.read<VaultProvider>();
    return vault.vaultActive ? vault.manga : context.read<LibraryProvider>().manga;
  }

  List<String> _activeCategoryNames(BuildContext context) {
    final vault = context.read<VaultProvider>();
    final cats = vault.vaultActive ? vault.categories : context.read<LibraryProvider>().categories;
    return cats.map((c) => c.name).toList();
  }

  Future<void> _checkForUpdates() => _refreshLibrary();

  /// [scoped] limits the check to the entries currently on screen (the selected
  /// category), which is what "Category Update" means.
  Future<void> _refreshLibrary({bool scoped = false}) async {
    if (_isRefreshing) return;
    final subset = scoped
        ? _activeManga(context)
            .where((m) =>
                _selectedCategory == null ||
                m.categories.contains(_selectedCategory))
            .toList()
        : null;
    setState(() => _isRefreshing = true);
    final libraryProvider = context.read<LibraryProvider>();
    final sourceProvider = context.read<SourceProvider>();
    final newUpdates = await LibraryUpdateService.checkForUpdates(
      libraryProvider: libraryProvider,
      sourceProvider: sourceProvider,
      only: subset,
    );
    if (mounted) {
      setState(() => _isRefreshing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newUpdates.isNotEmpty
            ? 'Found ${newUpdates.length} new chapter${newUpdates.length == 1 ? '' : 's'}'
            : 'No new chapters'),
        duration: const Duration(seconds: 2)));
    }
  }

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
    _loadLibrarySettings();

    // Throttled to once every 12 hours inside the service, and it swallows its
    // own failures — a missing network or an unreachable site must never block
    // the library from loading.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdatePrompt.maybeShow(context);
    });
  }

  Future<void> _loadLibrarySettings() async {
    final s = await LibrarySettings.load();
    if (mounted) setState(() => _librarySettings = s);
  }

  void _applyLibrarySettings(LibrarySettings next) {
    setState(() => _librarySettings = next);
    next.save();
  }

  void _openLibraryOptions() {
    LibraryOptionsSheet.show(
      context,
      settings: _librarySettings,
      sources: _librarySources(context),
      onChanged: _applyLibrarySettings,
    );
  }

  /// The "More" menu: update scopes plus the entry-level actions.
  Future<void> _openMoreMenu() async {
    final cs = Theme.of(context).colorScheme;
    final inCategory = _selectedCategory != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final item in [
              if (inCategory)
                (
                  'category',
                  Icons.refresh_rounded,
                  'Category Update',
                  'Check "$_selectedCategory" for new chapters'
                ),
              (
                'global',
                Icons.public_rounded,
                'Global Update',
                'Check every entry in your library'
              ),
              (
                'summary',
                Icons.info_outline_rounded,
                'Updates Summary',
                'What the last check found'
              ),
              ('select', Icons.check_circle_outline_rounded, 'Select', ''),
              ('random', Icons.shuffle_rounded, 'Open random entry', ''),
            ])
              ListTile(
                leading: Icon(item.$2, color: cs.primary, size: 22),
                title: Text(item.$3,
                    style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                subtitle: item.$4.isEmpty
                    ? null
                    : Text(item.$4,
                        style: GoogleFonts.manrope(
                            fontSize: 12, color: cs.outline)),
                onTap: () => Navigator.pop(ctx, item.$1),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;

    switch (choice) {
      case 'category':
      case 'global':
        // Category Update reuses the same checker, scoped to what's on screen;
        // Global ignores the category filter and checks the whole library.
        await _refreshLibrary(
          scoped: choice == 'category',
        );
        break;
      case 'summary':
        await _showUpdatesSummary();
        break;
      case 'select':
        setState(() => _isSelectMode = true);
        break;
      case 'random':
        final list = _applyFilters(_activeManga(context));
        if (list.isEmpty) {
          AppTheme.showSnackBar(context, 'Library is empty');
          break;
        }
        final pick = list[DateTime.now().microsecond % list.length];
        Navigator.pushNamed(context, AppRoutes.mangaDetail, arguments: pick);
        break;
    }
  }

  Future<void> _showUpdatesSummary() async {
    final updates = await LibraryUpdateService.loadUpdates();
    final last = await LibraryUpdateService.getLastUpdate();
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    final when = last == null
        ? 'never'
        : '${last.year}-${last.month.toString().padLeft(2, '0')}-'
            '${last.day.toString().padLeft(2, '0')} '
            '${last.hour.toString().padLeft(2, '0')}:'
            '${last.minute.toString().padLeft(2, '0')}';
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
        title: Text('Updates Summary',
            style: GoogleFonts.manrope(
                fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last checked: $when',
                style: GoogleFonts.manrope(fontSize: 13, color: cs.outline)),
            const SizedBox(height: 8),
            Text(
              updates.isEmpty
                  ? 'No new chapters were found in the last check.'
                  : '${updates.length} '
                      'entr${updates.length == 1 ? 'y has' : 'ies have'} '
                      'new chapters.',
              style: GoogleFonts.manrope(fontSize: 14, color: cs.onSurface),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Sources present in the library, for the Filter tab's Sources list.
  List<({String id, String name})> _librarySources(BuildContext context) {
    final installed = context.read<SourceProvider>().installedSources;
    final ids = _activeManga(context).map((m) => m.sourceId).toSet();
    final named = <String, String>{};
    for (final id in ids) {
      final match = installed.where((s) => s.source.id == id);
      named[id] = match.isNotEmpty ? match.first.source.name : id;
    }
    final entries = named.entries
        .map((e) => (id: e.key, name: e.value))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return entries;
  }

  Future<void> _loadBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(kBookmarkedMangaIdsKey) ?? [];
    if (mounted) {
      setState(() {
        _bookmarkedIds
          ..clear()
          ..addAll(ids);
      });
    }
  }

  Future<void> _saveBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kBookmarkedMangaIdsKey, _bookmarkedIds.toList());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<LibraryManga> _applyFilters(List<LibraryManga> manga) {
    var list = manga;

    // Category filter
    if (_selectedCategory != null) {
      list = list.where((m) => m.categories.contains(_selectedCategory)).toList();
    }

    // Bookmarks filter
    if (_showBookmarksOnly) {
      String key(LibraryManga m) => '${m.sourceId}::${m.url}';
      list = list.where((m) => _bookmarkedIds.contains(key(m))).toList();
    }

    // Search
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((m) => m.title.toLowerCase().contains(q)).toList();
    }

    // User-chosen filters + sort order (Filter/Sort sheet).
    return applyLibraryQuery(list, _librarySettings);
  }

  void _onSearchToggle() {
    setState(() {
      _isSearchActive = !_isSearchActive;
      if (!_isSearchActive) {
        _searchQuery = '';
        _searchController.clear();
      } else {
        Future.delayed(const Duration(milliseconds: 150), () {
          _searchFocus.requestFocus();
        });
      }
    });
  }

  String _mangaKey(LibraryManga m) => '${m.sourceId}::${m.url}';

  void _toggleBookmark(LibraryManga manga) {
    final key = _mangaKey(manga);
    setState(() {
      if (_bookmarkedIds.contains(key)) {
        _bookmarkedIds.remove(key);
      } else {
        _bookmarkedIds.add(key);
      }
    });
    _saveBookmarks();
  }

  // Multi-select helpers
  void _enterSelectMode(LibraryManga manga) {
    setState(() {
      _isSelectMode = true;
      _selectedMangaIds.add(_mangaKey(manga));
    });
  }

  void _exitSelectMode() {
    setState(() {
      _isSelectMode = false;
      _selectedMangaIds.clear();
    });
  }

  void _toggleSelect(LibraryManga manga) {
    final key = _mangaKey(manga);
    setState(() {
      if (_selectedMangaIds.contains(key)) {
        _selectedMangaIds.remove(key);
        if (_selectedMangaIds.isEmpty) _isSelectMode = false;
      } else {
        _selectedMangaIds.add(key);
      }
    });
  }

  void _selectAll(List<LibraryManga> manga) {
    setState(() {
      _selectedMangaIds.addAll(manga.map(_mangaKey));
    });
  }

  void _deselectAll() {
    setState(() => _selectedMangaIds.clear());
  }

  List<LibraryManga> _getSelectedManga() {
    final all = _activeManga(context);
    return all.where((m) => _selectedMangaIds.contains(_mangaKey(m))).toList();
  }

  // Vault-aware provider helpers
  void _doRemove(LibraryManga manga) {
    final vault = context.read<VaultProvider>();
    if (vault.vaultActive) {
      vault.removeFromLibrary(manga.sourceId, manga.url);
    } else {
      context.read<LibraryProvider>().removeFromLibrary(manga.sourceId, manga.url);
    }
  }

  void _doSetCategories(LibraryManga manga, List<String> cats) {
    final vault = context.read<VaultProvider>();
    if (vault.vaultActive) {
      vault.setMangaCategories(manga.sourceId, manga.url, cats);
    } else {
      context.read<LibraryProvider>().setMangaCategories(manga.sourceId, manga.url, cats);
    }
  }

  void _doMarkAllRead(LibraryManga manga) {
    final vault = context.read<VaultProvider>();
    if (vault.vaultActive) {
      vault.markAllRead(manga.sourceId, manga.url);
    } else {
      context.read<LibraryProvider>().markAllRead(manga.sourceId, manga.url);
    }
  }

  void _doMarkAllUnread(LibraryManga manga) {
    final vault = context.read<VaultProvider>();
    if (vault.vaultActive) {
      vault.markAllUnread(manga.sourceId, manga.url);
    } else {
      context.read<LibraryProvider>().markAllUnread(manga.sourceId, manga.url);
    }
  }

  void _showContextMenu(LibraryManga manga) {
    final catNames = _activeCategoryNames(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MangaContextSheet(
        manga: manga,
        categories: catNames,
        onMoveCategory: () {
          Navigator.pop(context);
          _showMoveCategorySheet([manga]);
        },
        onMarkRead: () {
          Navigator.pop(context);
          _doMarkAllRead(manga);
        },
        onMarkUnread: () {
          Navigator.pop(context);
          _doMarkAllUnread(manga);
        },
        onRemove: () {
          Navigator.pop(context);
          _doRemove(manga);
        },
      ),
    );
  }

  void _showMoveCategorySheet(List<LibraryManga> mangaList) {
    final cs = Theme.of(context).colorScheme;
    final catNames = _activeCategoryNames(context);
    if (catNames.isEmpty) return;

    // Start with intersection of all selected manga's categories
    final commonCats = mangaList.first.categories.toSet();
    for (final m in mangaList.skip(1)) {
      commonCats.retainAll(m.categories);
    }
    final selected = Set<String>.from(commonCats);

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text('Move to Category',
                  style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
              const SizedBox(height: 12),
              ...catNames.map((cat) {
                final isIn = selected.contains(cat);
                return InkWell(
                  onTap: () => setSheetState(() {
                    if (isIn) { selected.remove(cat); } else { selected.add(cat); }
                  }),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(children: [
                      Icon(isIn ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                          size: 20, color: isIn ? cs.primary : cs.outline),
                      const SizedBox(width: 14),
                      Text(cat, style: GoogleFonts.manrope(
                          fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    ]),
                  ),
                );
              }),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    for (final m in mangaList) {
                      _doSetCategories(m, selected.toList());
                    }
                    if (_isSelectMode) _exitSelectMode();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary, foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Save', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Batch actions for multi-select
  void _batchMarkRead() {
    for (final m in _getSelectedManga()) { _doMarkAllRead(m); }
    _exitSelectMode();
  }

  void _batchMarkUnread() {
    for (final m in _getSelectedManga()) { _doMarkAllUnread(m); }
    _exitSelectMode();
  }

  void _batchRemove() {
    for (final m in _getSelectedManga()) { _doRemove(m); }
    _exitSelectMode();
  }

  void _batchMoveCategory() {
    _showMoveCategorySheet(_getSelectedManga());
  }

  /// Bulk migrate: send each selected entry to the single-entry migrate screen
  /// in turn.
  ///
  /// Deliberately sequential rather than "pick one target source and move
  /// everything". Titles differ between sources — punctuation, romanisation,
  /// season suffixes — so an automatic match would silently attach the wrong
  /// series. Stepping through lets each candidate be confirmed (and previewed
  /// with "Show entry") before anything is replaced.
  Future<void> _batchMigrate() async {
    final selected = _getSelectedManga();
    if (selected.isEmpty) return;
    _exitSelectMode();

    for (var i = 0; i < selected.length; i++) {
      if (!mounted) return;
      final m = selected[i];
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MigrateScreen(
            sourceId: m.sourceId,
            mangaUrl: m.url,
            mangaTitle: m.title,
            // Shown in the app bar so it's clear where you are in the queue.
            queuePosition: i + 1,
            queueTotal: selected.length,
          ),
        ),
      );
    }
  }

  int get _totalUnread {
    final manga = _activeManga(context);
    return manga.fold(0, (sum, m) => sum + (m.totalChapters - m.readChapters));
  }

  LibraryManga? get _lastReadManga {
    final manga = _activeManga(context);
    if (manga.isEmpty) return null;
    final withRead = manga.where((m) => m.readChapters > 0 && m.lastReadChapterUrl != null).toList();
    if (withRead.isEmpty) return null;
    withRead.sort((a, b) => (b.lastReadAt ?? DateTime(2000)).compareTo(a.lastReadAt ?? DateTime(2000)));
    return withRead.first;
  }

  /// Columns for the grid — whatever the user picked in "Items per row".
  ///
  /// This used to cap the count by screen width (4 on a phone, 5 at 600dp, 6 at
  /// 840dp) while the picker still offered up to 6. On a phone that silently
  /// swallowed the choice: selecting 5 or 6 changed the number on screen but
  /// never the grid. The setting is already bounded to 2..6 when it's stored,
  /// so honour it — a user asking for six small covers has asked for exactly
  /// that, and can step back down if they don't like it.
  int _getColumnCount(BuildContext context) {
    return _librarySettings.itemsPerRow.clamp(2, 6);
  }

  PreferredSizeWidget _buildSelectAppBar(ColorScheme cs) {
    return AppBar(
      backgroundColor: cs.primary,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: Colors.white),
        onPressed: _exitSelectMode,
      ),
      title: Text('${_selectedMangaIds.length} selected',
          style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
      actions: [
        IconButton(
          icon: const Icon(Icons.select_all_rounded, color: Colors.white),
          tooltip: 'Select all',
          onPressed: () {
            final filtered = _applyFilters(_activeManga(context));
            _selectAll(filtered);
          },
        ),
        if (_selectedMangaIds.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.deselect_rounded, color: Colors.white),
            tooltip: 'Deselect all',
            onPressed: _deselectAll,
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildBatchBar(ColorScheme cs) {
    final catNames = _activeCategoryNames(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (catNames.isNotEmpty)
              _BatchButton(icon: Icons.drive_file_move_rounded, label: 'Move', onTap: _batchMoveCategory),
            _BatchButton(icon: Icons.done_all_rounded, label: 'Read', onTap: _batchMarkRead),
            _BatchButton(icon: Icons.remove_done_rounded, label: 'Unread', onTap: _batchMarkUnread),
            _BatchButton(icon: Icons.swap_horiz_rounded, label: 'Migrate', onTap: _batchMigrate),
            _BatchButton(icon: Icons.delete_outline_rounded, label: 'Remove', onTap: _batchRemove),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final columnCount = _getColumnCount(context);
    final isVault = _isVaultMode;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: _isSelectMode
            ? _buildSelectAppBar(cs)
            : _LibraryAppBar(
                isSearchActive: _isSearchActive,
                searchController: _searchController,
                searchFocus: _searchFocus,
                totalUnread: _totalUnread,
                isGridView: _isGridView,
                showStats: _showStats,
                isVaultMode: isVault,
                onSearchToggle: _onSearchToggle,
                onSearchChanged: (q) => setState(() => _searchQuery = q),
                onViewToggle: () => _applyLibrarySettings(
                      _librarySettings.copyWith(
                        displayMode: _isGridView
                            ? LibraryDisplayMode.list
                            : LibraryDisplayMode.grid,
                      ),
                    ),
                onStatsTap: () => setState(() => _showStats = !_showStats),
                onRefresh: _checkForUpdates,
                onOptionsTap: _openLibraryOptions,
                onMoreTap: _openMoreMenu,
                hasActiveFilter: _librarySettings.hasActiveFilter,
                isRefreshing: _isRefreshing,
              ),
        body: SafeArea(
          child: _showStats
              ? const LibraryStatsWidget()
              : Column(
                  children: [
                    // Category tabs with bookmark toggle
                    Consumer2<LibraryProvider, VaultProvider>(
                      builder: (_, library, vault, __) {
                        final cats = vault.vaultActive
                            ? vault.categories.map((c) => c.name).toList()
                            : library.categories.map((c) => c.name).toList();
                        // Auto-select first category if none selected, or if
                        // the current selection isn't valid in the active mode
                        // (e.g. after toggling vault, the previous mode's
                        // category names don't exist in the new list).
                        if (cats.isNotEmpty &&
                            (_selectedCategory == null ||
                                !cats.contains(_selectedCategory))) {
                          _selectedCategory = cats.first;
                        }
                        return _CategoryTabs(
                          categories: cats,
                          selected: _selectedCategory,
                          onSelected: (cat) => setState(() {
                            _selectedCategory = cat;
                            _showBookmarksOnly = false;
                          }),
                          showBookmarksOnly: _showBookmarksOnly,
                          bookmarkCount: _bookmarkedIds.length,
                          onBookmarkToggle: () => setState(
                              () => _showBookmarksOnly = !_showBookmarksOnly),
                        );
                      },
                    ),
                    // Continue reading banner
                    Consumer2<LibraryProvider, VaultProvider>(
                      builder: (_, library, vault, __) {
                        final lastRead = _lastReadManga;
                        if (lastRead == null) return const SizedBox.shrink();
                        return _ContinueReadingBanner(
                          manga: lastRead,
                          onTap: () => Navigator.pushNamed(
                            context,
                            AppRoutes.mangaDetail,
                            arguments: {
                              'mangaUrl': lastRead.url,
                              'sourceId': lastRead.sourceId,
                              'title': lastRead.title,
                              'coverUrl': lastRead.coverUrl,
                            },
                          ),
                        );
                      },
                    ),
                    // Main content
                    Expanded(
                      child: Consumer2<LibraryProvider, VaultProvider>(
                        builder: (_, library, vault, __) {
                          final activeManga = vault.vaultActive ? vault.manga : library.manga;
                          final filtered = _applyFilters(activeManga);

                          // Pull down anywhere to update the category the user
                          // is currently viewing (all entries when on "All").
                          Widget withPullToRefresh(Widget child) =>
                              RefreshIndicator(
                                onRefresh: () => _refreshLibrary(scoped: true),
                                child: child,
                              );

                          if (filtered.isEmpty) {
                            return withPullToRefresh(
                              ListView(
                                // A plain Center can't be pulled; a scrollable
                                // list can.
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height:
                                        MediaQuery.of(context).size.height * 0.6,
                                    child: _EmptyState(
                                      isSearching: _searchQuery.isNotEmpty,
                                      searchQuery: _searchQuery,
                                      isBookmarkFilter: _showBookmarksOnly,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          void onTap(LibraryManga m) {
                            if (_isSelectMode) {
                              _toggleSelect(m);
                            } else {
                              Navigator.pushNamed(context, AppRoutes.mangaDetail,
                                arguments: {
                                  'mangaUrl': m.url,
                                  'sourceId': m.sourceId,
                                  'title': m.title,
                                  'coverUrl': m.coverUrl,
                                });
                            }
                          }
                          void onLong(LibraryManga m) {
                            if (_isSelectMode) {
                              _toggleSelect(m);
                            } else {
                              _enterSelectMode(m);
                            }
                          }

                          return withPullToRefresh(
                            _isGridView
                                ? _LibraryGrid(
                                    mangaList: filtered,
                                    columnCount: columnCount,
                                    selectedIds:
                                        _isSelectMode ? _selectedMangaIds : null,
                                    onTap: onTap,
                                    onLongPress: onLong,
                                  )
                                : _LibraryList(
                                    mangaList: filtered,
                                    selectedIds:
                                        _isSelectMode ? _selectedMangaIds : null,
                                    onTap: onTap,
                                    onLongPress: onLong,
                                  ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
        bottomNavigationBar: _isSelectMode ? _buildBatchBar(cs) : null,
        floatingActionButton: !_showStats && !_isSelectMode
            ? FloatingActionButton.extended(
                heroTag: 'library_fab',
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.browse),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text('Add Manga',
                    style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                elevation: 4,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusFull)),
              )
            : null,
      ),
    );
  }
}

// ── App Bar ──────────────────────────────────────────────────
class _LibraryAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isSearchActive;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final int totalUnread;
  final bool isGridView;
  final bool showStats;
  final bool isVaultMode;
  final VoidCallback onSearchToggle;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onViewToggle;
  final VoidCallback onStatsTap;
  final VoidCallback? onRefresh;
  final bool isRefreshing;
  final VoidCallback onOptionsTap;
  final VoidCallback onMoreTap;
  final bool hasActiveFilter;

  const _LibraryAppBar({
    required this.isSearchActive,
    required this.searchController,
    required this.searchFocus,
    required this.totalUnread,
    required this.isGridView,
    required this.showStats,
    this.isVaultMode = false,
    required this.onSearchToggle,
    required this.onSearchChanged,
    required this.onViewToggle,
    required this.onStatsTap,
    required this.onOptionsTap,
    required this.onMoreTap,
    this.hasActiveFilter = false,
    this.onRefresh,
    this.isRefreshing = false,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppBar(
      backgroundColor: cs.surface,
      elevation: 0,
      scrolledUnderElevation: 2,
      automaticallyImplyLeading: false,
      title: AnimatedSwitcher(
        duration: AppTheme.standard,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.05, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation, curve: AppTheme.primaryCurve)),
            child: child,
          ),
        ),
        child: isSearchActive
            ? _SearchField(
                key: const ValueKey('search'),
                controller: searchController,
                focusNode: searchFocus,
                onChanged: onSearchChanged)
            : _TitleRow(
                key: const ValueKey('title'), totalUnread: totalUnread, isVaultMode: isVaultMode),
      ),
      actions: [
        if (!isSearchActive) ...[
          _AppBarAction(
            icon: Icons.search_rounded,
            onTap: onSearchToggle,
            tooltip: 'Search library',
          ),
          if (!showStats && onRefresh != null)
            isRefreshing
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)))
                : _AppBarAction(
                    icon: Icons.refresh_rounded,
                    onTap: onRefresh!,
                    tooltip: 'Check for updates',
                  ),
          // Filter / Sort / Display. Dot marks that a filter is narrowing the
          // list, so a "missing" entry is never a mystery.
          if (!showStats)
            Stack(
              alignment: Alignment.center,
              children: [
                _AppBarAction(
                  icon: Icons.filter_list_rounded,
                  onTap: onOptionsTap,
                  tooltip: 'Filter, sort & display',
                ),
                if (hasActiveFilter)
                  Positioned(
                    top: 12,
                    right: 10,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          _AppBarAction(
            icon: showStats
                ? Icons.collections_bookmark_outlined
                : Icons.bar_chart_rounded,
            onTap: onStatsTap,
            tooltip: showStats ? 'Library' : 'Stats',
          ),
          if (!showStats)
            _AppBarAction(
              icon: Icons.more_vert_rounded,
              onTap: onMoreTap,
              tooltip: 'More',
            ),
        ] else
          _AppBarAction(
            icon: Icons.close_rounded,
            onTap: onSearchToggle,
            tooltip: 'Close search',
          ),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _TitleRow extends StatelessWidget {
  final int totalUnread;
  final bool isVaultMode;
  const _TitleRow({super.key, required this.totalUnread, this.isVaultMode = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isVaultMode) ...[
          Icon(Icons.shield_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(isVaultMode ? 'Vault' : 'Library',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(
                  fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface)),
        ),
        if (totalUnread > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: cs.primary,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
            child: Text(totalUnread > 99 ? '99+' : '$totalUnread',
                style: GoogleFonts.manrope(
                    fontSize: 11, fontWeight: FontWeight.w800, color: cs.onPrimary)),
          ),
        ],
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;

  const _SearchField({
    super.key, required this.controller,
    required this.focusNode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
      child: TextField(
        controller: controller, focusNode: focusNode, onChanged: onChanged,
        style: GoogleFonts.manrope(fontSize: 14, color: cs.onSurface),
        decoration: InputDecoration(
          hintText: 'Search in library...',
          hintStyle: GoogleFonts.manrope(fontSize: 14, color: cs.outline),
          prefixIcon: Icon(Icons.search_rounded, size: 18, color: cs.outline),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          filled: false),
        textAlignVertical: TextAlignVertical.center,
      ),
    );
  }
}

class _AppBarAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  const _AppBarAction({required this.icon, required this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          splashColor: cs.primary.withAlpha(26),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 22, color: cs.onSurface)),
        ),
      ),
    );
  }
}

// ── Category Tabs ───────────────────────────────────────────
class _CategoryTabs extends StatelessWidget {
  final List<String> categories;
  final String? selected;
  final ValueChanged<String?> onSelected;
  final bool showBookmarksOnly;
  final int bookmarkCount;
  final VoidCallback onBookmarkToggle;

  const _CategoryTabs({
    required this.categories,
    required this.selected,
    required this.onSelected,
    required this.showBookmarksOnly,
    required this.bookmarkCount,
    required this.onBookmarkToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tabs = [...categories];

    return Container(
      height: 48,
      color: cs.surface,
      child: Row(
        children: [
          // Bookmark toggle
          GestureDetector(
            onTap: onBookmarkToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: showBookmarksOnly
                    ? cs.primary.withAlpha(26)
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                border: Border.all(
                  color: showBookmarksOnly ? cs.primary : Colors.transparent,
                  width: 1.5)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    showBookmarksOnly
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    size: 14,
                    color: showBookmarksOnly ? cs.primary : cs.outline),
                  if (bookmarkCount > 0) ...[
                    const SizedBox(width: 4),
                    Text('$bookmarkCount',
                        style: GoogleFonts.manrope(
                            fontSize: 11, fontWeight: FontWeight.w700,
                            color: showBookmarksOnly ? cs.primary : cs.outline)),
                  ],
                ],
              ),
            ),
          ),
          Container(width: 1, height: 24, color: cs.surfaceContainerHighest),
          // Category chips
          Expanded(
            child: Builder(builder: (context) {
              // Resolve the two label styles ONCE. GoogleFonts.manrope() does a
              // registry lookup on every call, and calling it inside
              // itemBuilder meant every chip re-resolved its font on every
              // frame of a drag — which is what made this strip stutter.
              final selectedStyle = GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: cs.primary);
              final unselectedStyle = GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: cs.outline);
              return ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              itemCount: tabs.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final label = tabs[index];
                final isSelected = selected == label && !showBookmarksOnly;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onSelected(label),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    child: AnimatedContainer(
                      duration: AppTheme.fastMicro,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? cs.primary.withAlpha(26)
                            : cs.surfaceContainerHighest,
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusFull),
                        border: Border.all(
                          color: isSelected
                              ? cs.primary
                              : Colors.transparent,
                          width: 1.5)),
                      child: Text(label,
                          style:
                              isSelected ? selectedStyle : unselectedStyle),
                    ),
                  ),
                );
              },
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ── Continue Reading Banner ──────────────────────────────────
class _ContinueReadingBanner extends StatelessWidget {
  final LibraryManga manga;
  final VoidCallback onTap;

  const _ContinueReadingBanner({required this.manga, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = manga.totalChapters > 0
        ? manga.readChapters / manga.totalChapters
        : 0.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.primary.withAlpha(26),
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: cs.primary.withAlpha(80))),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: manga.coverUrl.isNotEmpty
                  ? MangaImage(
                      imageUrl: manga.coverUrl, width: 36, height: 50,
                      referer: _originOf(manga.url),
                      fit: BoxFit.cover)
                  : Container(width: 36, height: 50, color: cs.surfaceContainerHighest),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Continue Reading',
                      style: GoogleFonts.manrope(
                          fontSize: 10, fontWeight: FontWeight.w600,
                          color: cs.primary, letterSpacing: 0.5)),
                  const SizedBox(height: 2),
                  Text(manga.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                          fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress, minHeight: 3,
                            backgroundColor: cs.primary.withAlpha(40),
                            valueColor: AlwaysStoppedAnimation<Color>(cs.primary)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Ch. ${manga.readChapters}/${manga.totalChapters}',
                          style: GoogleFonts.manrope(fontSize: 10, color: cs.outline)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
              child: Icon(Icons.play_arrow_rounded, size: 16, color: cs.onPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Library Grid ─────────────────────────────────────────────
class _LibraryGrid extends StatefulWidget {
  final List<LibraryManga> mangaList;
  final int columnCount;
  final Set<String>? selectedIds;
  final ValueChanged<LibraryManga> onTap;
  final ValueChanged<LibraryManga> onLongPress;

  const _LibraryGrid({
    required this.mangaList, required this.columnCount,
    this.selectedIds,
    required this.onTap, required this.onLongPress});

  @override
  State<_LibraryGrid> createState() => _LibraryGridState();
}

class _LibraryGridState extends State<_LibraryGrid>
    with TickerProviderStateMixin {
  late List<AnimationController> _itemControllers;
  late List<Animation<double>> _itemAnimations;

  @override
  void initState() {
    super.initState();
    _itemControllers = List.generate(widget.mangaList.length,
        (i) => AnimationController(vsync: this, duration: AppTheme.entrance));
    _itemAnimations = _itemControllers
        .map((c) => CurvedAnimation(parent: c, curve: AppTheme.primaryCurve))
        .toList();
    for (int i = 0; i < _itemControllers.length; i++) {
      Future.delayed(Duration(milliseconds: (i * 40).clamp(0, 400)), () {
        if (mounted) _itemControllers[i].forward();
      });
    }
  }

  @override
  void dispose() {
    for (final c in _itemControllers) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      // Always scrollable so pull-to-refresh triggers even when the grid
      // doesn't fill the screen.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.columnCount,
        childAspectRatio: 0.62, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: widget.mangaList.length,
      itemBuilder: (_, index) {
        final m = widget.mangaList[index];
        final isSelected = widget.selectedIds?.contains('${m.sourceId}::${m.url}') ?? false;
        final card = _MangaGridCard(
          manga: m,
          isSelected: isSelected,
          onTap: () => widget.onTap(m),
          onLongPress: () => widget.onLongPress(m));
        if (index >= _itemAnimations.length) return card;
        return FadeTransition(
          opacity: _itemAnimations[index],
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
                .animate(_itemAnimations[index]),
            child: card));
      },
    );
  }
}

// ── Grid Card ────────────────────────────────────────────────
class _MangaGridCard extends StatefulWidget {
  final LibraryManga manga;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _MangaGridCard({required this.manga, this.isSelected = false, required this.onTap, required this.onLongPress});

  @override
  State<_MangaGridCard> createState() => _MangaGridCardState();
}

class _MangaGridCardState extends State<_MangaGridCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut));
  }

  @override
  void dispose() { _pressController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unread = widget.manga.totalChapters - widget.manga.readChapters;
    final progress = widget.manga.totalChapters > 0
        ? widget.manga.readChapters / widget.manga.totalChapters : 0.0;

    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) => _pressController.reverse(),
      onTapCancel: () => _pressController.reverse(),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.manga.coverUrl.isNotEmpty
                  ? MangaImage(imageUrl: widget.manga.coverUrl, fit: BoxFit.cover,
                      referer: _originOf(widget.manga.url))
                  : Container(color: cs.surfaceContainerHighest,
                      child: Icon(Icons.image_rounded, color: cs.outline, size: 32)),
              // Gradient
              Positioned(bottom: 0, left: 0, right: 0, child: Container(
                height: 90, decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xDD000000)])))),
              // Progress bar
              if (progress > 0)
                Positioned(bottom: 0, left: 0, right: 0,
                  child: Container(height: 3, color: Colors.white.withAlpha(40),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft, widthFactor: progress.clamp(0.0, 1.0),
                      child: Container(decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(2), bottomRight: Radius.circular(2))))))),
              // Title
              Positioned(bottom: progress > 0 ? 8 : 8, left: 8, right: 8,
                child: Text(widget.manga.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700,
                        color: Colors.white, height: 1.3,
                        shadows: const [Shadow(color: Colors.black, blurRadius: 4)]))),
              // Unread badge
              if (unread > 0)
                Positioned(top: 6, right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
                    child: Text(unread > 99 ? '99+' : '$unread',
                        style: GoogleFonts.manrope(
                            fontSize: 10, fontWeight: FontWeight.w800, color: cs.onPrimary)))),
              // Selection overlay
              if (widget.isSelected) ...[
                Container(color: cs.primary.withAlpha(60)),
                Positioned(top: 6, left: 6,
                  child: Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: cs.primary, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, size: 16, color: Colors.white))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Library List ─────────────────────────────────────────────
class _LibraryList extends StatelessWidget {
  final List<LibraryManga> mangaList;
  final Set<String>? selectedIds;
  final ValueChanged<LibraryManga> onTap;
  final ValueChanged<LibraryManga> onLongPress;
  const _LibraryList({required this.mangaList, this.selectedIds, required this.onTap, required this.onLongPress});

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'reading': return AppTheme.success;
      case 'completed': return AppTheme.secondary;
      case 'on hold': return AppTheme.warning;
      case 'dropped': return AppTheme.error;
      default: return AppTheme.mutedDark;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
      itemCount: mangaList.length,
      itemBuilder: (_, index) {
        final manga = mangaList[index];
        final unread = manga.totalChapters - manga.readChapters;
        final isSelected = selectedIds?.contains('${manga.sourceId}::${manga.url}') ?? false;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => onTap(manga),
            onLongPress: () => onLongPress(manga),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isSelected ? cs.primary.withAlpha(30) : cs.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border(left: BorderSide(color: isSelected ? cs.primary : _statusColor(manga.status), width: 3))),
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    child: manga.coverUrl.isNotEmpty
                        ? MangaImage(imageUrl: manga.coverUrl, width: 52, height: 72, fit: BoxFit.cover,
                            referer: _originOf(manga.url))
                        : Container(width: 52, height: 72, color: cs.surfaceContainerHighest)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(manga.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.library_books_rounded, size: 11, color: cs.outline),
                        const SizedBox(width: 3),
                        Text('${manga.readChapters}/${manga.totalChapters} chapters',
                            style: GoogleFonts.manrope(fontSize: 11, color: cs.outline)),
                      ]),
                      const SizedBox(height: 6),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _statusColor(manga.status).withAlpha(38),
                            borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
                          child: Text(manga.status.isEmpty ? 'Unknown' : manga.status,
                              style: GoogleFonts.manrope(
                                  fontSize: 10, fontWeight: FontWeight.w600, color: _statusColor(manga.status)))),
                        const Spacer(),
                        if (unread > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
                            child: Text(unread > 99 ? '99+' : '$unread',
                                style: GoogleFonts.manrope(fontSize: 10, fontWeight: FontWeight.w800, color: cs.onPrimary))),
                      ]),
                    ],
                  )),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Empty State ──────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final bool isSearching;
  final String searchQuery;
  final bool isBookmarkFilter;
  const _EmptyState({required this.isSearching, required this.searchQuery, this.isBookmarkFilter = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isBookmarkFilter ? Icons.bookmark_border_rounded : Icons.collections_bookmark_outlined,
              size: 64, color: cs.outline.withAlpha(128)),
            const SizedBox(height: 16),
            Text(
              isBookmarkFilter ? 'No bookmarks yet'
                  : isSearching ? 'No results' : 'Library is empty',
              style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text(
              isBookmarkFilter
                  ? 'Long-press a manga and bookmark it to see it here.'
                  : isSearching
                      ? 'No results for "$searchQuery". Try a different search.'
                      : 'Your library is empty. Browse sources to add manga.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 13, color: cs.outline)),
          ],
        ),
      ),
    );
  }
}

// ── Manga Context Sheet ─────────────────────────────────────
class _MangaContextSheet extends StatelessWidget {
  final LibraryManga manga;
  final List<String> categories;
  final VoidCallback onMoveCategory;
  final VoidCallback onMarkRead;
  final VoidCallback onMarkUnread;
  final VoidCallback onRemove;

  const _MangaContextSheet({
    required this.manga, required this.categories,
    required this.onMoveCategory, required this.onMarkRead,
    required this.onMarkUnread, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text(manga.title, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface),
              maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
          if (manga.categories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(manga.categories.join(', '),
                  style: GoogleFonts.manrope(fontSize: 11, color: cs.outline)),
            ),
          const SizedBox(height: 16),
          if (categories.isNotEmpty)
            _SheetAction(icon: Icons.drive_file_move_rounded, label: 'Move to Category',
                color: cs.primary, onTap: onMoveCategory),
          _SheetAction(icon: Icons.done_all_rounded, label: 'Mark All as Read',
              color: AppTheme.success, onTap: onMarkRead),
          _SheetAction(icon: Icons.remove_done_rounded, label: 'Mark All as Unread',
              color: AppTheme.warning, onTap: onMarkUnread),
          _SheetAction(icon: Icons.delete_outline_rounded, label: 'Remove from Library',
              color: AppTheme.error, onTap: onRemove),
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SheetAction({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Text(label, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
          ]),
        ),
      ),
    );
  }
}

class _BatchButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _BatchButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: cs.onSurface),
            const SizedBox(height: 4),
            Text(label, style: GoogleFonts.manrope(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurface)),
          ],
        ),
      ),
    );
  }
}
