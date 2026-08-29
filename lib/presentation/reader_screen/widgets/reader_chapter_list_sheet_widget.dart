import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class ReaderChapterListSheetWidget extends StatelessWidget {
  final List<Map<String, dynamic>> chapters;
  final int currentIndex;
  final ValueChanged<int> onChapterSelected;

  const ReaderChapterListSheetWidget({
    super.key,
    required this.chapters,
    required this.currentIndex,
    required this.onChapterSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusLarge),
          ),
        ),
        child: Column(
          children: [
            // Handle + header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.outline.withAlpha(128),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Chapters',
                        style: GoogleFonts.manrope(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius:
                              BorderRadius.circular(AppTheme.radiusFull),
                        ),
                        child: Text(
                          '${chapters.length}',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(color: cs.outlineVariant, height: 1),
                ],
              ),
            ),
            // Chapter list
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 32),
                itemCount: chapters.length,
                itemBuilder: (_, index) {
                  final chapter = chapters[index];
                  final isCurrent = index == currentIndex;
                  return _ChapterListItem(
                    chapter: chapter,
                    index: index,
                    isCurrent: isCurrent,
                    onTap: () => onChapterSelected(index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChapterListItem extends StatelessWidget {
  final Map<String, dynamic> chapter;
  final int index;
  final bool isCurrent;
  final VoidCallback onTap;

  const _ChapterListItem({
    required this.chapter,
    required this.index,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = chapter['name'] as String? ?? 'Chapter ${index + 1}';
    final isRead = chapter['isRead'] as bool? ?? false;

    return Material(
      color: isCurrent ? cs.primary.withAlpha(26) : Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Chapter number circle
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? cs.primary.withAlpha(38)
                      : cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isCurrent ? cs.primary : cs.outline,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Title + metadata
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight:
                            isCurrent ? FontWeight.w700 : FontWeight.w500,
                        color: isRead ? cs.outline : cs.onSurface,
                      ),
                    ),
                    if (chapter['scanlator'] != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        chapter['scanlator'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          color: cs.outline,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Status icons
              if (isRead)
                Icon(Icons.check_circle_rounded,
                    size: 16, color: AppTheme.success),
              if (isCurrent)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.play_arrow_rounded,
                      size: 18, color: cs.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
