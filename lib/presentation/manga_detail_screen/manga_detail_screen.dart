import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/manga_image.dart';
import '../../core/models/manga_model.dart';
import '../../core/providers/source_provider.dart';
import '../../core/providers/library_provider.dart';
import '../../core/providers/tracking_provider.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/utils/html_util.dart';
import '../tracking/tracking_sheet.dart';
import '../../core/providers/download_provider.dart';
import '../../core/services/local_source_service.dart';
import 'migrate_screen.dart';
import '../../eval/lib.dart';
import '../../eval/model/m_manga.dart';
import '../../eval/model/m_chapter.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../core/utils/date_format.dart';

class MangaDetailScreen extends StatefulWidget {
  final String mangaUrl;
  final String sourceId;
  final String? title;
  final String? coverUrl;

  const MangaDetailScreen({
    super.key,
    required this.mangaUrl,
    required this.sourceId,
    this.title,
    this.coverUrl,
  });

  @override
  State<MangaDetailScreen> createState() => _MangaDetailScreenState();
}

class _MangaDetailScreenState extends State<MangaDetailScreen> {
  MManga? _manga;
  bool _isLoading = true;
  String? _error;
  bool _descExpanded = false;

  // Chapter toolbar state
  bool _sortAscending = false;
  bool _filterUnread = false;
  bool _filterBookmarked = false;
  bool _chapterSearchActive = false;
  String _chapterSearchQuery = '';
  final _chapterSearchController = TextEditingController();
  final Set<String> _bookmarkedChapterUrls = {};

  // Multi-select mode (entered via three-dots "Select chapters" or long-press)
  bool _selectionMode = false;
  final Set<String> _selectedChapterUrls = {};

  // Per-manga note (persisted in SharedPreferences)
  String _note = '';

  String _safeOrigin(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return '';
    try { return uri.origin; } catch (_) { return ''; }
  }

  @override
  void initState() {
    super.initState();
    _loadDetail();
    _loadNote();
  }

  String get _noteKey => 'manga_note_${widget.sourceId}_${widget.mangaUrl}';

