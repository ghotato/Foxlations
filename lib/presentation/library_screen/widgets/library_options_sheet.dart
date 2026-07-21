import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/library_settings.dart';
import '../../../theme/app_theme.dart';

/// Bottom sheet with the library's Filter / Sort / Display controls.
///
/// Edits are pushed up live through [onChanged] so the grid behind the sheet
/// reflects each change immediately, rather than only on dismiss.
class LibraryOptionsSheet extends StatefulWidget {
  final LibrarySettings settings;
  final List<({String id, String name})> sources;
  final ValueChanged<LibrarySettings> onChanged;

  const LibraryOptionsSheet({
    super.key,
    required this.settings,
    required this.sources,
    required this.onChanged,
  });

  static Future<void> show(
    BuildContext context, {
    required LibrarySettings settings,
    required List<({String id, String name})> sources,
    required ValueChanged<LibrarySettings> onChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => LibraryOptionsSheet(
        settings: settings,
        sources: sources,
        onChanged: onChanged,
      ),
    );
  }

  @override
  State<LibraryOptionsSheet> createState() => _LibraryOptionsSheetState();
}

class _LibraryOptionsSheetState extends State<LibraryOptionsSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late LibrarySettings _s;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _s = widget.settings;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _update(LibrarySettings next) {
    setState(() => _s = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusLarge)),
      ),
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.72),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          TabBar(
            controller: _tabs,
            labelColor: cs.primary,
            unselectedLabelColor: cs.outline,
            indicatorColor: cs.primary,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: GoogleFonts.manrope(
                fontSize: 13.5, fontWeight: FontWeight.w700),
            unselectedLabelStyle: GoogleFonts.manrope(
                fontSize: 13.5, fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Filter'),
              Tab(text: 'Sort'),
              Tab(text: 'Display'),
            ],
          ),
          const Divider(height: 1),
          Flexible(
            child: TabBarView(
              controller: _tabs,
              children: [
                _filterTab(cs),
                _sortTab(cs),
                _displayTab(cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter ────────────────────────────────────────────────────────────────
  Widget _filterTab(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _check(cs, 'Unread', _s.filterUnread,
            (v) => _update(_s.copyWith(filterUnread: v))),
        _check(cs, 'Completed', _s.filterCompleted,
            (v) => _update(_s.copyWith(filterCompleted: v))),
        _check(cs, 'Downloaded', _s.filterDownloaded,
            (v) => _update(_s.copyWith(filterDownloaded: v))),
        if (widget.sources.isNotEmpty) ...[
          const Divider(height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Sources',
                style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.primary)),
          ),
          for (final src in widget.sources)
            _check(cs, src.name, _s.filterSourceIds.contains(src.id), (v) {
              final next = Set<String>.from(_s.filterSourceIds);
              v ? next.add(src.id) : next.remove(src.id);
              _update(_s.copyWith(filterSourceIds: next));
            }),
        ],
      ],
    );
  }

  Widget _check(
      ColorScheme cs, String label, bool value, ValueChanged<bool> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: cs.primary,
                side: BorderSide(color: cs.primary, width: 1.6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.manrope(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sort ──────────────────────────────────────────────────────────────────
  Widget _sortTab(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final option in LibrarySort.values)
          InkWell(
            onTap: () {
              // Re-tapping the active sort flips direction, like Mihon.
              if (_s.sort == option) {
                _update(_s.copyWith(sortAscending: !_s.sortAscending));
              } else {
                _update(_s.copyWith(sort: option, sortAscending: true));
              }
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: _s.sort == option
                        ? Icon(
                            _s.sortAscending
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 18,
                            color: cs.primary)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Text(option.label,
                      style: GoogleFonts.manrope(
                        fontSize: 14.5,
                        fontWeight:
                            _s.sort == option ? FontWeight.w700 : FontWeight.w600,
                        color:
                            _s.sort == option ? cs.primary : cs.onSurface,
                      )),
                ],
              ),
            ),
          ),
        const Divider(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () async {
                await LibrarySettings.resetToDefaults();
                _update(const LibrarySettings());
              },
              child: Text('Reset to default',
                  style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.outline)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Display ───────────────────────────────────────────────────────────────
  Widget _displayTab(ColorScheme cs) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _sectionLabel(cs, 'Display Mode'),
        for (final mode in LibraryDisplayMode.values)
          InkWell(
            onTap: () => _update(_s.copyWith(displayMode: mode)),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    _s.displayMode == mode
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: _s.displayMode == mode ? cs.primary : cs.outline,
                  ),
                  const SizedBox(width: 16),
                  Text(mode.label,
                      style: GoogleFonts.manrope(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                ],
              ),
            ),
          ),
        if (_s.displayMode == LibraryDisplayMode.grid)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text('Items per row',
                      style: GoogleFonts.manrope(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                ),
                _stepper(cs, Icons.remove_rounded,
                    _s.itemsPerRow > 2
                        ? () => _update(
                            _s.copyWith(itemsPerRow: _s.itemsPerRow - 1))
                        : null),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('${_s.itemsPerRow}',
                      style: GoogleFonts.manrope(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                ),
                _stepper(cs, Icons.add_rounded,
                    _s.itemsPerRow < 6
                        ? () => _update(
                            _s.copyWith(itemsPerRow: _s.itemsPerRow + 1))
                        : null),
              ],
            ),
          ),
        const Divider(height: 20),
        _sectionLabel(cs, 'Badges'),
        _check(cs, 'Unread', _s.badgeUnread,
            (v) => _update(_s.copyWith(badgeUnread: v))),
        _check(cs, 'Downloaded', _s.badgeDownloaded,
            (v) => _update(_s.copyWith(badgeDownloaded: v))),
        const Divider(height: 20),
        _sectionLabel(cs, 'Tabs'),
        _check(cs, 'Show number of items', _s.showTabCounts,
            (v) => _update(_s.copyWith(showTabCounts: v))),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _sectionLabel(ColorScheme cs, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
        child: Text(text,
            style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.primary)),
      );

  Widget _stepper(ColorScheme cs, IconData icon, VoidCallback? onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: onTap == null
              ? cs.surfaceContainerHighest
              : cs.primary.withAlpha(38),
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            size: 18, color: onTap == null ? cs.outline : cs.primary),
      ),
    );
  }
}
