import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/installed_source_model.dart';
import '../../../core/providers/source_provider.dart';
import '../../../core/providers/vault_provider.dart';
import '../../../routes/app_routes.dart';
import '../../../theme/app_theme.dart';
import 'browse_source_detail_sheet.dart';

class SourcesTabWidget extends StatefulWidget {
  final String searchQuery;

  const SourcesTabWidget({super.key, this.searchQuery = ''});

  @override
  State<SourcesTabWidget> createState() => _SourcesTabWidgetState();
}

class _SourcesTabWidgetState extends State<SourcesTabWidget> {
  String _selectedLang = 'all';
  Set<String> _pinnedIds = {};
  static const _pinnedKey = 'pinned_source_ids';

  @override
  void initState() {
    super.initState();
    _loadPinned();
  }

  Future<void> _loadPinned() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _pinnedIds = (prefs.getStringList(_pinnedKey) ?? []).toSet());
  }

  Future<void> _togglePin(String sourceId) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_pinnedIds.contains(sourceId)) {
        _pinnedIds.remove(sourceId);
      } else {
        _pinnedIds.add(sourceId);
      }
    });
    await prefs.setStringList(_pinnedKey, _pinnedIds.toList());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Consumer2<SourceProvider, VaultProvider>(
      builder: (_, provider, vault, __) {
        var installed = provider.installedSources;

        // Hide vault-only sources when not in vault mode
        // In vault mode, show everything (vault + regular sources)
        if (!vault.vaultActive) {
          installed = installed
              .where((s) => !vault.isSourceInVault(s.source.id))
              .toList();
        }

        // Filter by search
        if (widget.searchQuery.isNotEmpty) {
          final q = widget.searchQuery.toLowerCase();
          installed = installed
              .where((s) => s.source.name.toLowerCase().contains(q))
              .toList();
        }

        // Get available languages
        final languages = <String>{'all'};
        for (final s in installed) {
          languages.add(s.source.lang);
        }

        // Filter by language
        if (_selectedLang != 'all') {
          installed = installed
              .where((s) => s.source.lang == _selectedLang)
              .toList();
        }

        // Group by language
        final grouped = <String, List<InstalledSource>>{};
        for (final s in installed) {
          grouped.putIfAbsent(s.source.lang, () => []).add(s);
        }

        return Column(
          children: [
            // Language filter chips
            if (languages.length > 2)
              _buildLanguageChips(cs, languages.toList()),
            if (languages.length > 2)
              Divider(height: 1, color: cs.surfaceContainerHighest),

            // Content
            Expanded(
              child: installed.isEmpty
                  ? _buildEmptyState(cs)
                  : Builder(builder: (_) {
                      final pinned = installed.where((s) => _pinnedIds.contains(s.source.id)).toList();
                      final unpinned = installed.where((s) => !_pinnedIds.contains(s.source.id)).toList();

                      // Group unpinned by language
                      final grouped = <String, List<InstalledSource>>{};
                      for (final s in unpinned) {
                        grouped.putIfAbsent(s.source.lang, () => []).add(s);
                      }

                      return ListView(
                        padding: const EdgeInsets.only(bottom: 100),
                        children: [
                          // Pinned section
                          if (pinned.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                              child: Row(children: [
                                Icon(Icons.push_pin_rounded, size: 14, color: cs.primary),
                                const SizedBox(width: 6),
                                Text('PINNED', style: GoogleFonts.manrope(
                                  fontSize: 11, fontWeight: FontWeight.w700,
                                  color: cs.primary, letterSpacing: 1.2)),
                              ]),
                            ),
                            ...pinned.map((s) => _SourceRow(
                              installedSource: s,
                              isPinned: true,
                              onTap: () => Navigator.pushNamed(context, AppRoutes.sourceCatalog,
                                  arguments: {'sourceId': s.source.id, 'sourceName': s.source.name}),
                              onLongPress: () => _showSourceDetail(context, s),
                              onPinToggle: () => _togglePin(s.source.id),
                            )),
                            Divider(height: 1, color: cs.surfaceContainerHighest),
                          ],
                          // Unpinned grouped by language
                          ...grouped.entries.expand((e) => [
                            _LanguageHeader(lang: e.key),
                            ...e.value.map((s) => _SourceRow(
                              installedSource: s,
                              isPinned: false,
                              onTap: () => Navigator.pushNamed(context, AppRoutes.sourceCatalog,
                                  arguments: {'sourceId': s.source.id, 'sourceName': s.source.name}),
                              onLongPress: () => _showSourceDetail(context, s),
                              onPinToggle: () => _togglePin(s.source.id),
                            )),
                          ]),
                        ],
                      );
                    }),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLanguageChips(ColorScheme cs, List<String> languages) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: languages.length,
        itemBuilder: (_, i) {
          final lang = languages[i];
          final isSelected = _selectedLang == lang;
          return GestureDetector(
            onTap: () => setState(() => _selectedLang = lang),
            child: AnimatedContainer(
              duration: AppTheme.fastMicro,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected
                    ? cs.primary.withAlpha(38)
                    : cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                border: Border.all(
                  color: isSelected ? cs.primary : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Text(
                lang == 'all' ? 'All' : _langDisplayName(lang),
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? cs.primary : cs.outline,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: cs.primary.withAlpha(31),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Icon(Icons.explore_off_rounded, size: 32, color: cs.primary),
          ),
          const SizedBox(height: 16),
          Text(
            'No installed sources',
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Install extensions from the Extensions tab\nto see sources here.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 12,
              color: cs.outline,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  void _showSourceDetail(BuildContext context, InstalledSource source) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BrowseSourceDetailSheet(
        source: source.source,
        isInstalled: true,
      ),
    );
  }

  String _langDisplayName(String code) {
    const map = {
      'en': 'English',
      'ja': 'Japanese',
      'ko': 'Korean',
      'zh': 'Chinese',
      'fr': 'French',
      'es': 'Spanish',
      'de': 'German',
      'pt': 'Portuguese',
      'id': 'Indonesian',
      'tr': 'Turkish',
      'th': 'Thai',
      'ru': 'Russian',
    };
    return map[code] ?? code.toUpperCase();
  }
}

class _LanguageHeader extends StatelessWidget {
  final String lang;
  const _LanguageHeader({required this.lang});

  static const _langEmoji = {
    'en': '🇬🇧', 'ja': '🇯🇵', 'ko': '🇰🇷', 'zh': '🇨🇳',
    'fr': '🇫🇷', 'es': '🇪🇸', 'de': '🇩🇪', 'pt': '🇧🇷',
    'id': '🇮🇩', 'tr': '🇹🇷', 'th': '🇹🇭', 'ru': '🇷🇺',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final emoji = _langEmoji[lang] ?? '🌐';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        '$emoji  ${lang.toUpperCase()}',
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

class _SourceRow extends StatelessWidget {
  final InstalledSource installedSource;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onPinToggle;
  final bool isPinned;

  const _SourceRow({
    required this.installedSource,
    required this.onTap,
    this.onLongPress,
    this.onPinToggle,
    this.isPinned = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final source = installedSource.source;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: cs.primary.withAlpha(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Source icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Center(
                  child: Text(
                    source.name.isNotEmpty
                        ? source.name[0].toUpperCase()
                        : '?',
                    style: GoogleFonts.manrope(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Source info
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
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _LangBadge(lang: source.lang, isNsfw: source.isNsfw),
                        const SizedBox(width: 8),
                        Text(
                          source.framework,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            color: cs.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Pin button
              if (onPinToggle != null)
                IconButton(
                  icon: Icon(
                    isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    size: 18,
                    color: isPinned ? cs.primary : cs.outline.withAlpha(120),
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: isPinned ? 'Unpin' : 'Pin',
                  onPressed: onPinToggle,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LangBadge extends StatelessWidget {
  final String lang;
  final bool isNsfw;
  const _LangBadge({required this.lang, this.isNsfw = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: isNsfw
            ? AppTheme.error.withAlpha(30)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(3),
        border: isNsfw
            ? Border.all(color: AppTheme.error.withAlpha(80))
            : null,
      ),
      child: Text(
        lang.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isNsfw ? AppTheme.error : cs.outline,
        ),
      ),
    );
  }
}
