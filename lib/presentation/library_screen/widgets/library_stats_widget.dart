import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/models/manga_model.dart';
import '../../widgets/manga_image.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/providers/vault_provider.dart';
import '../../../core/providers/source_provider.dart';
import '../../../core/providers/library_type_provider.dart';
import '../../../core/utils/url_utils.dart';
import '../../../theme/app_theme.dart';

class LibraryStatsWidget extends StatefulWidget {
  const LibraryStatsWidget({super.key});

  @override
  State<LibraryStatsWidget> createState() => _LibraryStatsWidgetState();
}

class _LibraryStatsWidgetState extends State<LibraryStatsWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVault = context.watch<VaultProvider>().vaultActive;
    // Scope every stat to the Library's current content type (Manga / Anime /
    // Light Novels) so the numbers match what the user is looking at.
    final type = context.watch<LibraryTypeProvider>().type;
    final sp = context.read<SourceProvider>();

    List<LibraryManga> ofType(List<LibraryManga> all) => all.where((m) {
          final t = sp.getInstalledSource(m.sourceId)?.source.itemType ?? 'manga';
          return t == type;
        }).toList();

    if (isVault) {
      return Consumer<VaultProvider>(
        builder: (_, vault, __) {
          final manga = ofType(vault.manga);
          return _StatsContent(
            manga: manga,
            // Reading streak / heatmap count only this type's chapters. Taking
            // the ids from the already-filtered list keeps orphaned-source
            // entries under Manga, matching the library view.
            sourceIds: manga.map((m) => m.sourceId).toSet(),
            contentType: type,
            fadeAnim: _fadeAnim,
            isVault: true,
          );
        },
      );
    }

    return Consumer<LibraryProvider>(
      builder: (_, library, __) {
        final manga = ofType(library.manga);
        return _StatsContent(
          manga: manga,
          sourceIds: manga.map((m) => m.sourceId).toSet(),
          contentType: type,
          fadeAnim: _fadeAnim,
          isVault: false,
        );
      },
    );
  }
}

class _StatsContent extends StatelessWidget {
  final List<LibraryManga> manga;
  final Set<String> sourceIds;
  final String contentType;
  final Animation<double> fadeAnim;
  final bool isVault;

  const _StatsContent({
    required this.manga,
    required this.sourceIds,
    required this.contentType,
    required this.fadeAnim,
    required this.isVault,
  });

  @override
  Widget build(BuildContext context) {
    if (manga.isEmpty) {
      return _EmptyStatsView(isVault: isVault, contentType: contentType);
    }

    final totalChapters = manga.fold(0, (sum, m) => sum + m.totalChapters);
    final readChapters = manga.fold(0, (sum, m) => sum + m.readChapters);

    // Status breakdown
    final statusCounts = <String, int>{};
    for (final m in manga) {
      final s = m.status.isEmpty ? 'Unknown' : m.status;
      statusCounts[s] = (statusCounts[s] ?? 0) + 1;
    }

    // Most-read series (by chapters read)
    final sorted = List<LibraryManga>.from(manga)
      ..sort((a, b) => b.readChapters.compareTo(a.readChapters));
    final topSeries = sorted.take(3).toList();

    // Pull real reading-history stats from the active provider so the
    // streak and heatmap reflect actual reads instead of hardcoded zeros.
    final int currentStreak;
    final int longestStreak;
    final Map<DateTime, int> activity;
    if (isVault) {
      final vault = context.read<VaultProvider>();
      currentStreak = vault.getCurrentReadingStreak(sourceIds: sourceIds);
      longestStreak = vault.getLongestReadingStreak(sourceIds: sourceIds);
      activity = vault.getReadActivityByDay(days: 35, sourceIds: sourceIds);
    } else {
      final library = context.read<LibraryProvider>();
      currentStreak = library.getCurrentReadingStreak(sourceIds: sourceIds);
      longestStreak = library.getLongestReadingStreak(sourceIds: sourceIds);
      activity = library.getReadActivityByDay(days: 35, sourceIds: sourceIds);
    }

    final cs = Theme.of(context).colorScheme;

    return FadeTransition(
      opacity: fadeAnim,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          if (isVault)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(Icons.shield_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 6),
                  Text('Vault Stats',
                      style: GoogleFonts.manrope(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: cs.primary)),
                ],
              ),
            ),
          _TopStatsRow(
            totalManga: manga.length,
            readChapters: readChapters,
            totalChapters: totalChapters,
          ),
          const SizedBox(height: 16),
          _StreakCard(
            currentStreak: currentStreak,
            longestStreak: longestStreak,
          ),
          const SizedBox(height: 16),
          _ActivityHeatmap(activity: activity),
          const SizedBox(height: 16),
          if (statusCounts.isNotEmpty) ...[
            _LibraryBreakdownCard(
              statusCounts: statusCounts,
              total: manga.length,
              label: isVault
                  ? 'Vault Breakdown'
                  : '${LibraryTypeProvider.label(contentType)} Breakdown',
            ),
            const SizedBox(height: 16),
          ],
          if (topSeries.isNotEmpty)
            _MostReadSeriesCard(series: topSeries),
        ],
      ),
    );
  }
}

