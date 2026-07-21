import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
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

  String _safeOrigin(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return '';
    try { return uri.origin; } catch (_) { return ''; }
  }

  @override
  void initState() {
    super.initState();
    _loadDetail();
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
                  const PopupMenuItem(value: 'webview', child: Text('Open in browser')),
                  const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                  if (inLibrary) ...[
                    const PopupMenuDivider(),
                    const PopupMenuItem(value: 'edit_category', child: Text('Edit categories')),
                    const PopupMenuItem(value: 'migrate', child: Text('Migrate')),
                  ],
                ],
                onSelected: (v) {
                  if (v == 'webview') {
                    Navigator.pushNamed(context, AppRoutes.webview,
                        arguments: {'url': widget.mangaUrl, 'title': title});
                  } else if (v == 'refresh') {
                    _loadDetail(forceRefresh: true);
                  } else if (v == 'edit_category') {
                    _showMoveCategorySheet(context);
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
      floatingActionButton: libraryManga?.lastReadChapterUrl != null && _manga?.chapters != null
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

    return InkWell(
      onTap: () {
        if (chapterUrl.isEmpty) return;
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
        setState(() {
          if (isBookmarked) {
            _bookmarkedChapterUrls.remove(chapterUrl);
          } else {
            _bookmarkedChapterUrls.add(chapterUrl);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isBookmarked ? 'Bookmark removed' : 'Bookmarked'),
          duration: const Duration(seconds: 1),
        ));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          // Bookmark indicator (left edge)
          if (isBookmarked)
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
          // Download button
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
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Add to Category',
                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 12),
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
                    Text(cat, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  ]),
                ),
              );
            }),
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
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Edit Categories',
                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 12),
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
                    Text(cat, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  ]),
                ),
              );
            }),
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
