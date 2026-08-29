import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../theme/app_theme.dart';

/// What the user chose to do with a migration target.
enum MigrationAction {
  /// Open the target's entry so its chapter count can be checked first.
  showEntry,

  /// Add the target alongside the original, leaving the original in place.
  copy,

  /// Replace the original with the target.
  migrate,
}

/// Which parts of the original entry carry over.
class MigrationOptions {
  final bool chapters;
  final bool categories;
  final bool tracking;
  final bool removeDownloads;

  const MigrationOptions({
    this.chapters = true,
    this.categories = true,
    this.tracking = true,
    this.removeDownloads = true,
  });

  MigrationOptions copyWith({
    bool? chapters,
    bool? categories,
    bool? tracking,
    bool? removeDownloads,
  }) =>
      MigrationOptions(
        chapters: chapters ?? this.chapters,
        categories: categories ?? this.categories,
        tracking: tracking ?? this.tracking,
        removeDownloads: removeDownloads ?? this.removeDownloads,
      );
}

class MigrationChoice {
  final MigrationAction action;
  final MigrationOptions options;
  const MigrationChoice(this.action, this.options);
}

/// Asks what to carry across before replacing an entry, and offers to open the
/// candidate first.
///
/// "Show entry" exists because the search result only shows a cover and a
/// title — not whether the other source actually has the whole series. Opening
/// it first turns migration from a guess into a check.
///
/// "Tracking" re-binds the original entry's per-manga tracker records (MAL /
/// AniList / Kitsu) to the new entry, so a migrated series keeps syncing.
Future<MigrationChoice?> showMigrationOptions(
  BuildContext context, {
  required String targetSourceName,
  required String targetTitle,
  /// Bulk migration can't preview a single entry, so the button is hidden.
  bool allowShowEntry = true,
  int entryCount = 1,
}) {
  return showDialog<MigrationChoice>(
    context: context,
    builder: (ctx) {
      var opts = const MigrationOptions();
      final cs = Theme.of(ctx).colorScheme;

      return StatefulBuilder(
        builder: (ctx, setState) {
          Widget check(String label, bool value, ValueChanged<bool> onChanged) {
            return InkWell(
              onTap: () => setState(() => onChanged(!value)),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Checkbox(
                    value: value,
                    activeColor: cs.primary,
                    onChanged: (v) => setState(() => onChanged(v ?? false)),
                  ),
                  const SizedBox(width: 4),
                  Text(label,
                      style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                ]),
              ),
            );
          }

          return AlertDialog(
            backgroundColor: cs.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
            title: Text('Select data to include',
                style: GoogleFonts.manrope(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    entryCount > 1
                        ? '$entryCount entries → $targetSourceName'
                        : '$targetTitle → $targetSourceName',
                    style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                const SizedBox(height: 6),
                Text('Downloaded chapters do not transfer.',
                    style: GoogleFonts.manrope(
                        fontSize: 12.5, color: cs.outline, height: 1.4)),
                const SizedBox(height: 12),
                check('Chapters', opts.chapters,
                    (v) => opts = opts.copyWith(chapters: v)),
                check('Categories', opts.categories,
                    (v) => opts = opts.copyWith(categories: v)),
                check('Tracking', opts.tracking,
                    (v) => opts = opts.copyWith(tracking: v)),
                check('Remove downloads if migrate', opts.removeDownloads,
                    (v) => opts = opts.copyWith(removeDownloads: v)),
              ],
            ),
            actionsPadding:
                const EdgeInsets.only(left: 12, right: 12, bottom: 10),
            actions: [
              if (allowShowEntry)
                TextButton(
                  onPressed: () => Navigator.pop(
                      ctx, MigrationChoice(MigrationAction.showEntry, opts)),
                  child: Text('Show entry',
                      style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w600, color: cs.primary)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(
                    ctx, MigrationChoice(MigrationAction.copy, opts)),
                child: Text('Copy',
                    style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w600, color: cs.primary)),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                    ctx, MigrationChoice(MigrationAction.migrate, opts)),
                style: FilledButton.styleFrom(backgroundColor: cs.primary),
                child: Text('Migrate',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      );
    },
  );
}
