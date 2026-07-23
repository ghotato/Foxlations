import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/models/manga_model.dart';
import '../../core/models/installed_source_model.dart';
import '../../core/utils/search_filter.dart';
import '../../core/providers/source_provider.dart';
import '../../core/providers/library_provider.dart';
import '../../core/providers/tracking_provider.dart';
import '../../core/providers/vault_provider.dart';
import '../../core/services/download_service.dart';
import '../../eval/lib.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../widgets/manga_image.dart';
import 'widgets/migration_options_dialog.dart';

/// Migration screen — search all sources for the same manga and transfer read progress.
class MigrateScreen extends StatefulWidget {
  final String sourceId;
  final String mangaUrl;
  final String mangaTitle;

  /// Position in a bulk-migrate queue, shown in the app bar so it's clear how
  /// many entries are left. Null for a one-off migration.
  final int? queuePosition;
  final int? queueTotal;

  /// Title and source of the NEXT entry in a bulk-migrate queue. When set, this
  /// screen searches for it in the background while the user picks the current
  /// target, so the next screen opens with results already loaded. The source
  /// is needed so the prefetch excludes the right entry's own source.
  final String? nextQuery;
  final String? nextSourceId;

  const MigrateScreen({
    super.key,
    required this.sourceId,
    required this.mangaUrl,
    required this.mangaTitle,
    this.queuePosition,
    this.queueTotal,
    this.nextQuery,
    this.nextSourceId,
  });

  @override
  State<MigrateScreen> createState() => _MigrateScreenState();

  /// Drop any prefetched search results. Called at the start of a new bulk
  /// migration so a fresh queue never shows stale hits from a previous run.
  static void resetSearchCache() => _MigrateScreenState._searchCache.clear();
}

class _MigrateScreenState extends State<MigrateScreen> {
  final _searchController = TextEditingController();
  bool _searching = false;
  // Set while a chosen target is being migrated (fetching the new source's
  // chapters + copying read state) — the work runs on the UI isolate, so
  // without this the screen just sits frozen and reads as a hang.
  bool _migrating = false;
  // sourceId -> list of results
  Map<String, List<_SearchResult>> _results = {};

  // Cross-screen cache so a bulk migration doesn't re-run the same all-sources
  // search when the next entry opens — the previous screen prefetches into it.
  static final Map<String, Map<String, List<_SearchResult>>> _searchCache = {};
  static String _norm(String q) => q.trim().toLowerCase();

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.mangaTitle;
    _search(useCache: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search({bool useCache = false}) async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    // Prefetched by the previous entry in the queue — show instantly.
    if (useCache) {
      final cached = _searchCache[_norm(query)];
      if (cached != null && cached.isNotEmpty) {
        setState(() { _results = cached; _searching = false; });
        _prefetchNext();
        return;
      }
    }

    setState(() { _searching = true; _results = {}; });

    final gathered = await _runSearch(query, excludeSourceId: widget.sourceId,
        into: (id, list) {
      if (!mounted) return;
      setState(() => _results[id] = list);
    });

    _searchCache[_norm(query)] = gathered;
    if (mounted) setState(() => _searching = false);
    _prefetchNext();
  }

  /// Warm the cache for the next queue entry while the user reviews this one,
  /// so the next screen doesn't spin. Skipped if already cached.
  void _prefetchNext() {
    final next = widget.nextQuery?.trim();
    if (next == null || next.isEmpty) return;
    if (_searchCache.containsKey(_norm(next))) return;
    // Reserve the key so a second prefetch doesn't duplicate the work.
    _searchCache[_norm(next)] = {};
    _runSearch(next, excludeSourceId: widget.nextSourceId ?? widget.sourceId)
        .then((res) => _searchCache[_norm(next)] = res);
  }

  /// Runs the all-sources search for [query], excluding [excludeSourceId] (the
  /// entry's own source can't be a migration target). [into] (optional)
  /// receives each source's results as they arrive for live display. Returns
  /// the full map.
  Future<Map<String, List<_SearchResult>>> _runSearch(
    String query, {
    required String excludeSourceId,
    void Function(String sourceId, List<_SearchResult> results)? into,
  }) async {
    final sourceProvider = context.read<SourceProvider>();
    final vaultProvider = context.read<VaultProvider>();
    final sources = sourceProvider.installedSources
        .where((s) => s.source.id != excludeSourceId) // exclude entry's source
        .where((s) => !vaultProvider.isSourceInVault(s.source.id)) // hide vault sources
        .toList();

    final out = <String, List<_SearchResult>>{};
    await Future.wait(sources.map((source) async {
      final list = await _searchSource(source, query);
      if (list.isNotEmpty) {
        out[source.source.id] = list;
        into?.call(source.source.id, list);
      }
    }));
    return out;
  }