// ── Empty State ──────────────────────────────────────────────
class _EmptyStatsView extends StatelessWidget {
  final bool isVault;
  final String contentType;
  const _EmptyStatsView({this.isVault = false, this.contentType = 'manga'});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final word = LibraryTypeProvider.label(contentType).toLowerCase();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isVault ? Icons.shield_outlined : Icons.auto_graph_rounded,
                size: 56, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text(
              'No stats yet',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isVault
                  ? 'Add $word to your vault and start reading to see stats here.'
                  : 'Add $word to your library and start reading to see your stats here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 13, color: cs.outline),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Top Stats Row ────────────────────────────────────────────
class _TopStatsRow extends StatelessWidget {
  final int totalManga;
  final int readChapters;
  final int totalChapters;

  const _TopStatsRow({
    required this.totalManga,
    required this.readChapters,
    required this.totalChapters,
  });

  String _format(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(1)}k' : '$n';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.menu_book_rounded,
            iconColor: cs.primary,
            value: _format(readChapters),
            label: 'Chapters Read',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.library_books_rounded,
            iconColor: cs.secondary,
            value: '$totalManga',
            label: 'Series',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatTile(
            icon: Icons.emoji_events_rounded,
            iconColor: AppTheme.warning,
            value: _format(totalChapters),
            label: 'Total Chapters',
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatTile({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: cs.outline,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Streak Card ──────────────────────────────────────────────
class _StreakCard extends StatelessWidget {
  final int currentStreak;
  final int longestStreak;

  const _StreakCard({
    required this.currentStreak,
    required this.longestStreak,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_fire_department_rounded,
                  size: 16, color: cs.secondary),
              const SizedBox(width: 6),
              Text(
                'Reading Streak',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StreakBar(
                  label: 'Current',
                  days: currentStreak,
                  maxDays: longestStreak > 0 ? longestStreak : 1,
                  color: cs.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StreakBar(
                  label: 'Best',
                  days: longestStreak,
                  maxDays: longestStreak > 0 ? longestStreak : 1,
                  color: cs.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            currentStreak == 0
                ? 'Start a streak by reading today!'
                : currentStreak == 1
                    ? 'Read tomorrow to keep the streak going!'
                    : '$currentStreak days strong — keep it up!',
            style: GoogleFonts.manrope(fontSize: 12, color: cs.outline),
          ),
        ],
      ),
    );
  }
}

class _StreakBar extends StatelessWidget {
  final String label;
  final int days;
  final int maxDays;
  final Color color;

  const _StreakBar({
    required this.label,
    required this.days,
    required this.maxDays,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ratio = maxDays > 0 ? (days / maxDays).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: GoogleFonts.manrope(fontSize: 11, color: cs.outline)),
            Text(
              '$days days',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: cs.outlineVariant,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// ── Activity Heatmap ─────────────────────────────────────────
class _ActivityHeatmap extends StatelessWidget {
  final Map<DateTime, int> activity;

  const _ActivityHeatmap({required this.activity});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Build 5 weeks × 7 days grid (35 days back)
    final List<DateTime> days = [];
    for (int i = 34; i >= 0; i--) {
      days.add(today.subtract(Duration(days: i)));
    }

    const dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded,
                  size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'Monthly Activity',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                _monthLabel(today),
                style: GoogleFonts.manrope(fontSize: 11, color: cs.outline),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Day-of-week labels
          Row(
            children: List.generate(7, (i) {
              return Expanded(
                child: Center(
                  child: Text(
                    dayLabels[i],
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      color: cs.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          // Heatmap grid — 5 rows × 7 cols
          ...List.generate(5, (week) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: List.generate(7, (dayOfWeek) {
                  final idx = week * 7 + dayOfWeek;
                  if (idx >= days.length) {
                    return const Expanded(child: SizedBox());
                  }
                  final date = days[idx];
                  final count = activity[date] ?? 0;
                  final isToday = date == today;

                  Color cellColor;
                  if (count == 0) {
                    cellColor = cs.outlineVariant;
                  } else if (count < 5) {
                    cellColor = cs.primary.withAlpha(80);
                  } else if (count < 15) {
                    cellColor = cs.primary.withAlpha(140);
                  } else {
                    cellColor = cs.primary;
                  }

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Container(
                          decoration: BoxDecoration(
                            color: cellColor,
                            borderRadius: BorderRadius.circular(3),
                            border: isToday
                                ? Border.all(
                                    color: cs.onSurface, width: 1.5)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
          const SizedBox(height: 8),
          // Legend
          Row(
            children: [
              Text('Less',
                  style:
                      GoogleFonts.manrope(fontSize: 10, color: cs.outline)),
              const SizedBox(width: 4),
              ...List.generate(4, (i) {
                final colors = [
                  cs.outlineVariant,
                  cs.primary.withAlpha(80),
                  cs.primary.withAlpha(140),
                  cs.primary,
                ];
                return Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: colors[i],
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
              const SizedBox(width: 4),
              Text('More',
                  style:
                      GoogleFonts.manrope(fontSize: 10, color: cs.outline)),
            ],
          ),
        ],
      ),
    );
  }

  String _monthLabel(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

// ── Library Breakdown ────────────────────────────────────────
class _LibraryBreakdownCard extends StatelessWidget {
  final Map<String, int> statusCounts;
  final int total;
  final String label;

  const _LibraryBreakdownCard({
    required this.statusCounts,
    required this.total,
    this.label = 'Library Breakdown',
  });

  Color _colorForStatus(String status) {
    switch (status.toLowerCase()) {
      case 'reading':
        return const Color(0xFFE85D4A);
      case 'completed':
        return AppTheme.secondary;
      case 'on hold':
        return AppTheme.warning;
      case 'dropped':
        return AppTheme.error;
      case 'plan to read':
        return AppTheme.success;
      default:
        return const Color(0xFF06B6D4);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = statusCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 16, color: cs.secondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...entries.map((e) {
            final ratio = total > 0 ? e.value / total : 0.0;
            final color = _colorForStatus(e.key);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          e.key,
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      Text(
                        '${e.value} (${(ratio * 100).round()}%)',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 5,
                      backgroundColor: cs.outlineVariant,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Most-Read Series ─────────────────────────────────────────
class _MostReadSeriesCard extends StatelessWidget {
  final List<LibraryManga> series;

  const _MostReadSeriesCard({required this.series});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded,
                  size: 16, color: AppTheme.success),
              const SizedBox(width: 6),
              Text(
                'Most-Read Series',
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...series.asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final m = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  // Rank badge
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: rank == 1
                          ? cs.secondary.withAlpha(30)
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: rank == 1 ? cs.secondary : cs.outline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Cover
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: m.coverUrl.isNotEmpty
                        ? MangaImage(
                            imageUrl: m.coverUrl,
                            width: 36,
                            height: 50,
                            fit: BoxFit.cover,
                            // Uri.origin THROWS on a scheme-less/relative url
                            // (common for migrated entries), which crashed this
                            // whole card to a grey box in a release build. The
                            // helper guards it.
                            referer: safeOrigin(m.url),
                          )
                        : Container(
                            width: 36,
                            height: 50,
                            color: cs.surface,
                            child: Icon(Icons.image_rounded,
                                size: 16, color: cs.outline),
                          ),
                  ),
                  const SizedBox(width: 10),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            _MiniStat(
                              icon: Icons.bookmark_rounded,
                              value: '${m.readChapters} ch',
                              color: cs.secondary,
                            ),
                            const SizedBox(width: 10),
                            _MiniStat(
                              icon: Icons.menu_book_rounded,
                              value: '${m.totalChapters} total',
                              color: cs.primary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(
          value,
          style: GoogleFonts.manrope(fontSize: 11, color: cs.outline),
        ),
      ],
    );
  }
}
