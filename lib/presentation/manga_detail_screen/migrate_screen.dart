import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/models/manga_model.dart';
import '../../core/models/installed_source_model.dart';
import '../../core/utils/search_filter.dart';
import '../../core/providers/source_provider.dart';
import '../../core/providers/library_provider.dart';
import '../../core/providers/vault_provider.dart';
import '../../eval/lib.dart';
import '../../theme/app_theme.dart';
import '../widgets/manga_image.dart';

/// Migration screen — search all sources for the same manga and transfer read progress.
class MigrateScreen extends StatefulWidget {
  final String sourceId;
  final String mangaUrl;
  final String mangaTitle;

  const MigrateScreen({
    super.key,
    required this.sourceId,
    required this.mangaUrl,
    required this.mangaTitle,
  });

  @override
  State<MigrateScreen> createState() => _MigrateScreenState();
}

class _MigrateScreenState extends State<MigrateScreen> {
  final _searchController = TextEditingController();
  bool _searching = false;
  // sourceId -> list of results
  Map<String, List<_SearchResult>> _results = {};

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.mangaTitle;
    _search();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() { _searching = true; _results = {}; });

    final sourceProvider = context.read<SourceProvider>();
    final vaultProvider = context.read<VaultProvider>();
    final sources = sourceProvider.installedSources
        .where((s) => s.source.id != widget.sourceId) // exclude current source
        .where((s) => !vaultProvider.isSourceInVault(s.source.id)) // hide vault sources
        .toList();

    // Search each source in parallel
    final futures = <Future>[];
    for (final source in sources) {
      futures.add(_searchSource(source, query));
    }
    await Future.wait(futures);

    if (mounted) setState(() => _searching = false);
  }

  Future<void> _searchSource(InstalledSource installed, String query) async {
    try {
      final result = await withExtensionService(
        installed.source, installed.sourceCode,
        (service) => service.search(query, 1, []),
      );
      final matched = filterSearchResults(result.list, query);
      if (matched.isNotEmpty && mounted) {
        setState(() {
          _results[installed.source.id] = matched.take(5).map((m) =>
            _SearchResult(
              name: m.name ?? query,
              url: m.link ?? '',
              coverUrl: m.imageUrl ?? '',
              sourceId: installed.source.id,
              sourceName: installed.source.name,
            ),
          ).toList();
        });
      }
    } catch (e) {
      // Source search failed — skip silently
    }
  }

  Future<void> _migrate(_SearchResult target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
          title: Text('Migrate to ${target.sourceName}?',
              style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(target.name, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 8),
            Text('This will:\n• Update the source to ${target.sourceName}\n• Transfer read progress by chapter number\n• Keep categories and bookmarks',
                style: GoogleFonts.manrope(fontSize: 13, color: cs.outline, height: 1.5)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: Text('Cancel', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, color: cs.outline))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: cs.primary),
                child: Text('Migrate', style: GoogleFonts.manrope(fontWeight: FontWeight.w700))),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manga not found in library')));
      }
      return;
    }

    // Get old chapter read states
    final oldCachedChapters = (provider as dynamic).getCachedChapters(widget.sourceId, widget.mangaUrl) as List;
    final readChapterNumbers = <String, bool>{};
    for (final ch in oldCachedChapters) {
      if (libraryProvider.isChapterRead(widget.sourceId, ch.chapterUrl)) {
        final num = _extractChapterNumber(ch.title);
        if (num != null) readChapterNumbers[num] = true;
      }
    }

    // Remove old entry
    await (provider as dynamic).removeFromLibrary(widget.sourceId, widget.mangaUrl);

    // Add new entry
    final newManga = LibraryManga(
      sourceId: target.sourceId,
      url: target.url,
      title: target.name,
      coverUrl: target.coverUrl,
      author: oldManga.author,
      description: oldManga.description,
      genres: oldManga.genres,
      status: oldManga.status,
      categories: oldManga.categories,
      lastReadAt: oldManga.lastReadAt,
      readChapters: oldManga.readChapters,
    );
    await (provider as dynamic).addToLibrary(newManga);

    // Fetch new chapters and match read state
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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Migrated to ${target.sourceName}'), duration: const Duration(seconds: 2)));
      Navigator.pop(context); // back to detail
      Navigator.pop(context); // back to library (old detail is stale)
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
        title: Text('Migrate', style: GoogleFonts.manrope(
            fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
      ),
      body: Column(children: [
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

        // Results
        if (_searching)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: _results.isEmpty
                ? Center(child: Text('No results found',
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