  Future<List<_SearchResult>> _searchSource(
      InstalledSource installed, String query) async {
    try {
      final result = await withExtensionService(
        installed.source, installed.sourceCode,
        (service) => service.search(query, 1, []),
        // One slow/hanging source shouldn't stall the whole batch.
      ).timeout(const Duration(seconds: 15));
      final matched = filterSearchResults(result.list, query);
      return matched.take(5).map((m) =>
        _SearchResult(
          name: m.name ?? query,
          url: m.link ?? '',
          coverUrl: m.imageUrl ?? '',
          sourceId: installed.source.id,
          sourceName: installed.source.name,
        ),
      ).toList();
    } catch (e) {
      // Source search failed or timed out — skip silently.
      return const [];
    }
  }

  Future<void> _migrate(_SearchResult target) async {
    final choice = await showMigrationOptions(
      context,
      targetSourceName: target.sourceName,
      targetTitle: target.name,
    );
    if (choice == null || !mounted) return;

    // "Show entry" is a look, not a decision — open the candidate so its
    // chapter list can be checked, then come back to the results.
    if (choice.action == MigrationAction.showEntry) {
      await Navigator.pushNamed(context, AppRoutes.mangaDetail, arguments: {
        'mangaUrl': target.url,
        'sourceId': target.sourceId,
        'title': target.name,
        'coverUrl': target.coverUrl,
      });
      return;
    }

    final opts = choice.options;
    final isCopy = choice.action == MigrationAction.copy;

    // Show a blocking progress overlay while the (UI-isolate) migration runs.
    setState(() => _migrating = true);

    // Perform migration
    final libraryProvider = context.read<LibraryProvider>();
    final vaultProvider = context.read<VaultProvider>();
    final isVault = vaultProvider.vaultActive;
    final provider = isVault ? vaultProvider : libraryProvider;

    // Get old manga data
    final oldManga = (provider as dynamic).manga.cast<LibraryManga?>().firstWhere(
        (m) => m!.sourceId == widget.sourceId && m.url == widget.mangaUrl,
        orElse: () => null) as LibraryManga?;

    if (oldManga == null) {
      if (mounted) {
        setState(() => _migrating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manga not found in library')));
      }
      return;
    }

    // Read progress is matched by chapter NUMBER, since the two sources won't
    // share chapter URLs. Skipped entirely when "Chapters" is unticked.
    final readChapterNumbers = <String, bool>{};
    if (opts.chapters) {
      final oldCachedChapters = (provider as dynamic)
          .getCachedChapters(widget.sourceId, widget.mangaUrl) as List;
      for (final ch in oldCachedChapters) {
        if (libraryProvider.isChapterRead(widget.sourceId, ch.chapterUrl)) {
          final num = _extractChapterNumber(ch.title);
          if (num != null) readChapterNumbers[num] = true;
        }
      }
    }

    // Copy leaves the original in place; migrate replaces it.
    if (!isCopy) {
      if (opts.removeDownloads) {
        try {
          await DownloadService().deleteManga(widget.sourceId, oldManga.title,
              isVault: isVault);
        } catch (_) {
          // Downloads may not exist — never block the migration on cleanup.
        }
      }
      await (provider as dynamic)
          .removeFromLibrary(widget.sourceId, widget.mangaUrl);
    }

    final newManga = LibraryManga(
      sourceId: target.sourceId,
      url: target.url,
      title: target.name,
      coverUrl: target.coverUrl,
      author: oldManga.author,
      description: oldManga.description,
      genres: oldManga.genres,
      status: oldManga.status,
      categories: opts.categories ? oldManga.categories : const <String>[],
      lastReadAt: opts.chapters ? oldManga.lastReadAt : null,
      readChapters: opts.chapters ? oldManga.readChapters : 0,
    );
    await (provider as dynamic).addToLibrary(newManga);

    // Fetch new chapters and match read state
    if (!mounted) return;
    try {
      final sourceProvider = context.read<SourceProvider>();
      final installed = sourceProvider.getInstalledSource(target.sourceId);
      if (installed != null) {
        final detail = await withExtensionService(
          installed.source, installed.sourceCode,
          (service) => service.getDetail(target.url),
        );
        if (detail.chapters != null) {
          // Cache new chapters
          await (provider as dynamic).cacheChapters(target.sourceId, target.url,
              detail.chapters!.map((c) => c.toJson()).toList());

          // Mark matching chapters as read
          for (final ch in detail.chapters!) {
            final num = _extractChapterNumber(ch.name ?? '');
            if (num != null && readChapterNumbers.containsKey(num)) {
              await libraryProvider.markChapterRead(target.sourceId, target.url, ch.url ?? '');
            }
          }
        }
      }
    } catch (e) {
      // Chapter matching failed — manga is still migrated, just without read state
    }

    // Carry tracker bindings (MAL / AniList / Kitsu) across to the new entry so
    // it keeps auto-syncing. On a copy the original stays, so leave its
    // bindings; on a migrate the original is gone, so move them.
    if (opts.tracking && mounted) {
      try {
        await context.read<TrackingProvider>().copyBindings(
              fromSourceId: widget.sourceId,
              fromUrl: widget.mangaUrl,
              toSourceId: target.sourceId,
              toUrl: target.url,
              removeOld: !isCopy,
            );
      } catch (_) {
        // Tracking carry-over is best-effort — never block the migration on it.
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isCopy
              ? 'Copied to ${target.sourceName}'
              : 'Migrated to ${target.sourceName}'),
          duration: const Duration(seconds: 2)));
      Navigator.pop(context); // pop this MigrateScreen
      // A single migration is launched on top of the manga's detail screen, and
      // a migrate (not copy) leaves that detail screen pointing at a now-removed
      // entry — so pop it too. In a bulk run MigrateScreen sits directly on the
      // library (the queue re-pushes the next one), so that extra pop would tear
      // the library off the stack and black-screen the app.
      final isBulk = widget.queueTotal != null;
      if (!isCopy && !isBulk) Navigator.pop(context);
    }
  }

  /// Extract chapter number from a chapter name.
  String? _extractChapterNumber(String name) {
    // Match decimal (Ch 1.5) or integer (Chapter 123)
    final decimal = RegExp(r'(\d+\.\d+)').firstMatch(name);
    if (decimal != null) return decimal.group(1);
    final integer = RegExp(r'(\d+)').firstMatch(name);
    return integer?.group(1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: cs.onSurface, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Migrate',
                style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
            // Bulk migration walks entries one at a time; without this there's
            // no way to tell how far through the queue you are.
            if (widget.queueTotal != null && widget.queueTotal! > 1)
              Text('${widget.queuePosition} of ${widget.queueTotal}',
                  style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.outline)),
          ],
        ),
      ),
      body: Stack(children: [
        Column(children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            controller: _searchController,
            style: GoogleFonts.manrope(fontSize: 14, color: cs.onSurface),
            decoration: InputDecoration(
              hintText: 'Search manga title...',
              hintStyle: GoogleFonts.manrope(fontSize: 14, color: cs.outline),
              prefixIcon: Icon(Icons.search_rounded, size: 20, color: cs.outline),
              suffixIcon: IconButton(
                icon: Icon(Icons.send_rounded, size: 18, color: cs.primary),
                onPressed: _search,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              filled: true, fillColor: cs.surfaceContainerHighest,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onSubmitted: (_) => _search(),
          ),
        ),

        // Info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Icon(Icons.info_outline_rounded, size: 14, color: cs.outline),
            const SizedBox(width: 6),
            Expanded(child: Text(
              'Select the same manga from a different source. Read progress will be transferred.',
              style: GoogleFonts.manrope(fontSize: 11, color: cs.outline),
            )),
          ]),
        ),
        const SizedBox(height: 8),

        // Thin progress line while sources are still being searched — the
        // results below fill in as each source returns, so there's no blank
        // full-screen wait.
        if (_searching)
          LinearProgressIndicator(
              minHeight: 2,
              color: cs.primary,
              backgroundColor: cs.surfaceContainerHighest),

        // Results
        Expanded(
            child: _results.isEmpty
                ? Center(child: Text(
                    _searching ? 'Searching sources…' : 'No results found',
                    style: GoogleFonts.manrope(fontSize: 14, color: cs.outline)))
                : ListView(
                    padding: const EdgeInsets.only(bottom: 32),
                    children: _results.entries.map((e) {
                      final sourceName = context.read<SourceProvider>()
                          .installedSources
                          .where((s) => s.source.id == e.key)
                          .map((s) => s.source.name)
                          .firstOrNull ?? e.key;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                            child: Text(sourceName.toUpperCase(),
                                style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700,
                                    color: cs.primary, letterSpacing: 1.0)),
                          ),
                          SizedBox(
                            height: 160,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              separatorBuilder: (_, __) => const SizedBox(width: 10),
                              itemCount: e.value.length,
                              itemBuilder: (_, i) => _MigrationCard(
                                result: e.value[i],
                                onTap: () => _migrate(e.value[i]),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
          ),
        ]),
        if (_migrating)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Migrating…',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _SearchResult {
  final String name;
  final String url;
  final String coverUrl;
  final String sourceId;
  final String sourceName;

  _SearchResult({
    required this.name,
    required this.url,
    required this.coverUrl,
    required this.sourceId,
    required this.sourceName,
  });
}

class _MigrationCard extends StatelessWidget {
  final _SearchResult result;
  final VoidCallback onTap;

  const _MigrationCard({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 100,
        child: Column(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            child: SizedBox(
              width: 100, height: 130,
              child: result.coverUrl.isNotEmpty
                  ? MangaImage(imageUrl: result.coverUrl, fit: BoxFit.cover)
                  : Container(color: cs.surfaceContainerHighest,
                      child: Icon(Icons.image_rounded, color: cs.outline)),
            ),
          ),
          const SizedBox(height: 4),
          Text(result.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ]),
      ),
    );
  }
}
