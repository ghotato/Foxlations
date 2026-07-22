import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/models/source_model.dart';
import '../../../core/providers/source_provider.dart';
import '../../../core/providers/vault_provider.dart';
import '../../../theme/app_theme.dart';
import 'browse_source_detail_sheet.dart';
import 'source_settings_page.dart';

class ExtensionsTabWidget extends StatefulWidget {
  final String searchQuery;

  const ExtensionsTabWidget({super.key, this.searchQuery = ''});

  @override
  State<ExtensionsTabWidget> createState() => _ExtensionsTabWidgetState();
}

class _ExtensionsTabWidgetState extends State<ExtensionsTabWidget> {
  String _selectedLang = 'all';
  String _typeFilter = 'manga';
  bool _showFilters = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Consumer2<SourceProvider, VaultProvider>(
      builder: (_, provider, vault, __) {
        var allSources = provider.allSources;

        // Filter by type (manga / anime)
        allSources = allSources
            .where((s) => s.itemType == _typeFilter)
            .toList();

        // Hide vault-only sources when not in vault mode
        if (!vault.vaultActive) {
          allSources = allSources
              .where((s) => !vault.isSourceInVault(s.id))
              .toList();
        }

        // Hide NSFW sources unless the user opted in (Browse settings).
        if (!provider.showNsfw) {
          allSources = allSources.where((s) => !s.isNsfw).toList();
        }

        // Search filter
        if (widget.searchQuery.isNotEmpty) {
          final q = widget.searchQuery.toLowerCase();
          allSources = allSources
              .where((s) => s.name.toLowerCase().contains(q))
              .toList();
        }

        // Get languages
        final languages = <String>{'all'};
        for (final s in allSources) {
          languages.add(s.lang);
        }

        // Language filter
        if (_selectedLang != 'all') {
          allSources =
              allSources.where((s) => s.lang == _selectedLang).toList();
        }

        // Split into installed / available
        final installed = <MangaSource>[];
        final available = <MangaSource>[];
        final repoIds = <String>{};
        for (final s in allSources) {
          repoIds.add(s.id);
          if (provider.isInstalled(s.id)) {
            installed.add(s);
          } else {
            available.add(s);
          }
        }
        // Add orphaned installed sources (no longer in any repo)
        final q = widget.searchQuery.toLowerCase();
        for (final s in provider.installedSources) {
          if (!repoIds.contains(s.source.id)) {
            if (!vault.vaultActive && vault.isSourceInVault(s.source.id)) continue;
            if (s.source.itemType != _typeFilter) continue;
            if (q.isEmpty || s.source.name.toLowerCase().contains(q)) {
              installed.add(s.source);
            }
          }
        }

        return Column(
          children: [
            // Manga / Anime type toggle
            _buildTypeToggle(cs),
            // Filter bar
            if (languages.length > 2) _buildFilterBar(cs, languages.toList(), allSources.length),
            if (languages.length > 2)
              Divider(height: 1, color: cs.surfaceContainerHighest),

            // Content
            Expanded(
              child: RefreshIndicator(
                onRefresh: _handleRefresh,
                child: allSources.isEmpty && !provider.isLoading
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.6,
                            child: _buildEmptyState(cs),
                          ),
                        ],
                      )
                    : provider.isLoading && allSources.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(
                                height: 300,
                                child: Center(
                                    child: CircularProgressIndicator()),
                              ),
                            ],
                          )
                        : ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(bottom: 100),
                            children: [
                              if (installed.isNotEmpty) ...[
                                _SectionHeader(
                                    title: 'INSTALLED',
                                    count: installed.length),
                                ...installed.map((s) => _ExtensionRow(
                                      source: s,
                                      isInstalled: true,
                                      onInstall: () =>
                                          provider.uninstallSource(s.id),
                                      onSettings: () =>
                                          _openSourceSettings(context, s),
                                      onTap: () =>
                                          _showDetail(context, s, true),
                                    )),
                              ],
                              if (available.isNotEmpty) ...[
                                _SectionHeader(
                                    title: 'AVAILABLE',
                                    count: available.length),
                                ...available.map((s) => _ExtensionRow(
                                      source: s,
                                      isInstalled: false,
                                      onInstall: () =>
                                          provider.installSource(s),
                                      onTap: () =>
                                          _showDetail(context, s, false),
                                    )),
                              ],
                            ],
                          ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Opens the source's own preferences. Needs the installed record because the
  /// preference list comes from running the extension's getSourcePreferences().
  void _openSourceSettings(BuildContext context, MangaSource source) {
    final installed =
        context.read<SourceProvider>().getInstalledSource(source.id);
    if (installed == null) {
      AppTheme.showSnackBar(context, 'Source is not installed');
      return;
    }
    SourceSettingsPage.open(
      context,
      source: installed.source,
      sourceCode: installed.sourceCode,
    );
  }

  Widget _buildTypeToggle(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.surfaceContainerHighest)),
      ),
      child: Row(
        children: [
          for (final type in ['manga', 'anime', 'novel'])
            GestureDetector(
              onTap: () => setState(() {
                _typeFilter = type;
                _selectedLang = 'all';
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _typeFilter == type ? cs.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  type == 'manga'
                      ? 'Manga'
                      : type == 'anime'
                          ? 'Anime'
                          : 'Novels',
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: _typeFilter == type ? FontWeight.w700 : FontWeight.w500,
                    color: _typeFilter == type ? cs.primary : cs.outline,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ColorScheme cs, List<String> languages, int resultCount) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFilterBarRow(cs, resultCount),
        // The toggle used to flip `_showFilters` without anything reading it,
        // so the button highlighted and nothing else happened. It now reveals
        // the language picker — the filter `_selectedLang` already backed but
        // which had no way to be set (only an "active chip" to clear it).
        if (_showFilters) _buildLanguagePanel(cs, languages),
      ],
    );
  }

  Widget _buildLanguagePanel(ColorScheme cs, List<String> languages) {
    final ordered = [
      'all',
      ...languages.where((l) => l != 'all').toList()..sort(),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final lang in ordered)
            GestureDetector(
              onTap: () => setState(() => _selectedLang = lang),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _selectedLang == lang
                      ? cs.primary
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                ),
                child: Text(
                  lang == 'all' ? 'All languages' : lang.toUpperCase(),
                  style: GoogleFonts.manrope(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _selectedLang == lang ? Colors.white : cs.onSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterBarRow(ColorScheme cs, int resultCount) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Filter toggle button
          GestureDetector(
            onTap: () => setState(() => _showFilters = !_showFilters),
            child: AnimatedContainer(
              duration: AppTheme.fastMicro,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _showFilters ? cs.primary : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.filter_list_rounded,
                    size: 14,
                    color: _showFilters ? Colors.white : cs.onSurface,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Filter',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _showFilters ? Colors.white : cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Active filter chips
          if (_selectedLang != 'all') ...[
            const SizedBox(width: 8),
            _ActiveFilterChip(
              label: _selectedLang.toUpperCase(),
              onRemove: () => setState(() => _selectedLang = 'all'),
            ),
          ],
          const Spacer(),
          // Results count
          Text(
            '$resultCount result${resultCount == 1 ? '' : 's'}',
            style: GoogleFonts.manrope(fontSize: 11, color: cs.outline),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension_rounded, size: 56, color: cs.outline),
          const SizedBox(height: 16),
          Text(
            'No extensions yet',
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add a repository using the settings\nbutton above to browse extensions.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(fontSize: 13, color: cs.outline),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRefresh() async {
    final provider = context.read<SourceProvider>();
    // Refresh repo indexes to pick up metadata changes, then re-download
    // cached extension code for all installed sources.
    await provider.refreshRepos();
    try {
      final count = await provider.refreshAllSourceCode();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated $count source${count == 1 ? '' : 's'}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Refresh failed: $e')),
      );
    }
  }

  void _showDetail(BuildContext context, MangaSource source, bool installed) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => BrowseSourceDetailSheet(
        source: source,
        isInstalled: installed,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;
  const _SectionHeader({required this.title, required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        '$title ($count)',
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: cs.outline,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ExtensionRow extends StatelessWidget {
  final MangaSource source;
  final bool isInstalled;
  final VoidCallback onInstall;
  final VoidCallback? onSettings;
  final VoidCallback? onTap;

  const _ExtensionRow({
    required this.source,
    required this.isInstalled,
    required this.onInstall,
    this.onSettings,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: cs.primary.withAlpha(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Extension icon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withAlpha(51),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    source.name.isNotEmpty
                        ? source.name[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.manrope(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Extension info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Language badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: cs.outline.withAlpha(51), width: 1),
                      ),
                      child: Text(
                        source.lang.toUpperCase(),
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: cs.outline,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Repo name & version
                    Row(
                      children: [
                        Icon(Icons.extension_rounded,
                            size: 12, color: cs.outline),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            source.repoName.isNotEmpty ? source.repoName : source.framework,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.manrope(
                                fontSize: 11, color: cs.outline),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.tag_rounded,
                            size: 12, color: cs.outline),
                        const SizedBox(width: 4),
                        Text(
                          'v${source.version}',
                          style: GoogleFonts.manrope(
                              fontSize: 11, color: cs.outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Not installed → Install. Installed → Settings, which opens the
              // source's own preferences (Remove lives in there).
              _InstallButton(
                isInstalled: isInstalled,
                onPressed: isInstalled ? (onSettings ?? onInstall) : onInstall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstallButton extends StatelessWidget {
  final bool isInstalled;
  final VoidCallback onPressed;

  const _InstallButton({
    required this.isInstalled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 80,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withAlpha(26),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withAlpha(isInstalled ? 102 : 128),
          ),
        ),
        child: Text(
          isInstalled ? 'Settings' : 'Install',
          style: GoogleFonts.manrope(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _ActiveFilterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: cs.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
        border: Border.all(color: cs.primary.withAlpha(77)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 14, color: cs.primary),
          ),
        ],
      ),
    );
  }
}
