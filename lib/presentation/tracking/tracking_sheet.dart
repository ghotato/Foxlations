import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/providers/tracking_provider.dart';
import '../../core/tracking/tracker.dart';
import '../../core/tracking/tracker_models.dart';
import '../../theme/app_theme.dart';

/// Bottom sheet for linking a manga to tracking services and editing its
/// status / chapter progress / score per service.
class TrackingSheet extends StatefulWidget {
  final String mangaKey;
  final String title;
  final int localProgress;

  const TrackingSheet({
    super.key,
    required this.mangaKey,
    required this.title,
    this.localProgress = 0,
  });

  @override
  State<TrackingSheet> createState() => _TrackingSheetState();
}

class _TrackingSheetState extends State<TrackingSheet> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tp = context.watch<TrackingProvider>();
    final connected = tp.connected;
    final bindings = {for (final b in tp.bindingsFor(widget.mangaKey)) b.trackerId: b};

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2)),
          ),
          Row(children: [
            Icon(Icons.sync_rounded, color: cs.primary, size: 20),
            const SizedBox(width: 8),
            Text('Tracking',
                style: GoogleFonts.manrope(
                    fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 12),
          if (connected.isEmpty)
            _notConnected(cs)
          else
            ...connected.map((t) => bindings[t.id] != null
                ? _boundCard(t, bindings[t.id]!, cs)
                : _unboundCard(t, cs)),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _notConnected(ColorScheme cs) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(children: [
          Icon(Icons.link_off_rounded, color: cs.outline, size: 36),
          const SizedBox(height: 10),
          Text('No tracker connected',
              style: GoogleFonts.manrope(
                  fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Connect AniList, MyAnimeList, or Kitsu in Settings › Tracking.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
        ]),
      );

  Widget _unboundCard(Tracker t, ColorScheme cs) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        child: Row(children: [
          Icon(_iconFor(t.id), color: Color(t.colorValue), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Not linked on ${t.name}',
                style: GoogleFonts.manrope(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            onPressed: () => _linkFlow(t),
            style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact),
            child: const Text('Link'),
          ),
        ]),
      );

  Widget _boundCard(Tracker t, TrackRecord r, ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: Color(t.colorValue).withAlpha(80)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_iconFor(t.id), color: Color(t.colorValue), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(r.title.isEmpty ? t.name : r.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: 'Unlink',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.link_off_rounded, size: 18, color: cs.outline),
            onPressed: () =>
                context.read<TrackingProvider>().removeBinding(widget.mangaKey, t.id),
          ),
        ]),
        const SizedBox(height: 8),
        // Status
        Row(children: [
          SizedBox(
              width: 70,
              child: Text('Status',
                  style: GoogleFonts.manrope(fontSize: 12, color: cs.outline))),
          Expanded(
            child: DropdownButton<TrackStatus>(
              value: r.status,
              isExpanded: true,
              isDense: true,
              underline: const SizedBox.shrink(),
              style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface),
              items: TrackStatus.values
                  .map((s) =>
                      DropdownMenuItem(value: s, child: Text(s.label)))
                  .toList(),
              onChanged: (s) {
                if (s != null) _save(t, r.copyWith(status: s));
              },
            ),
          ),
        ]),
        // Progress
        Row(children: [
          SizedBox(
              width: 70,
              child: Text('Chapters',
                  style: GoogleFonts.manrope(fontSize: 12, color: cs.outline))),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
            onPressed: r.lastChapterRead > 0
                ? () => _save(
                    t, r.copyWith(lastChapterRead: r.lastChapterRead - 1))
                : null,
          ),
          Text(
            r.totalChapters > 0
                ? '${r.lastChapterRead} / ${r.totalChapters}'
                : '${r.lastChapterRead}',
            style: GoogleFonts.manrope(
                fontSize: 13, fontWeight: FontWeight.w700),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
            onPressed: () =>
                _save(t, r.copyWith(lastChapterRead: r.lastChapterRead + 1)),
          ),
        ]),
        // Score
        Row(children: [
          SizedBox(
              width: 70,
              child: Text('Score',
                  style: GoogleFonts.manrope(fontSize: 12, color: cs.outline))),
          Expanded(
            child: Slider(
              value: r.score.clamp(0, 10),
              min: 0,
              max: 10,
              divisions: 20,
              label: r.score == 0 ? '—' : r.score.toStringAsFixed(1),
              onChanged: (v) => setState(() => r.score = v),
              onChangeEnd: (v) => _save(t, r.copyWith(score: v)),
            ),
          ),
          SizedBox(
            width: 28,
            child: Text(r.score == 0 ? '—' : r.score.toStringAsFixed(1),
                textAlign: TextAlign.end,
                style: GoogleFonts.manrope(
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
      ]),
    );
  }

  void _save(Tracker t, TrackRecord updated) {
    context.read<TrackingProvider>().updateRecord(widget.mangaKey, updated);
  }

  Future<void> _linkFlow(Tracker t) async {
    final result = await showModalBottomSheet<TrackSearchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _TrackSearchSheet(tracker: t, initialQuery: widget.title),
    );
    if (result == null || !mounted) return;
    await context.read<TrackingProvider>().bind(
          widget.mangaKey,
          t.id,
          result,
          localProgress: widget.localProgress,
        );
    if (mounted) {
      AppTheme.showSnackBar(context, 'Linked to ${t.name}');
    }
  }

  IconData _iconFor(String id) {
    switch (id) {
      case 'anilist':
        return Icons.auto_graph_rounded;
      case 'kitsu':
        return Icons.pets_rounded;
      default:
        return Icons.track_changes_rounded;
    }
  }
}

/// Search a tracker's catalog and pick the entry to link.
class _TrackSearchSheet extends StatefulWidget {
  final Tracker tracker;
  final String initialQuery;
  const _TrackSearchSheet({required this.tracker, required this.initialQuery});

  @override
  State<_TrackSearchSheet> createState() => _TrackSearchSheetState();
}

class _TrackSearchSheetState extends State<_TrackSearchSheet> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.initialQuery);
  List<TrackSearchResult> _results = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    setState(() => _loading = true);
    final res = await context
        .read<TrackingProvider>()
        .search(widget.tracker.id, _ctl.text);
    if (mounted) {
      setState(() {
        _results = res;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 12),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(children: [
          Text('Link on ${widget.tracker.name}',
              style: GoogleFonts.manrope(
                  fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _ctl,
                autofocus: false,
                decoration: InputDecoration(
                  hintText: 'Search title',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium)),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
                onPressed: _loading ? null : _search,
                child: const Text('Search')),
          ]),
          const SizedBox(height: 10),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Text('No results',
                            style: GoogleFonts.manrope(color: cs.outline)))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final r = _results[i];
                          return ListTile(
                            leading: r.coverUrl.isEmpty
                                ? null
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: Image.network(r.coverUrl,
                                        width: 40,
                                        height: 56,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const SizedBox(width: 40)),
                                  ),
                            title: Text(r.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.manrope(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            subtitle: r.totalChapters > 0
                                ? Text('${r.totalChapters} ch',
                                    style: GoogleFonts.manrope(
                                        fontSize: 11, color: cs.outline))
                                : null,
                            onTap: () => Navigator.pop(context, r),
                          );
                        },
                      ),
          ),
        ]),
      ),
    );
  }
}
