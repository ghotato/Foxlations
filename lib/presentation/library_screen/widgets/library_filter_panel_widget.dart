import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import '../library_screen.dart';

// ── Filter State ─────────────────────────────────────────────
enum LibrarySortField { lastUpdated, title, unreadCount, rating }

enum LibrarySortDirection { ascending, descending }

enum LibraryCoverSize { small, medium, large }

class LibraryFilterState {
  final MangaReadingStatus statusFilter;
  final LibrarySortField sortField;
  final LibrarySortDirection sortDirection;
  final LibraryCoverSize coverSize;
  final bool isGridView;

  const LibraryFilterState({
    this.statusFilter = MangaReadingStatus.all,
    this.sortField = LibrarySortField.lastUpdated,
    this.sortDirection = LibrarySortDirection.descending,
    this.coverSize = LibraryCoverSize.medium,
    this.isGridView = true,
  });

  LibraryFilterState copyWith({
    MangaReadingStatus? statusFilter,
    LibrarySortField? sortField,
    LibrarySortDirection? sortDirection,
    LibraryCoverSize? coverSize,
    bool? isGridView,
  }) {
    return LibraryFilterState(
      statusFilter: statusFilter ?? this.statusFilter,
      sortField: sortField ?? this.sortField,
      sortDirection: sortDirection ?? this.sortDirection,
      coverSize: coverSize ?? this.coverSize,
      isGridView: isGridView ?? this.isGridView,
    );
  }

  bool get hasActiveFilters =>
      statusFilter != MangaReadingStatus.all ||
      sortField != LibrarySortField.lastUpdated ||
      sortDirection != LibrarySortDirection.descending;
}

// ── Filter Panel Widget ──────────────────────────────────────
class LibraryFilterPanelWidget extends StatefulWidget {
  final LibraryFilterState initialState;
  final ValueChanged<LibraryFilterState> onApply;

  const LibraryFilterPanelWidget({
    super.key,
    required this.initialState,
    required this.onApply,
  });

  @override
  State<LibraryFilterPanelWidget> createState() =>
      _LibraryFilterPanelWidgetState();
}

class _LibraryFilterPanelWidgetState extends State<LibraryFilterPanelWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late LibraryFilterState _state;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _state = widget.initialState;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _apply() {
    widget.onApply(_state);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLarge),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          // Handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Tab bar
          TabBar(
            controller: _tabController,
            labelColor: cs.primary,
            unselectedLabelColor: cs.outline,
            indicatorColor: cs.primary,
            indicatorWeight: 2.5,
            labelStyle: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: GoogleFonts.manrope(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: const [
              Tab(text: 'Filter'),
              Tab(text: 'Sort'),
              Tab(text: 'Display'),
            ],
          ),
          SizedBox(
            height: 280,
            child: TabBarView(
              controller: _tabController,
              children: [
                _FilterTab(
                  selected: _state.statusFilter,
                  onChanged: (s) => setState(
                    () => _state = _state.copyWith(statusFilter: s),
                  ),
                ),
                _SortTab(
                  field: _state.sortField,
                  direction: _state.sortDirection,
                  onFieldChanged: (f) => setState(
                    () => _state = _state.copyWith(sortField: f),
                  ),
                  onDirectionChanged: (d) => setState(
                    () => _state = _state.copyWith(sortDirection: d),
                  ),
                ),
                _DisplayTab(
                  coverSize: _state.coverSize,
                  onCoverSizeChanged: (s) => setState(
                    () => _state = _state.copyWith(coverSize: s),
                  ),
                ),
              ],
            ),
          ),
          // Apply button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _apply,
                style: FilledButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusFull),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  'Apply',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter Tab ───────────────────────────────────────────────
class _FilterTab extends StatelessWidget {
  final MangaReadingStatus selected;
  final ValueChanged<MangaReadingStatus> onChanged;

