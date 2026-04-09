import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class ReaderHudWidget extends StatelessWidget {
  final Animation<double> animation;
  final String? mangaTitle;
  final String? chapterTitle;
  final int currentPage;
  final int totalPages;
  final VoidCallback onBack;
  final VoidCallback onSettings;
  final VoidCallback onChapterList;
  final ValueChanged<int> onPageChanged;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final bool hasPreviousChapter;
  final bool hasNextChapter;

  const ReaderHudWidget({
    super.key,
    required this.animation,
    this.mangaTitle,
    this.chapterTitle,
    required this.currentPage,
    required this.totalPages,
    required this.onBack,
    required this.onSettings,
    required this.onChapterList,
    required this.onPageChanged,
    this.onPreviousChapter,
    this.onNextChapter,
    this.hasPreviousChapter = false,
    this.hasNextChapter = false,
  });

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: Column(
        children: [
          _TopBar(
            mangaTitle: mangaTitle,
            chapterTitle: chapterTitle,
            onBack: onBack,
            onSettings: onSettings,
            onChapterList: onChapterList,
          ),
          const Spacer(),
          _BottomBar(
            currentPage: currentPage,
            totalPages: totalPages,
            onPageChanged: onPageChanged,
            onPreviousChapter: onPreviousChapter,
            onNextChapter: onNextChapter,
            hasPreviousChapter: hasPreviousChapter,
            hasNextChapter: hasNextChapter,
          ),
        ],
      ),
    );
  }
}

// ── Top Bar ──────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String? mangaTitle;
  final String? chapterTitle;
  final VoidCallback onBack;
  final VoidCallback onSettings;
  final VoidCallback onChapterList;

  const _TopBar({
    this.mangaTitle,
    this.chapterTitle,
    required this.onBack,
    required this.onSettings,
    required this.onChapterList,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: Colors.white, size: 22),
                onPressed: onBack,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (mangaTitle != null)
                      Text(
                        mangaTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          shadows: const [
                            Shadow(color: Colors.black, blurRadius: 4),
                          ],
                        ),
                      ),
                    if (chapterTitle != null)
                      Text(
                        chapterTitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ),
              _HudButton(
                icon: Icons.list_rounded,
                tooltip: 'Chapters',
                onTap: onChapterList,
              ),
              _HudButton(
                icon: Icons.settings_rounded,
                tooltip: 'Settings',
                onTap: onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom Bar ───────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final bool hasPreviousChapter;
  final bool hasNextChapter;

  const _BottomBar({
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    this.onPreviousChapter,
    this.onNextChapter,
    required this.hasPreviousChapter,
    required this.hasNextChapter,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Page slider
              if (totalPages > 1) ...[
                Row(
                  children: [
                    Text(
                      '${currentPage + 1}',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: cs.primary,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: cs.primary,
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                        ),
                        child: Slider(
                          value: currentPage.toDouble(),
                          min: 0,
                          max: (totalPages - 1).toDouble(),
                          divisions:
                              totalPages > 1 ? totalPages - 1 : null,
                          onChanged: (v) => onPageChanged(v.round()),
                        ),
                      ),
                    ),
                    Text(
                      '$totalPages',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
              // Chapter navigation
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _HudButton(
                    icon: Icons.skip_previous_rounded,
                    tooltip: 'Previous chapter',
                    onTap: hasPreviousChapter
                        ? onPreviousChapter
                        : null,
                  ),
                  Text(
                    'Page ${currentPage + 1} of $totalPages',
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  _HudButton(
                    icon: Icons.skip_next_rounded,
                    tooltip: 'Next chapter',
                    onTap: hasNextChapter ? onNextChapter : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── HUD Button ───────────────────────────────────────────────
class _HudButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _HudButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onTap == null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isDisabled ? Colors.white38 : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
