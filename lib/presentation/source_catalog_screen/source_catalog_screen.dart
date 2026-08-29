import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/manga_image.dart';
import '../../core/providers/source_provider.dart';
import '../../core/providers/catalog_provider.dart';
import '../../eval/model/m_manga.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';

class SourceCatalogScreen extends StatelessWidget {
  final String sourceId;
  final String sourceName;
  final String? initialSearchQuery;

  const SourceCatalogScreen({
    super.key,
    required this.sourceId,
    required this.sourceName,
    this.initialSearchQuery,
  });

  @override
  Widget build(BuildContext context) {
    final sourceProvider = context.read<SourceProvider>();
    final installed = sourceProvider.getInstalledSource(sourceId);

    if (installed == null) {
      return Scaffold(
        appBar: AppBar(title: Text(sourceName)),
        body: const Center(child: Text('Source not installed')),
      );
    }

    return ChangeNotifierProvider(
      create: (_) {
        final provider = CatalogProvider(installed);
        if (initialSearchQuery != null && initialSearchQuery!.isNotEmpty) {
          provider.search(initialSearchQuery!);
        } else {
          provider.loadMore();
        }
        return provider;
      },
      child: _CatalogBody(
        sourceId: sourceId,
        sourceName: sourceName,
        hasCloudflare: installed.source.hasCloudflare,
        initialSearchQuery: initialSearchQuery,
      ),
    );
  }
}

class _CatalogBody extends StatefulWidget {
  final String sourceId;
  final String sourceName;
  final bool hasCloudflare;
  final String? initialSearchQuery;

  const _CatalogBody({required this.sourceId, required this.sourceName, this.hasCloudflare = false, this.initialSearchQuery});

  @override
  State<_CatalogBody> createState() => _CatalogBodyState();
}