  const _FilterTab({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = [
      (MangaReadingStatus.all, 'All', Icons.list_rounded),
      (MangaReadingStatus.reading, 'Reading', Icons.auto_stories_rounded),
      (MangaReadingStatus.completed, 'Completed', Icons.done_all_rounded),
      (MangaReadingStatus.onHold, 'On Hold', Icons.pause_circle_rounded),
      (MangaReadingStatus.dropped, 'Dropped', Icons.cancel_rounded),
      (MangaReadingStatus.planToRead, 'Plan to Read', Icons.bookmark_add_rounded),
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: options.map((o) {
        final (status, label, icon) = o;
        final isSelected = selected == status;
        return _OptionTile(
          icon: icon,
          label: label,
          isSelected: isSelected,
          onTap: () => onChanged(status),
        );
      }).toList(),
    );
  }
}

// ── Sort Tab ─────────────────────────────────────────────────
class _SortTab extends StatelessWidget {
  final LibrarySortField field;
  final LibrarySortDirection direction;
  final ValueChanged<LibrarySortField> onFieldChanged;
  final ValueChanged<LibrarySortDirection> onDirectionChanged;

  const _SortTab({
    required this.field,
    required this.direction,
    required this.onFieldChanged,
    required this.onDirectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fields = [
      (LibrarySortField.lastUpdated, 'Last Updated', Icons.update_rounded),
      (LibrarySortField.title, 'Title', Icons.sort_by_alpha_rounded),
      (LibrarySortField.unreadCount, 'Unread Count', Icons.notifications_none_rounded),
      (LibrarySortField.rating, 'Rating', Icons.star_border_rounded),
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        // Direction toggle
        Row(
          children: [
            Expanded(
              child: _DirectionButton(
                label: 'Ascending',
                icon: Icons.arrow_upward_rounded,
                isSelected: direction == LibrarySortDirection.ascending,
                onTap: () =>
                    onDirectionChanged(LibrarySortDirection.ascending),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DirectionButton(
                label: 'Descending',
                icon: Icons.arrow_downward_rounded,
                isSelected: direction == LibrarySortDirection.descending,
                onTap: () =>
                    onDirectionChanged(LibrarySortDirection.descending),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...fields.map((f) {
          final (sortField, label, icon) = f;
          return _OptionTile(
            icon: icon,
            label: label,
            isSelected: field == sortField,
            onTap: () => onFieldChanged(sortField),
          );
        }),
      ],
    );
  }
}

// ── Display Tab ──────────────────────────────────────────────
class _DisplayTab extends StatelessWidget {
  final LibraryCoverSize coverSize;
  final ValueChanged<LibraryCoverSize> onCoverSizeChanged;

  const _DisplayTab({
    required this.coverSize,
    required this.onCoverSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        Text(
          'Cover Size',
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _CoverSizeButton(
              label: 'Small',
              icon: Icons.grid_view_rounded,
              isSelected: coverSize == LibraryCoverSize.small,
              onTap: () => onCoverSizeChanged(LibraryCoverSize.small),
            ),
            const SizedBox(width: 8),
            _CoverSizeButton(
              label: 'Medium',
              icon: Icons.view_module_rounded,
              isSelected: coverSize == LibraryCoverSize.medium,
              onTap: () => onCoverSizeChanged(LibraryCoverSize.medium),
            ),
            const SizedBox(width: 8),
            _CoverSizeButton(
              label: 'Large',
              icon: Icons.view_agenda_rounded,
              isSelected: coverSize == LibraryCoverSize.large,
              onTap: () => onCoverSizeChanged(LibraryCoverSize.large),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Shared Tiles ─────────────────────────────────────────────
class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: AnimatedContainer(
        duration: AppTheme.fastMicro,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color:
              isSelected ? cs.primary.withAlpha(26) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 20, color: isSelected ? cs.primary : cs.outline),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? cs.onSurface
                      : cs.onSurface.withAlpha(180),
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_rounded, size: 18, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

class _DirectionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _DirectionButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppTheme.fastMicro,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withAlpha(26)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: isSelected ? cs.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16, color: isSelected ? cs.primary : cs.outline),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? cs.primary : cs.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverSizeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _CoverSizeButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppTheme.fastMicro,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? cs.primary.withAlpha(26)
                : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(
              color: isSelected ? cs.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 22, color: isSelected ? cs.primary : cs.outline),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? cs.primary : cs.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
