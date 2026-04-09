import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/services/library_update_service.dart';
import '../../core/providers/library_provider.dart';
import '../../core/providers/source_provider.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import '../widgets/manga_image.dart';

class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  List<MangaUpdate> _updates = [];
  bool _isUpdating = false;
  int _checkedCount = 0;
  int _totalCount = 0;
  DateTime? _lastUpdate;

  @override
  void initState() {
    super.initState();
    _loadUpdates();
  }

  Future<void> _loadUpdates() async {
    final updates = await LibraryUpdateService.loadUpdates();
    final last = await LibraryUpdateService.getLastUpdate();
    if (mounted) setState(() { _updates = updates; _lastUpdate = last; });
  }

  Future<void> _refreshUpdates() async {
    if (_isUpdating) return;
    setState(() { _isUpdating = true; _checkedCount = 0; });

    final libraryProvider = context.read<LibraryProvider>();
    final sourceProvider = context.read<SourceProvider>();
    _totalCount = libraryProvider.manga.length;

    final newUpdates = await LibraryUpdateService.checkForUpdates(
      libraryProvider: libraryProvider,
      sourceProvider: sourceProvider,
      onProgress: (checked, total) {
        if (mounted) setState(() { _checkedCount = checked; _totalCount = total; });
      },
    );

    await _loadUpdates();
    if (mounted) {
      setState(() => _isUpdating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newUpdates.isNotEmpty
            ? 'Found ${newUpdates.length} new chapter${newUpdates.length == 1 ? '' : 's'}'
            : 'No new chapters'),
        duration: const Duration(seconds: 2)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Group by date
    final grouped = <String, List<MangaUpdate>>{};
    for (final u in _updates) {
      final date = u.dateFound.length >= 10 ? u.dateFound.substring(0, 10) : 'Unknown';
      grouped.putIfAbsent(date, () => []).add(u);
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface, elevation: 0,
        title: Text('Updates', style: GoogleFonts.manrope(
            fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface)),
        actions: [
          if (_isUpdating)
            Padding(padding: const EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))))
          else
            IconButton(icon: Icon(Icons.refresh_rounded, color: cs.onSurface),
                tooltip: 'Check for updates', onPressed: _refreshUpdates),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: cs.onSurface),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'clear', child: Text('Clear all')),
            ],
            onSelected: (v) async {
              if (v == 'clear') { await LibraryUpdateService.clearUpdates(); _loadUpdates(); }
            },
          ),
        ],
      ),
      body: Column(children: [
        // Progress bar
        if (_isUpdating)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(children: [
              LinearProgressIndicator(
                value: _totalCount > 0 ? _checkedCount / _totalCount : null,
                backgroundColor: cs.surfaceContainerHighest, color: cs.primary, minHeight: 3),
              const SizedBox(height: 4),
              Text('Checking $_checkedCount / $_totalCount...',
                  style: GoogleFonts.manrope(fontSize: 11, color: cs.outline)),
            ])),

        // Last update
        if (_lastUpdate != null && !_isUpdating)
          Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(children: [
              Icon(Icons.schedule_rounded, size: 12, color: cs.outline),
              const SizedBox(width: 4),
              Text('Last checked: ${_formatTime(_lastUpdate!)}',
                  style: GoogleFonts.manrope(fontSize: 11, color: cs.outline)),
            ])),

        // List
        Expanded(
          child: _updates.isEmpty
              ? _buildEmpty(cs)
              : ListView(padding: const EdgeInsets.only(bottom: 80), children:
                  grouped.entries.map((e) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Text(_dateHeader(e.key), style: GoogleFonts.manrope(
                            fontSize: 11, fontWeight: FontWeight.w700,
                            color: cs.primary, letterSpacing: 1.0))),
                      ...e.value.map((u) => _UpdateTile(update: u, onTap: () {
                        Navigator.pushNamed(context, AppRoutes.mangaDetail, arguments: {
                          'mangaUrl': u.mangaUrl, 'sourceId': u.sourceId,
                          'title': u.mangaTitle, 'coverUrl': u.coverUrl,
                        });
                      })),
                    ],
                  )).toList()),
        ),
      ]),
    );
  }

  Widget _buildEmpty(ColorScheme cs) {
    return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 64, height: 64,
        decoration: BoxDecoration(color: cs.primary.withAlpha(31),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
        child: Icon(Icons.update_rounded, size: 32, color: cs.primary)),
      const SizedBox(height: 16),
      Text('No updates yet', style: GoogleFonts.manrope(
          fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
      const SizedBox(height: 6),
      Text('Tap refresh to check for new chapters',
          style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
      const SizedBox(height: 16),
      FilledButton.icon(
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: Text('Check Now', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
        style: FilledButton.styleFrom(backgroundColor: cs.primary, foregroundColor: Colors.white),
        onPressed: _isUpdating ? null : _refreshUpdates),
    ]));
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _dateHeader(String date) {
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final yd = now.subtract(const Duration(days: 1));
    final yesterday = '${yd.year}-${yd.month.toString().padLeft(2, '0')}-${yd.day.toString().padLeft(2, '0')}';
    if (date == today) return 'TODAY';
    if (date == yesterday) return 'YESTERDAY';
    return date.toUpperCase();
  }
}

class _UpdateTile extends StatelessWidget {
  final MangaUpdate update;
  final VoidCallback onTap;
  const _UpdateTile({required this.update, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(onTap: onTap, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(6),
          child: SizedBox(width: 42, height: 56,
            child: update.coverUrl.isNotEmpty
                ? MangaImage(imageUrl: update.coverUrl, fit: BoxFit.cover)
                : Container(color: cs.surfaceContainerHighest,
                    child: Icon(Icons.image_rounded, size: 18, color: cs.outline)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(update.mangaTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(update.chapterName, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
        ])),
        if (!update.isRead)
          Container(width: 8, height: 8,
            decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle)),
      ]),
    ));
  }
}