class _CatalogBodyState extends State<_CatalogBody> {
  @override
  void initState() {
    super.initState();
    if (widget.hasCloudflare) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        AppTheme.showSnackBar(context, 'Bypassing Cloudflare protection...',
            duration: const Duration(seconds: 3));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<CatalogProvider>(
      builder: (_, catalog, __) {
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.sourceName),
            actions: [
              IconButton(
                icon: const Icon(Icons.open_in_browser),
                tooltip: 'Open in WebView',
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.webview,
                    arguments: {
                      'url': catalog.source.baseUrl,
                      'title': widget.sourceName,
                    },
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => _showSearch(context, catalog),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Row(
                children: [
                  // Tabs adapt to the source: video sources get a "Categories"
                  // tab in place of "Latest"; manga sources keep "Latest" when
                  // supported. The Categories tab relabels to the drilled-in
                  // category name.
                  for (final tab in CatalogTab.values.where((t) {
                    if (t == CatalogTab.search) return false;
                    if (t == CatalogTab.categories) return catalog.showCategoriesTab;
                    if (t == CatalogTab.latest) {
                      return !catalog.showCategoriesTab && catalog.supportsLatest;
                    }
                    return true; // popular
                  }))
                    Expanded(
                      child: InkWell(
                        onTap: () => catalog.setTab(tab),
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: catalog.currentTab == tab
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text(
                            tab == CatalogTab.categories &&
                                    catalog.selectedCategory != null
                                ? catalog.selectedCategory!['name']!
                                : tab.name[0].toUpperCase() + tab.name.substring(1),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: catalog.currentTab == tab
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          body: _buildContent(context, catalog),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, CatalogProvider catalog) {
    // Categories tab, not yet drilled into a category: show the category list.
    if (catalog.currentTab == CatalogTab.categories &&
        catalog.selectedCategory == null) {
      return _buildCategoryList(context, catalog);
    }
    if (catalog.error != null && catalog.currentManga.isEmpty) {
      final is403 = catalog.error!.contains('403');
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              is403 ? Icons.shield_outlined : Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              is403 ? 'Cloudflare Protection' : 'Failed to load',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                is403
                    ? 'This source requires solving a Cloudflare challenge in the browser first.'
                    : catalog.error!,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            if (is403)
              FilledButton.icon(
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Open in WebView'),
                onPressed: () async {
                  final result = await Navigator.pushNamed(
                    context,
                    AppRoutes.webview,
                    arguments: {
                      'url': catalog.source.baseUrl,
                      'title': 'Solve Cloudflare',
                      'cloudflareMode': true,
                    },
                  );
                  if (result == true) catalog.refresh();
                },
              ),
            if (is403) const SizedBox(height: 8),
            FilledButton(
              onPressed: () => catalog.refresh(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (catalog.currentManga.isEmpty && catalog.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (catalog.currentManga.isEmpty) {
      // Match the wording to the source's content type — an anime or novel
      // source shouldn't say "no manga".
      final noun = switch (catalog.source.itemType) {
        'anime' => 'anime',
        'novel' => 'light novels',
        _ => 'manga',
      };
      return Center(child: Text('No $noun found'));
    }

    final grid = RefreshIndicator(
      onRefresh: () => catalog.refresh(),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification &&
              notification.metrics.extentAfter < 300) {
            catalog.loadMore();
          }
          return false;
        },
        child: GridView.builder(
          padding: EdgeInsets.fromLTRB(
              12, 12, 12, 12 + MediaQuery.of(context).viewPadding.bottom),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _getColumnCount(context),
            childAspectRatio: 0.65,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: catalog.currentManga.length + (catalog.isLoading ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= catalog.currentManga.length) {
              return const Center(child: CircularProgressIndicator());
            }
            return _MangaCard(
              manga: catalog.currentManga[i],
              sourceId: widget.sourceId,
              referer: catalog.source.baseUrl,
            );
          },
        ),
      ),
    );

    // Inside a drilled-in category: prepend a back bar to return to the list.
    if (catalog.currentTab == CatalogTab.categories &&
        catalog.selectedCategory != null) {
      return Column(children: [
        _categoryBackBar(context, catalog),
        Expanded(child: grid),
      ]);
    }
    return grid;
  }

  Widget _categoryBackBar(BuildContext context, CatalogProvider catalog) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      child: InkWell(
        onTap: catalog.clearCategory,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Icon(Icons.arrow_back_rounded, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            Text('All categories',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: cs.primary)),
            const Spacer(),
            Text(catalog.selectedCategory?['name'] ?? '',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: cs.outline)),
          ]),
        ),
      ),
    );
  }

  Widget _buildCategoryList(BuildContext context, CatalogProvider catalog) {
    final cs = Theme.of(context).colorScheme;
    if (catalog.categoriesLoading && catalog.categories.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (catalog.categories.isEmpty) {
      return Center(
        child: Text('No categories',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.outline)),
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          12, 12, 12, 12 + MediaQuery.of(context).viewPadding.bottom),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final cat in catalog.categories)
            ActionChip(
              label: Text(cat['name'] ?? ''),
              onPressed: () => catalog.selectCategory(cat),
              backgroundColor: cs.surfaceContainerHighest,
              side: BorderSide(color: cs.outlineVariant),
            ),
        ],
      ),
    );
  }

  int _getColumnCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 840) return 5;
    if (width >= 600) return 4;
    return 3;
  }

  void _showSearch(BuildContext context, CatalogProvider catalog) {
    showDialog(
      context: context,
      builder: (_) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Search'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Search manga...'),
            onSubmitted: (query) {
              Navigator.pop(context);
              catalog.search(query);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                catalog.search(controller.text);
              },
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
  }
}

class _MangaCard extends StatelessWidget {
  final MManga manga;
  final String sourceId;
  final String referer;

  const _MangaCard({required this.manga, required this.sourceId, required this.referer});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        if (manga.link == null) return;
        Navigator.pushNamed(
          context,
          AppRoutes.mangaDetail,
          arguments: {
            'mangaUrl': manga.link!,
            'sourceId': sourceId,
            'title': manga.name,
            'coverUrl': manga.imageUrl,
          },
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  child: MangaImage(imageUrl: manga.imageUrl ?? '', referer: referer),
                ),
                if (manga.link?.contains('#adult') == true)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(180),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.lock_rounded, size: 14, color: Colors.white70),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            manga.name ?? 'Unknown',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
