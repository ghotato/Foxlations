import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/installed_source_model.dart';
import '../../core/providers/source_provider.dart';
import '../../core/providers/vault_provider.dart';
import '../../eval/lib.dart';
import '../../eval/model/m_manga.dart';
import '../../core/utils/search_filter.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../widgets/manga_image.dart';

class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  bool _searching = false;
  Map<String, List<MManga>> _results = {};
  Map<String, bool> _sourceLoading = {};

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) return;
    _focusNode.unfocus();

    final sourceProvider = context.read<SourceProvider>();
    final vaultProvider = context.read<VaultProvider>();
    var sources = sourceProvider.installedSources;

    // Hide vault sources when not in vault mode
    if (!vaultProvider.vaultActive) {
      sources = sources.where((s) => !vaultProvider.isSourceInVault(s.source.id)).toList();
    }

    // NSFW filter (Browse settings)
    if (!sourceProvider.showNsfw) {
      sources = sources.where((s) => !s.source.isNsfw).toList();
    }

    // Pinned-only filter for global search (Browse settings).
    // Reads the same prefs key the Sources tab writes to.
    if (sourceProvider.pinnedOnlyGlobalSearch) {
      final prefs = await SharedPreferences.getInstance();
      final pinned = (prefs.getStringList('pinned_source_ids') ?? []).toSet();
      sources = sources.where((s) => pinned.contains(s.source.id)).toList();
    }

    setState(() {
      _searching = true;
      _results = {};
      _sourceLoading = {for (final s in sources) s.source.id: true};
    });

    // Search all sources in parallel
    for (final source in sources) {
      _searchSource(source, query);
    }
  }

  Future<void> _searchSource(InstalledSource installed, String query) async {
    try {
      final result = await withExtensionService(
        installed.source, installed.sourceCode,
        (service) => service.search(query, 1, []),
      );
      // Drop non-matching results — some sources fall back to a popular listing
      // when their site ignores the query, which would otherwise masquerade as
      // search hits (mismatched title/cover pairs).
      final matched = filterSearchResults(result.list, query);
      if (mounted && matched.isNotEmpty) {
        setState(() {
          _results[installed.source.id] = matched.take(6).toList();
        });
      }
    } catch (e) {
      // Source search failed — skip
    }
    if (mounted) {
      setState(() {
        _sourceLoading[installed.source.id] = false;
        if (_sourceLoading.values.every((v) => !v)) _searching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sourceProvider = context.watch<SourceProvider>();
    final sourceCount = sourceProvider.installedSources.length;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface, elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface, size: 22),
          onPressed: () => Navigator.pop(context)),
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
          child: TextField(
            controller: _searchController,
            focusNode: _focusNode,
            onSubmitted: _search,
            textInputAction: TextInputAction.search,
            textAlignVertical: TextAlignVertical.center,
            style: GoogleFonts.manrope(fontSize: 13, color: cs.onSurface),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search across all sources...',
              hintStyle: GoogleFonts.manrope(fontSize: 13, color: cs.outline),
              prefixIcon: Icon(Icons.travel_explore_rounded, size: 18, color: cs.primary),
              prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (_, val, __) => val.text.isNotEmpty
                    ? GestureDetector(
                        onTap: () { _searchController.clear(); setState(() { _results = {}; _searching = false; }); },
                        child: Icon(Icons.close_rounded, size: 16, color: cs.outline))
                    : const SizedBox.shrink()),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 4))),
        ),
        titleSpacing: 0,
        actions: const [SizedBox(width: 8)],
      ),
      body: _buildBody(cs, sourceCount),
    );
  }

  Widget _buildBody(ColorScheme cs, int sourceCount) {
    if (sourceCount == 0) return _buildEmptyState(cs, 'No sources installed', 'Install extensions from Browse tab.');

    // No search yet
    if (_results.isEmpty && !_searching) {
      return Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 72, height: 72,
            decoration: BoxDecoration(color: cs.primary.withAlpha(20), borderRadius: BorderRadius.circular(20)),
            child: Icon(Icons.travel_explore_rounded, size: 36, color: cs.primary)),
          const SizedBox(height: 20),
          Text('Search All Sources', style: GoogleFonts.manrope(
              fontSize: 17, fontWeight: FontWeight.w800, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text('Search $sourceCount source${sourceCount == 1 ? '' : 's'} at once.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 13, color: cs.outline)),
        ])));
    }

    // Loading
    final sourceProvider = context.read<SourceProvider>();
    final loadingCount = _sourceLoading.values.where((v) => v).length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        if (_searching)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary)),
              const SizedBox(width: 8),
              Text('Searching $loadingCount source${loadingCount == 1 ? '' : 's'}...',
                  style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
            ])),
        // Results grouped by source
        ..._results.entries.map((entry) {
          final sourceName = sourceProvider.installedSources
              .where((s) => s.source.id == entry.key)
              .map((s) => s.source.name)
              .firstOrNull ?? entry.key;
          return Column(
            key: ValueKey('src_${entry.key}'),
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
              child: Row(children: [
                Text(sourceName.toUpperCase(), style: GoogleFonts.manrope(
                    fontSize: 11, fontWeight: FontWeight.w700, color: cs.primary, letterSpacing: 1.0)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, AppRoutes.sourceCatalog, arguments: {
                    'sourceId': entry.key,
                    'sourceName': sourceName,
                    'searchQuery': _searchController.text.trim(),
                  }),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('See all', style: GoogleFonts.manrope(
                        fontSize: 11, fontWeight: FontWeight.w600, color: cs.primary)),
                    Icon(Icons.chevron_right_rounded, size: 16, color: cs.primary),
                  ]),
                ),
              ])),
            SizedBox(height: 190, child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemCount: entry.value.length,
              itemBuilder: (_, i) {
                final manga = entry.value[i];
                return _MangaCard(
                  key: ValueKey('${entry.key}_${manga.link ?? i}'),
                  name: manga.name ?? '',
                  coverUrl: manga.imageUrl ?? '',
                  onTap: () => Navigator.pushNamed(context, AppRoutes.mangaDetail, arguments: {
                    'mangaUrl': manga.link ?? '',
                    'sourceId': entry.key,
                    'title': manga.name,
                    'coverUrl': manga.imageUrl,
                  }),
                );
              },
            )),
          ]);
        }),
        // No results after all sources done
        if (!_searching && _results.isEmpty)
          Padding(padding: const EdgeInsets.all(40),
            child: Center(child: Text('No results found',
                style: GoogleFonts.manrope(fontSize: 14, color: cs.outline)))),
      ],
    );
  }

  Widget _buildEmptyState(ColorScheme cs, String title, String subtitle) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.explore_off_rounded, size: 48, color: cs.outline),
      const SizedBox(height: 12),
      Text(title, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
      const SizedBox(height: 6),
      Text(subtitle, style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
    ]));
  }
}

class _MangaCard extends StatelessWidget {
  final String name;
  final String coverUrl;
  final VoidCallback onTap;

  const _MangaCard({super.key, required this.name, required this.coverUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(width: 100, child: Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          child: SizedBox(width: 100, height: 135,
            child: coverUrl.isNotEmpty
                ? MangaImage(imageUrl: coverUrl, fit: BoxFit.cover)
                : Container(color: cs.surfaceContainerHighest,
                    child: Icon(Icons.image_rounded, color: cs.outline)))),
        const SizedBox(height: 4),
        Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onSurface)),
      ])),
    );
  }
}