  Future<void> _loadNote() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_noteKey) ?? '';
      if (mounted && v.isNotEmpty) setState(() => _note = v);
    } catch (_) {}
  }

  Future<void> _saveNote(String value) async {
    setState(() => _note = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value.trim().isEmpty) {
        await prefs.remove(_noteKey);
      } else {
        await prefs.setString(_noteKey, value);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _chapterSearchController.dispose();
    super.dispose();
  }

  List<MChapter> _getFilteredChapters(LibraryProvider libraryProvider) {
    var chapters = List<MChapter>.from(_manga?.chapters ?? []);
    if (_sortAscending) chapters = chapters.reversed.toList();
    if (_filterUnread) {
      chapters = chapters.where((c) =>
          !libraryProvider.isChapterRead(widget.sourceId, c.url ?? '')).toList();
    }
    if (_filterBookmarked) {
      chapters = chapters.where((c) =>
          _bookmarkedChapterUrls.contains(c.url ?? '')).toList();
    }
    if (_chapterSearchQuery.isNotEmpty) {
      final q = _chapterSearchQuery.toLowerCase();
      chapters = chapters.where((c) =>
          (c.name ?? '').toLowerCase().contains(q)).toList();
    }
    return chapters;
  }

  // ── Chapter actions ─────────────────────────────────────────
  void _toggleBookmark(String chapterUrl) {
    setState(() {
      if (_bookmarkedChapterUrls.contains(chapterUrl)) {
        _bookmarkedChapterUrls.remove(chapterUrl);
      } else {
        _bookmarkedChapterUrls.add(chapterUrl);
      }
    });
  }

  Future<void> _setChapterRead(
      String chapterUrl, bool read, LibraryProvider lib) async {
    if (read) {
      await lib.markChapterRead(widget.sourceId, widget.mangaUrl, chapterUrl);
    } else {
      await lib.markChapterUnread(widget.sourceId, widget.mangaUrl, chapterUrl);
    }
  }

  // "Mark all below as read" — marks the given chapter plus every chapter that
  // sits below it in the currently-displayed order.
  Future<void> _markBelowRead(String chapterUrl, LibraryProvider lib) async {
    final displayed = _getFilteredChapters(lib);
    final idx = displayed.indexWhere((c) => (c.url ?? '') == chapterUrl);
    if (idx < 0) return;
    for (final c in displayed.sublist(idx)) {
      final url = c.url ?? '';
      if (url.isEmpty) continue;
      await lib.markChapterRead(widget.sourceId, widget.mangaUrl, url);
    }
    if (mounted) setState(() {});
  }

  void _downloadChapter(MChapter chapter) {
    final chapterUrl = chapter.url ?? '';
    if (chapterUrl.isEmpty) return;
    final dlProvider = context.read<DownloadProvider>();
    final title = _manga?.name ?? widget.title ?? 'Unknown';
    final isAnime = context.read<SourceProvider>()
        .getInstalledSource(widget.sourceId)?.source.isAnime ?? false;
    if (isAnime) {
      dlProvider.enqueueEpisode(
        sourceId: widget.sourceId,
        animeUrl: widget.mangaUrl,
        animeTitle: title,
        episodeUrl: chapterUrl,
        episodeName: chapter.name ?? 'Episode',
      );
    } else {
      dlProvider.enqueueChapter(
        sourceId: widget.sourceId,
        mangaUrl: widget.mangaUrl,
        mangaTitle: title,
        chapterUrl: chapterUrl,
        chapterName: chapter.name ?? 'Chapter',
      );
    }
  }

  // Bottom-sheet menu shown when a chapter is long-pressed (not in select mode).
  void _showChapterActions(
      BuildContext context, MChapter chapter, LibraryProvider lib) {
    final chapterUrl = chapter.url ?? '';
    if (chapterUrl.isEmpty) return;
    final cs = Theme.of(context).colorScheme;
    final isBookmarked = _bookmarkedChapterUrls.contains(chapterUrl);
    final isRead = lib.isChapterRead(widget.sourceId, chapterUrl);
    final isDl = context.read<DownloadProvider>()
        .isDownloaded(widget.sourceId, chapterUrl);

    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(chapter.name ?? 'Chapter',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          ListTile(
            leading: Icon(isBookmarked
                ? Icons.bookmark_remove_rounded
                : Icons.bookmark_add_rounded, color: cs.primary),
            title: Text(isBookmarked ? 'Remove bookmark' : 'Bookmark',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
            onTap: () { Navigator.pop(sheetCtx); _toggleBookmark(chapterUrl); },
          ),
          ListTile(
            leading: Icon(Icons.done_all_rounded, color: cs.primary),
            title: Text('Mark all below as read',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
            onTap: () { Navigator.pop(sheetCtx); _markBelowRead(chapterUrl, lib); },
          ),
          ListTile(
            leading: Icon(isRead
                ? Icons.visibility_off_rounded
                : Icons.check_circle_rounded, color: cs.primary),
            title: Text(isRead ? 'Mark as unread' : 'Mark chapter as read',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
            onTap: () async {
              Navigator.pop(sheetCtx);
              await _setChapterRead(chapterUrl, !isRead, lib);
            },
          ),
          ListTile(
            leading: Icon(isDl
                ? Icons.download_done_rounded
                : Icons.download_rounded, color: cs.primary),
            title: Text(isDl ? 'Downloaded' : 'Download',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
            enabled: !isDl,
            onTap: isDl ? null : () {
              Navigator.pop(sheetCtx);
              _downloadChapter(chapter);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ── Multi-select mode ───────────────────────────────────────
  void _enterSelectionMode([String? firstUrl]) {
    setState(() {
      _selectionMode = true;
      if (firstUrl != null && firstUrl.isNotEmpty) {
        _selectedChapterUrls.add(firstUrl);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedChapterUrls.clear();
    });
  }

  void _toggleSelection(String chapterUrl) {
    if (chapterUrl.isEmpty) return;
    setState(() {
      if (_selectedChapterUrls.contains(chapterUrl)) {
        _selectedChapterUrls.remove(chapterUrl);
        if (_selectedChapterUrls.isEmpty) _selectionMode = false;
      } else {
        _selectedChapterUrls.add(chapterUrl);
      }
    });
  }

  void _selectAllChapters(LibraryProvider lib) {
    setState(() {
      for (final c in _getFilteredChapters(lib)) {
        final u = c.url ?? '';
        if (u.isNotEmpty) _selectedChapterUrls.add(u);
      }
    });
  }

  Future<void> _bulkSetRead(bool read, LibraryProvider lib) async {
    final urls = _selectedChapterUrls.toList();
    for (final url in urls) {
      await _setChapterRead(url, read, lib);
    }
    _exitSelectionMode();
  }

  void _bulkBookmark() {
    setState(() {
      // If every selected chapter is already bookmarked, toggle them all off;
      // otherwise bookmark the ones that aren't yet.
      final allBookmarked = _selectedChapterUrls
          .every((u) => _bookmarkedChapterUrls.contains(u));
      for (final u in _selectedChapterUrls) {
        if (allBookmarked) {
          _bookmarkedChapterUrls.remove(u);
        } else {
          _bookmarkedChapterUrls.add(u);
        }
      }
    });
    _exitSelectionMode();
  }

  // "Mark all below as read" in selection mode: read from the lowest selected
  // chapter downward in display order.
  Future<void> _bulkMarkBelowRead(LibraryProvider lib) async {
    final displayed = _getFilteredChapters(lib);
    var lowest = -1;
    for (var i = 0; i < displayed.length; i++) {
      if (_selectedChapterUrls.contains(displayed[i].url ?? '')) lowest = i;
    }
    if (lowest < 0) { _exitSelectionMode(); return; }
    for (final c in displayed.sublist(lowest)) {
      final url = c.url ?? '';
      if (url.isEmpty) continue;
      await lib.markChapterRead(widget.sourceId, widget.mangaUrl, url);
    }
    _exitSelectionMode();
  }

  void _bulkDownload(LibraryProvider lib) {
    final displayed = _getFilteredChapters(lib);
    for (final c in displayed) {
      if (_selectedChapterUrls.contains(c.url ?? '')) _downloadChapter(c);
    }
    _exitSelectionMode();
  }

  // ── Notes ───────────────────────────────────────────────────
  void _showNotesDialog(BuildContext context) {
    final controller = TextEditingController(text: _note);
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Notes'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: 'Add a note for this title…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              _saveNote(controller.text);
              Navigator.pop(dCtx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemoveFromLibrary(
      BuildContext context, LibraryProvider lib) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('Remove from library?'),
        content: Text(
            'Remove "${_manga?.name ?? widget.title ?? 'this title'}" from your library?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) {
      await lib.removeFromLibrary(widget.sourceId, widget.mangaUrl);
      if (mounted) Navigator.pop(context);
    }
  }

  Widget _buildSelectionBar(BuildContext context, LibraryProvider lib) {
    final cs = Theme.of(context).colorScheme;
    final count = _selectedChapterUrls.length;
    final disabled = count == 0;
    Widget action(IconData icon, String tooltip, VoidCallback? onTap) => IconButton(
          icon: Icon(icon),
          tooltip: tooltip,
          color: cs.onSurface,
          disabledColor: cs.outline.withAlpha(90),
          onPressed: disabled ? null : onTap,
        );
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Done',
                onPressed: _exitSelectionMode,
              ),
              Text('$count selected',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(
                onPressed: () => _selectAllChapters(lib),
                child: const Text('Select all'),
              ),
            ]),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            action(Icons.bookmark_add_rounded, 'Bookmark', _bulkBookmark),
            action(Icons.done_all_rounded, 'Mark all below as read',
                () => _bulkMarkBelowRead(lib)),
            action(Icons.check_circle_rounded, 'Mark as read',
                () => _bulkSetRead(true, lib)),
            action(Icons.visibility_off_rounded, 'Mark as unread',
                () => _bulkSetRead(false, lib)),
            action(Icons.download_rounded, 'Download', () => _bulkDownload(lib)),
          ]),
        ]),
      ),
    );
  }

  Future<void> _loadDetail({bool forceRefresh = false}) async {
    final libraryProvider = context.read<LibraryProvider>();
    final inLibrary = libraryProvider.isInLibrary(widget.sourceId, widget.mangaUrl);

    // Show cached chapters instantly for library manga
    if (!forceRefresh && inLibrary && _manga == null) {
      final cached = libraryProvider.getCachedChapters(widget.sourceId, widget.mangaUrl);
      if (cached.isNotEmpty) {
        final cachedManga = MManga();
        // Populate from LibraryManga metadata
        final lm = libraryProvider.manga.cast<LibraryManga?>().firstWhere(
            (m) => m!.sourceId == widget.sourceId && m.url == widget.mangaUrl,
            orElse: () => null);
        if (lm != null) {
          cachedManga.name = lm.title;
          cachedManga.imageUrl = lm.coverUrl;
          cachedManga.author = lm.author;
          cachedManga.description = lm.description;
          cachedManga.genre = lm.genres;
        }
        cachedManga.chapters = cached.map((c) => MChapter(
          url: c.chapterUrl,
          name: c.title,
          dateUpload: c.dateUpload,
        )).toList();
        setState(() { _manga = cachedManga; _isLoading = false; });
        // Refresh in background
        _refreshInBackground();
        return;
      }
    }

    setState(() { _isLoading = true; _error = null; });
    try {
      // Handle local sources
      if (widget.sourceId == 'local' && widget.mangaUrl.startsWith('local://')) {
        final localPath = widget.mangaUrl.replaceFirst('local://', '');
        final localService = LocalSourceService();
        final allManga = await localService.scanAll();
        final localManga = allManga.cast<LocalManga?>().firstWhere(
            (m) => m!.path == localPath, orElse: () => null);
        if (localManga != null) {
          final manga = MManga();
          manga.name = localManga.title;
          manga.author = localManga.author;
          manga.description = localManga.description;
          manga.genre = localManga.genres;
          if (localManga.coverPath != null) manga.imageUrl = 'file://${localManga.coverPath}';
          manga.chapters = localManga.chapters.map((c) => MChapter(
            name: c.name,
            url: c.isArchive ? 'archive://${c.path}' : 'file://${c.path}',
          )).toList();
          if (mounted) setState(() => _manga = manga);
          if (mounted) setState(() => _isLoading = false);
          return;
        }
      }

      final sourceProvider = context.read<SourceProvider>();
      final installed = sourceProvider.getInstalledSource(widget.sourceId);
      if (installed == null) throw Exception('Source not installed');
      final manga = await withExtensionService(
        installed.source, installed.sourceCode,
        (service) => service.getDetail(widget.mangaUrl),
      );
      if (mounted) {
        setState(() => _manga = manga);
        // Cache chapters if in library
        if (inLibrary && manga.chapters != null) {
          libraryProvider.cacheChapters(widget.sourceId, widget.mangaUrl,
              manga.chapters!.map((c) => c.toJson()).toList());
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _refreshInBackground() async {
    try {
      final sourceProvider = context.read<SourceProvider>();
      final installed = sourceProvider.getInstalledSource(widget.sourceId);
      if (installed == null) return;
      final manga = await withExtensionService(
        installed.source, installed.sourceCode,
        (service) => service.getDetail(widget.mangaUrl),
      );
      if (mounted) {
        setState(() => _manga = manga);
        final libraryProvider = context.read<LibraryProvider>();
        if (manga.chapters != null) {
          libraryProvider.cacheChapters(widget.sourceId, widget.mangaUrl,
              manga.chapters!.map((c) => c.toJson()).toList());
        }
      }
    } catch (_) {
      // Silent fail — cached data is already showing
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final coverUrl = _manga?.imageUrl ?? widget.coverUrl;
    final title = _manga?.name ?? widget.title ?? '';
    final libraryProvider = context.watch<LibraryProvider>();
    final inLibrary = libraryProvider.isInLibrary(widget.sourceId, widget.mangaUrl);
    final libraryManga = inLibrary
        ? libraryProvider.manga.cast<LibraryManga?>().firstWhere(
            (m) => m!.sourceId == widget.sourceId && m.url == widget.mangaUrl,
            orElse: () => null)
        : null;

    return Scaffold(
      bottomNavigationBar: _selectionMode
          ? _buildSelectionBar(context, libraryProvider)
          : null,
      body: RefreshIndicator(
        onRefresh: () => _loadDetail(forceRefresh: true),
        color: cs.primary,
        child: CustomScrollView(
        slivers: [
          // App bar with cover
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: cs.surface,
            actions: [
              // Download menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.download_rounded),
                tooltip: 'Download',
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'dl_next_1', child: Text('Next chapter')),
                  const PopupMenuItem(value: 'dl_next_5', child: Text('Next 5 chapters')),
                  const PopupMenuItem(value: 'dl_next_10', child: Text('Next 10 chapters')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'dl_unread', child: Text('All unread')),
                  const PopupMenuItem(value: 'dl_all', child: Text('All chapters')),
                ],
                onSelected: (v) => _handleBulkDownload(v, context, libraryProvider),
              ),
              // Overflow menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                itemBuilder: (_) => [
                  if (inLibrary) ...[
                    const PopupMenuItem(value: 'edit_category', child: Text('Edit categories')),
                    const PopupMenuItem(value: 'notes', child: Text('Notes')),
                    const PopupMenuItem(value: 'migrate', child: Text('Migrate')),
                  ],
                  const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                  if ((_manga?.chapters?.isNotEmpty ?? false))
                    const PopupMenuItem(value: 'select', child: Text('Select chapters')),
                  if (inLibrary)
                    const PopupMenuItem(value: 'remove', child: Text('Remove from library')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'webview', child: Text('Open in browser')),
                ],
                onSelected: (v) {
                  if (v == 'webview') {
                    Navigator.pushNamed(context, AppRoutes.webview,
                        arguments: {'url': widget.mangaUrl, 'title': title});
                  } else if (v == 'refresh') {
                    _loadDetail(forceRefresh: true);
                  } else if (v == 'edit_category') {
                    _showMoveCategorySheet(context);
                  } else if (v == 'notes') {
                    _showNotesDialog(context);
                  } else if (v == 'select') {
                    _enterSelectionMode();
                  } else if (v == 'remove') {
                    _confirmRemoveFromLibrary(context, libraryProvider);
                  } else if (v == 'migrate') {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => MigrateScreen(
                        sourceId: widget.sourceId,
                        mangaUrl: widget.mangaUrl,
                        mangaTitle: _manga?.name ?? widget.title ?? '',
                      ),
                    ));
                  }
                },
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: coverUrl != null && coverUrl.isNotEmpty
                  ? Stack(fit: StackFit.expand, children: [
                      MangaImage(imageUrl: coverUrl, referer: _safeOrigin(widget.mangaUrl)),
                      DecoratedBox(decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter, end: Alignment.bottomCenter,
                          colors: [Colors.transparent, cs.surface],
                        ),
                      )),
                    ])
                  : null,
            ),
          ),

          if (_isLoading)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            SliverFillRemaining(child: Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, color: cs.outline, size: 48),
                const SizedBox(height: 12),
                Text(_error!, style: GoogleFonts.manrope(fontSize: 12, color: cs.outline),
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _loadDetail, child: const Text('Retry')),
              ],
            )))
          else ...[
            // Title + metadata
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: GoogleFonts.manrope(
                    fontSize: 22, fontWeight: FontWeight.w800, color: cs.onSurface)),
                const SizedBox(height: 6),
                if (_manga?.author != null && _manga!.author!.isNotEmpty)
                  Row(children: [
                    Icon(Icons.person_outline_rounded, size: 14, color: cs.outline),
                    const SizedBox(width: 4),
                    Text(_manga!.author!, style: GoogleFonts.manrope(fontSize: 13, color: cs.outline)),
                  ]),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.schedule_rounded, size: 14, color: cs.outline),
                  const SizedBox(width: 4),
                  Text(_statusText(_manga?.status ?? MangaStatus.unknown),
                      style: GoogleFonts.manrope(fontSize: 13, color: cs.outline)),
                ]),
              ]),
            )),

            // Action buttons row: Library | Tracking | WebView
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                // Library button
                Expanded(child: _ActionButton(
                  icon: inLibrary ? Icons.favorite_rounded : Icons.favorite_border,
                  label: inLibrary ? 'Remove' : 'Add',
                  active: inLibrary,
                  cs: cs,
                  onTap: () {
                    if (inLibrary) {
                      libraryProvider.removeFromLibrary(widget.sourceId, widget.mangaUrl);
                    } else {
                      _addToLibrary(context);
                    }
                  },
                )),
                const SizedBox(width: 8),
                // Tracking button
                Expanded(child: _ActionButton(
                  icon: Icons.sync_rounded,
                  label: 'Tracking',
                  active: context.watch<TrackingProvider>()
                      .bindingsFor('${widget.sourceId}_${widget.mangaUrl}')
                      .isNotEmpty,
                  cs: cs,
                  onTap: () {
                    final readCount = _manga?.chapters
                            ?.where((c) => libraryProvider.isChapterRead(
                                widget.sourceId, c.url ?? ''))
                            .length ??
                        0;
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: cs.surface,
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(20))),
                      builder: (_) => TrackingSheet(
                        mangaKey: '${widget.sourceId}_${widget.mangaUrl}',
                        title: title,
                        localProgress: readCount,
                      ),
                    );
                  },
                )),
                const SizedBox(width: 8),
                // WebView button
                Expanded(child: _ActionButton(
                  icon: Icons.public_rounded,
                  label: 'WebView',
                  active: false,
                  cs: cs,
                  onTap: () => Navigator.pushNamed(context, AppRoutes.webview,
                      arguments: {'url': widget.mangaUrl, 'title': title}),
                )),
              ]),
            )),

            // Description
            if (_manga?.description != null && _manga!.description!.isNotEmpty)
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  onTap: () => setState(() => _descExpanded = !_descExpanded),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(stripHtml(_manga!.description!),
                        style: GoogleFonts.manrope(fontSize: 13, color: cs.onSurface.withAlpha(200)),
                        maxLines: _descExpanded ? 100 : 3,
                        overflow: TextOverflow.ellipsis),
                    Icon(_descExpanded ? Icons.expand_less : Icons.expand_more,
                        color: cs.outline, size: 20),
                  ]),
                ),
              )),

            // Note banner (only when a note exists)
            if (_note.trim().isNotEmpty)
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: InkWell(
                  onTap: () => _showNotesDialog(context),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withAlpha(90),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      border: Border.all(color: cs.primary.withAlpha(80)),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.sticky_note_2_rounded, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_note,
                          style: GoogleFonts.manrope(fontSize: 13, color: cs.onSurface))),
                    ]),
                  ),
                ),
              )),

            // Genres
            if (_manga?.genre != null && _manga!.genre!.isNotEmpty)
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Wrap(spacing: 6, runSpacing: 6, children: _manga!.genre!.map((g) =>
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: cs.outlineVariant),
                    ),
                    child: Text(g, style: GoogleFonts.manrope(fontSize: 11, color: cs.onSurface)),
                  ),
                ).toList()),
              )),

            // Chapter toolbar
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: _chapterSearchActive
                  ? Row(children: [
                      Expanded(child: TextField(
                        controller: _chapterSearchController,
                        autofocus: true,
                        style: GoogleFonts.manrope(fontSize: 14, color: cs.onSurface),
                        decoration: InputDecoration(
                          hintText: 'Search chapters...',
                          hintStyle: GoogleFonts.manrope(fontSize: 14, color: cs.outline),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: cs.outlineVariant)),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: cs.primary)),
                        ),
                        onChanged: (v) => setState(() => _chapterSearchQuery = v),
                      )),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => setState(() {
                          _chapterSearchActive = false;
                          _chapterSearchQuery = '';
                          _chapterSearchController.clear();
                        }),
                      ),
                    ])
                  : Row(children: [
                      Text('${_manga?.chapters?.length ?? 0} Chapters',
                          style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w800, color: cs.onSurface)),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.search_rounded, size: 20, color: cs.outline),
                        tooltip: 'Search chapters',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _chapterSearchActive = true),
                      ),
                      IconButton(
                        icon: Icon(
                          _sortAscending ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                          size: 20, color: cs.outline),
                        tooltip: _sortAscending ? 'Oldest first' : 'Newest first',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _sortAscending = !_sortAscending),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.filter_list_rounded, size: 20,
                            color: (_filterUnread || _filterBookmarked) ? cs.primary : cs.outline),
                        tooltip: 'Filter',
                        itemBuilder: (_) => [
                          CheckedPopupMenuItem<String>(
                            value: 'unread', checked: _filterUnread,
                            child: Text('Unread', style: GoogleFonts.manrope(fontSize: 14)),
                          ),
                          CheckedPopupMenuItem<String>(
                            value: 'bookmarked', checked: _filterBookmarked,
                            child: Text('Bookmarked', style: GoogleFonts.manrope(fontSize: 14)),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem<String>(
                            value: 'mark_all_read',
                            child: Row(children: [
                              Icon(Icons.done_all_rounded, size: 18, color: cs.onSurface),
                              const SizedBox(width: 8),
                              Text('Mark all as read', style: GoogleFonts.manrope(fontSize: 14)),
                            ]),
                          ),
                          PopupMenuItem<String>(
                            value: 'mark_all_unread',
                            child: Row(children: [
                              Icon(Icons.remove_done_rounded, size: 18, color: cs.onSurface),
                              const SizedBox(width: 8),
                              Text('Mark all as unread', style: GoogleFonts.manrope(fontSize: 14)),
                            ]),
                          ),
                        ],
                        onSelected: (value) {
                          if (value == 'unread') setState(() => _filterUnread = !_filterUnread);
                          else if (value == 'bookmarked') setState(() => _filterBookmarked = !_filterBookmarked);
                          else if (value == 'mark_all_read') libraryProvider.markAllRead(widget.sourceId, widget.mangaUrl);
                          else if (value == 'mark_all_unread') libraryProvider.markAllUnread(widget.sourceId, widget.mangaUrl);
                        },
                      ),
                    ]),
            )),

            // Login prompt when 0 chapters
            if ((_manga?.chapters?.isEmpty ?? true) && _manga != null)
              SliverToBoxAdapter(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(children: [
                    Icon(Icons.lock_outline_rounded, size: 32, color: cs.outline),
                    const SizedBox(height: 8),
                    Text('Login may be required',
                        style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    const SizedBox(height: 4),
                    Text('This content may require logging in to view chapters.',
                        style: GoogleFonts.manrope(fontSize: 12, color: cs.outline), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.login_rounded, size: 16),
                        label: Text('Login in Browser',
                            style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 12)),
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.primary, foregroundColor: cs.onPrimary,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                        onPressed: () async {
                          final sourceProvider = context.read<SourceProvider>();
                          final installed = sourceProvider.getInstalledSource(widget.sourceId);
                          final loginUrl = installed?.source.config['loginUrl'] as String?
                              ?? installed?.source.baseUrl ?? '';
                          await Navigator.pushNamed(context, AppRoutes.webview,
                              arguments: {'url': loginUrl, 'title': 'Login'});
                          _loadDetail();
                        },
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _loadDetail,
                        style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
                        child: Text('Retry', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 12)),
                      ),
                    ]),
                  ]),
                ),
              )),

            // Chapter list
            Builder(builder: (context) {
              final filtered = _getFilteredChapters(libraryProvider);
              final allChapterMaps = _manga!.chapters!.map((c) => {'url': c.url, 'name': c.name}).toList();
              return SliverList(delegate: SliverChildBuilderDelegate(
                (_, i) => _buildChapterTile(context, filtered[i], libraryProvider, libraryManga, allChapterMaps),
                childCount: filtered.length,
              ));
            }),
            const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
          ],
        ],
      )),
      // Resume FAB
      floatingActionButton: !_selectionMode &&
              libraryManga?.lastReadChapterUrl != null && _manga?.chapters != null
          ? FloatingActionButton.extended(
              backgroundColor: cs.primary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text('Resume', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              onPressed: () {
                final chapters = _manga!.chapters!;
                final lastUrl = libraryManga!.lastReadChapterUrl!;
                final idx = chapters.indexWhere((c) => c.url == lastUrl);
                final sp = context.read<SourceProvider>();
                final src = sp.getInstalledSource(widget.sourceId)?.source;
                final isAnime = src?.isAnime ?? false;
                final isNovel = src?.isNovel ?? false;
                final chapterMaps = chapters.map((c) => {'url': c.url, 'name': c.name}).toList();
                if (isNovel) {
                  Navigator.pushNamed(context, AppRoutes.novelReader, arguments: {
                    'chapterUrl': lastUrl,
                    'sourceId': widget.sourceId,
                    'chapterTitle': idx >= 0 ? chapters[idx].name : null,
                    'mangaTitle': title,
                    'chapters': chapterMaps,
                    'currentIndex': idx >= 0 ? idx : 0,
                  });
                } else if (isAnime) {
                  Navigator.pushNamed(context, AppRoutes.player, arguments: {
                    'episodeUrl': lastUrl,
                    'sourceId': widget.sourceId,
                    'episodeTitle': idx >= 0 ? chapters[idx].name : null,
                    'animeTitle': title,
                  });
                } else {
                  Navigator.pushNamed(context, AppRoutes.reader, arguments: {
                    'chapterUrl': lastUrl,
                    'sourceId': widget.sourceId,
                    'mangaUrl': widget.mangaUrl,
                    'chapterTitle': idx >= 0 ? chapters[idx].name : null,
                    'mangaTitle': title,
                    'chapters': chapterMaps,
                    'currentIndex': idx >= 0 ? idx : 0,
                    'startPage': libraryManga.lastReadPage,
                  });
                }
              },
            )
          : null,
    );
  }

  Widget _buildChapterTile(BuildContext context, MChapter chapter,
      LibraryProvider libraryProvider, LibraryManga? libraryManga,
      List<Map<String, dynamic>> allChapters) {
    final cs = Theme.of(context).colorScheme;
    final chapterUrl = chapter.url ?? '';
    final isRead = libraryProvider.isChapterRead(widget.sourceId, chapterUrl);
    final isBookmarked = _bookmarkedChapterUrls.contains(chapterUrl);
    final index = _manga!.chapters!.indexWhere((c) => c.url == chapterUrl);

    // Only show page position on the last-read unread chapter
    final isLastRead = libraryManga?.lastReadChapterUrl == chapterUrl && !isRead;

    // Text colors: read chapters are dimmed
    final titleColor = isRead ? cs.outline.withAlpha(100) : cs.onSurface;
    final subColor = isRead ? cs.outline.withAlpha(80) : cs.outline;

    final isSelected = _selectedChapterUrls.contains(chapterUrl);

    return InkWell(
      onTap: () {
        if (chapterUrl.isEmpty) return;
        if (_selectionMode) { _toggleSelection(chapterUrl); return; }
        final src2 = context
            .read<SourceProvider>()
            .getInstalledSource(widget.sourceId)
            ?.source;
        final isAnime = src2?.isAnime ?? false;
        final isNovel = src2?.isNovel ?? false;
        if (isNovel) {
          Navigator.pushNamed(context, AppRoutes.novelReader, arguments: {
            'chapterUrl': chapterUrl,
            'sourceId': widget.sourceId,
            'chapterTitle': chapter.name,
            'mangaTitle': _manga?.name,
            'chapters': allChapters,
            'currentIndex': index >= 0 ? index : 0,
          });
        } else if (isAnime) {
          Navigator.pushNamed(context, AppRoutes.player, arguments: {
            'episodeUrl': chapterUrl,
            'sourceId': widget.sourceId,
            'episodeTitle': chapter.name,
            'animeTitle': _manga?.name,
          });
        } else {
          Navigator.pushNamed(context, AppRoutes.reader, arguments: {
            'chapterUrl': chapterUrl,
            'sourceId': widget.sourceId,
            'mangaUrl': widget.mangaUrl,
            'chapterTitle': chapter.name,
            'mangaTitle': _manga?.name,
            'chapters': allChapters,
            'currentIndex': index >= 0 ? index : 0,
          });
        }
      },
      onLongPress: () {
        if (chapterUrl.isEmpty) return;
        if (_selectionMode) {
          _toggleSelection(chapterUrl);
        } else {
          _showChapterActions(context, chapter, libraryProvider);
        }
      },
      child: Container(
        color: isSelected ? cs.primary.withAlpha(30) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          // Selection checkbox (only in multi-select mode)
          if (_selectionMode)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: isSelected ? cs.primary : cs.outline.withAlpha(120)),
            ),
          // Bookmark indicator (left edge)
          if (isBookmarked && !_selectionMode)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.bookmark_rounded, size: 16, color: cs.primary),
            ),
          // Chapter info
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              chapter.name ?? 'Chapter',
              style: GoogleFonts.manrope(
                fontSize: 14,
                fontWeight: isLastRead ? FontWeight.w700 : FontWeight.w500,
                color: isLastRead ? cs.primary : titleColor,
              ),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Row(children: [
              if (chapter.dateUpload != null && formatChapterDate(chapter.dateUpload).isNotEmpty)
                Text(formatChapterDate(chapter.dateUpload),
                    style: GoogleFonts.manrope(fontSize: 11, color: subColor)),
              // Page position only for the current reading chapter
              if (isLastRead && libraryManga != null) ...[
                if (chapter.dateUpload != null) Text(' \u2022 ',
                    style: GoogleFonts.manrope(fontSize: 11, color: subColor)),
                Text('Page ${libraryManga.lastReadPage + 1}',
                    style: GoogleFonts.manrope(fontSize: 11, color: cs.primary, fontWeight: FontWeight.w600)),
              ],
            ]),
          ])),
          // Download button (hidden while selecting chapters)
          if (!_selectionMode)
          Builder(builder: (context) {
            final dlProvider = context.watch<DownloadProvider>();
            final dlTask = dlProvider.getTask(widget.sourceId, chapterUrl);
            final isDl = dlProvider.isDownloaded(widget.sourceId, chapterUrl);

            if (dlTask != null && dlTask.status == DownloadStatus.downloading) {
              return SizedBox(
                width: 32, height: 32,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: CircularProgressIndicator(
                    value: dlTask.progress > 0 ? dlTask.progress : null,
                    strokeWidth: 2, color: cs.primary),
                ),
              );
            }
            return IconButton(
              icon: Icon(
                isDl ? Icons.download_done_rounded : Icons.download_outlined,
                size: 20,
                color: isDl ? cs.primary : cs.outline.withAlpha(120)),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: isDl ? 'Delete download' : 'Download',
              onPressed: () {
                final title = _manga?.name ?? widget.title ?? 'Unknown';
                if (isDl) {
                  dlProvider.deleteDownload(
                    widget.sourceId, title, chapter.name ?? 'Chapter', chapterUrl);
                } else {
                  final isAnime = context.read<SourceProvider>()
                      .getInstalledSource(widget.sourceId)?.source.isAnime ?? false;
                  if (isAnime) {
                    dlProvider.enqueueEpisode(
                      sourceId: widget.sourceId,
                      animeUrl: widget.mangaUrl,
                      animeTitle: title,
                      episodeUrl: chapterUrl,
                      episodeName: chapter.name ?? 'Episode',
                    );
                  } else {
                    dlProvider.enqueueChapter(
                      sourceId: widget.sourceId,
                      mangaUrl: widget.mangaUrl,
                      mangaTitle: title,
                      chapterUrl: chapterUrl,
                      chapterName: chapter.name ?? 'Chapter',
                    );
                  }
                }
              },
            );
          }),
        ]),
      ),
    );
  }

  void _handleBulkDownload(String action, BuildContext context, LibraryProvider libraryProvider) {
    final chapters = _manga?.chapters;
    if (chapters == null || chapters.isEmpty) return;

    final dlProvider = context.read<DownloadProvider>();
    final mangaTitle = _manga?.name ?? widget.title ?? 'Unknown';

    List<MChapter> toDownload = [];

    // Find the last read chapter index
    final libraryManga = libraryProvider.manga.cast<LibraryManga?>().firstWhere(
        (m) => m!.sourceId == widget.sourceId && m.url == widget.mangaUrl,
        orElse: () => null);
    final lastReadUrl = libraryManga?.lastReadChapterUrl;
    var startIdx = 0;
    if (lastReadUrl != null) {
      final idx = chapters.indexWhere((c) => c.url == lastReadUrl);
      if (idx >= 0) startIdx = idx;
    }

    switch (action) {
      case 'dl_next_1':
        if (startIdx + 1 < chapters.length) toDownload = [chapters[startIdx + 1]];
        else if (chapters.isNotEmpty) toDownload = [chapters.last];
        break;
      case 'dl_next_5':
        toDownload = chapters.skip(startIdx + 1).take(5).toList();
        break;
      case 'dl_next_10':
        toDownload = chapters.skip(startIdx + 1).take(10).toList();
        break;
      case 'dl_unread':
        toDownload = chapters.where((c) =>
            !libraryProvider.isChapterRead(widget.sourceId, c.url ?? '')).toList();
        break;
      case 'dl_all':
        toDownload = List.from(chapters);
        break;
    }

    // Filter out already downloaded
    toDownload = toDownload.where((c) =>
        !dlProvider.isDownloaded(widget.sourceId, c.url ?? '')).toList();

    if (toDownload.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to download'), duration: Duration(seconds: 1)),
      );
      return;
    }

    final isAnime = context.read<SourceProvider>()
        .getInstalledSource(widget.sourceId)?.source.isAnime ?? false;

    if (isAnime) {
      for (final c in toDownload) {
        dlProvider.enqueueEpisode(
          sourceId: widget.sourceId,
          animeUrl: widget.mangaUrl,
          animeTitle: mangaTitle,
          episodeUrl: c.url ?? '',
          episodeName: c.name ?? 'Episode',
        );
      }
    } else {
      dlProvider.enqueueChapters(toDownload.map((c) => {
        'sourceId': widget.sourceId,
        'mangaUrl': widget.mangaUrl,
        'mangaTitle': mangaTitle,
        'chapterUrl': c.url ?? '',
        'chapterName': c.name ?? 'Chapter',
      }).toList());
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Downloading ${toDownload.length} chapter${toDownload.length == 1 ? '' : 's'}'),
        duration: const Duration(seconds: 2)),
    );
  }

  void _addToLibrary(BuildContext context) {
    final manga = _manga;
    if (manga == null) return;

    final vault = context.read<VaultProvider>();
    final library = context.read<LibraryProvider>();
    final isVault = vault.vaultActive;
    final cats = isVault ? vault.categories : library.categories;

    LibraryManga buildManga({List<String> categories = const []}) {
      return LibraryManga(
        sourceId: widget.sourceId,
        url: widget.mangaUrl,
        title: manga.name ?? widget.title ?? 'Unknown',
        coverUrl: manga.imageUrl ?? widget.coverUrl ?? '',
        author: manga.author,
        description: manga.description,
        genres: manga.genre ?? [],
        status: _statusText(manga.status ?? MangaStatus.unknown),
        totalChapters: manga.chapters?.length ?? 0,
        categories: categories,
      );
    }

    void afterAdd() {
      if (manga.chapters != null && manga.chapters!.isNotEmpty) {
        final chapterMaps = manga.chapters!.map((c) => c.toJson()).toList();
        if (isVault) {
          vault.cacheChapters(widget.sourceId, widget.mangaUrl, chapterMaps);
        } else {
          library.cacheChapters(widget.sourceId, widget.mangaUrl, chapterMaps);
        }
      }
    }

    if (cats.length <= 1) {
      final defaultCats = cats.isNotEmpty ? [cats.first.name] : <String>[];
      if (isVault) {
        vault.addToLibrary(buildManga(categories: defaultCats));
      } else {
        library.addToLibrary(buildManga(categories: defaultCats));
      }
      afterAdd();
    } else {
      _showCategoryPicker(context, cats.map((c) => c.name).toList(), (selected) {
        if (isVault) {
          vault.addToLibrary(buildManga(categories: selected));
        } else {
          library.addToLibrary(buildManga(categories: selected));
        }
        afterAdd();
      });
    }
  }

  void _showCategoryPicker(
      BuildContext context, List<String> categories, ValueChanged<List<String>> onConfirm) {
    final cs = Theme.of(context).colorScheme;
    final selected = <String>{};

    showModalBottomSheet(
      context: context,
      // Grow past the half-screen cap and bound the height so a long category
      // list scrolls while the confirm button stays reachable.
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 36, height: 4,
                    decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Text('Add to Category',
                    style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      ...categories.map((cat) {
                        final isIn = selected.contains(cat);
                        return InkWell(
                          onTap: () => setSheetState(() {
                            isIn ? selected.remove(cat) : selected.add(cat);
                          }),
                          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                            child: Row(children: [
                              Icon(isIn ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                  size: 20, color: isIn ? cs.primary : cs.outline),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(cat, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                              ),
                            ]),
                          ),
                        );
                      }),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: FilledButton(
                  onPressed: () { Navigator.pop(context); onConfirm(selected.toList()); },
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary, foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text(selected.isEmpty ? 'Add without Category' : 'Add to Library',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14)),
                )),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _showMoveCategorySheet(BuildContext context) {
    final vault = context.read<VaultProvider>();
    final library = context.read<LibraryProvider>();
    final isVault = vault.vaultActive;
    final catNames = isVault
        ? vault.categories.map((c) => c.name).toList()
        : library.categories.map((c) => c.name).toList();
    final manga = isVault
        ? vault.manga.cast<LibraryManga?>().firstWhere(
            (m) => m!.sourceId == widget.sourceId && m.url == widget.mangaUrl, orElse: () => null)
        : library.manga.cast<LibraryManga?>().firstWhere(
            (m) => m!.sourceId == widget.sourceId && m.url == widget.mangaUrl, orElse: () => null);
    if (manga == null || catNames.isEmpty) return;

    final cs = Theme.of(context).colorScheme;
    final selected = Set<String>.from(manga.categories);

    showModalBottomSheet(
      context: context,
      // Let the sheet grow past the default half-screen cap, and bound it so a
      // long category list scrolls while the Save button stays pinned.
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 36, height: 4,
                    decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Text('Edit Categories',
                    style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
                const SizedBox(height: 12),
                // Scrolls when there are more categories than fit.
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      ...catNames.map((cat) {
                        final isIn = selected.contains(cat);
                        return InkWell(
                          onTap: () => setSheetState(() { isIn ? selected.remove(cat) : selected.add(cat); }),
                          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                            child: Row(children: [
                              Icon(isIn ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                  size: 20, color: isIn ? cs.primary : cs.outline),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(cat, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                              ),
                            ]),
                          ),
                        );
                      }),
                    ]),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    if (isVault) {
                      vault.setMangaCategories(widget.sourceId, widget.mangaUrl, selected.toList());
                    } else {
                      library.setMangaCategories(widget.sourceId, widget.mangaUrl, selected.toList());
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary, foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: Text('Save', style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 14)),
                )),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  String _statusText(MangaStatus status) => switch (status) {
    MangaStatus.ongoing => 'Ongoing',
    MangaStatus.completed => 'Completed',
    MangaStatus.onHiatus => 'Hiatus',
    MangaStatus.canceled => 'Canceled',
    MangaStatus.publishingFinished => 'Finished',
    MangaStatus.unknown => 'Unknown',
  };
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final ColorScheme cs;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.cs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? cs.surfaceContainerHighest : cs.surfaceContainerHighest.withAlpha(140),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 22, color: active ? cs.primary : cs.onSurface),
            const SizedBox(height: 4),
            Text(label, style: GoogleFonts.manrope(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: active ? cs.primary : cs.onSurface)),
          ]),
        ),
      ),
    );
  }
}
