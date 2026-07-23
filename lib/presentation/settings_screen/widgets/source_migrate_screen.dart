import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/models/manga_model.dart';
import '../../../core/models/installed_source_model.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/providers/source_provider.dart';
import '../../../core/providers/tracking_provider.dart';
import '../../../core/utils/search_filter.dart';
import '../../../eval/lib.dart';
import '../../../eval/model/m_manga.dart';
import '../../../theme/app_theme.dart';

/// Moves *every* library entry from one source to another in one pass — the
/// bulk companion to the per-entry Migrate. Two main uses:
///  • swapping an old source for a newer one on the SAME site (e.g. a
///    keiyoushi Asura source → a Foxtensions Asura source), where the manga
///    URLs match and the move is exact; and
///  • re-homing entries imported from a Kotlin reader's backup, whose original
///    source isn't installed here — they show up as an "imported" group that
///    can be pointed at a real Foxlations source.
class SourceMigrateScreen extends StatefulWidget {
  const SourceMigrateScreen({super.key});

  @override
  State<SourceMigrateScreen> createState() => _SourceMigrateScreenState();
}

class _SourceGroup {
  final String id;
  final String label;
  final int count;
  final bool installed;
  const _SourceGroup(this.id, this.label, this.count, this.installed);
}

class _PlanItem {
  final LibraryManga entry;
  String matchType; // 'url' | 'title' | 'none'
  String? targetUrl;
  MManga? detail;
  _PlanItem(this.entry, {this.matchType = 'none', this.targetUrl, this.detail});
}

class _SourceMigrateScreenState extends State<SourceMigrateScreen> {
  String? _fromId;
  String? _toId;
  bool _matchByTitle = false;

  bool _busy = false;
  String _busyLabel = '';
  int _progress = 0;
  int _progressTotal = 0;

  bool _finished = false;
  int _movedUrl = 0;
  int _movedTitle = 0;
  final List<String> _unmatched = [];

  // ── source enumeration ──────────────────────────────────────
  List<_SourceGroup> _fromGroups() {
    final lib = context.read<LibraryProvider>();
    final sources = context.read<SourceProvider>().installedSources;
    final byId = {for (final s in sources) s.source.id: s};
    final counts = <String, int>{};
    for (final m in lib.manga) {
      counts[m.sourceId] = (counts[m.sourceId] ?? 0) + 1;
    }
    final groups = counts.entries.map((e) {
      final inst = byId[e.key];
      final installed = inst != null;
      final label = installed
          ? inst.source.name
          : 'Imported source · ${_shortId(e.key)}';
      return _SourceGroup(e.key, label, e.value, installed);
    }).toList();
    // Installed first, then by count desc.
    groups.sort((a, b) {
      if (a.installed != b.installed) return a.installed ? -1 : 1;
      return b.count.compareTo(a.count);
    });
    return groups;
  }

  List<InstalledSource> _toSources() =>
      context.read<SourceProvider>().installedSources
          .where((s) => s.source.id != _fromId)
          .toList();

  String _shortId(String id) =>
      id.length <= 10 ? id : '${id.substring(0, 10)}…';

  InstalledSource? _installed(String id) {
    for (final s in context.read<SourceProvider>().installedSources) {
      if (s.source.id == id) return s;
    }
    return null;
  }

  String? _chapterNumber(String name) {
    final dec = RegExp(r'(\d+\.\d+)').firstMatch(name);
    if (dec != null) return dec.group(1);
    return RegExp(r'(\d+)').firstMatch(name)?.group(1);
  }

  // ── run ─────────────────────────────────────────────────────
  Future<void> _start() async {
    final fromId = _fromId, toId = _toId;
    if (fromId == null || toId == null) return;
    final to = _installed(toId);
    if (to == null) return;

    final lib = context.read<LibraryProvider>();
    final entries =
        lib.manga.where((m) => m.sourceId == fromId).toList(growable: false);
    if (entries.isEmpty) return;

    // Phase 1 — analyse: find each entry on the target (exact URL, then an
    // optional title search) and cache the fetched detail for the commit.
    setState(() {
      _busy = true;
      _busyLabel = 'Checking matches';
      _progress = 0;
      _progressTotal = entries.length;
    });

    final plan = <_PlanItem>[];
    for (final e in entries) {
      if (!mounted) return;
      setState(() => _progress++);
      plan.add(await _plan(e, to));
    }

    final urlN = plan.where((p) => p.matchType == 'url').length;
    final titleN = plan.where((p) => p.matchType == 'title').length;
    final noneN = plan.where((p) => p.matchType == 'none').length;

    if (!mounted) return;
    setState(() => _busy = false);

    // Phase 2 — confirm.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Migrate this source?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summaryRow(ctx, '$urlN matched by URL', Icons.link_rounded),
            if (titleN > 0)
              _summaryRow(ctx, '$titleN matched by title', Icons.title_rounded),
            _summaryRow(
                ctx,
                '$noneN not found — left in place',
                Icons.remove_circle_outline_rounded),
            const SizedBox(height: 10),
            Text(
              'Read progress, categories and tracking carry over. The originals '
              'are removed only for entries that move.',
              style: GoogleFonts.manrope(fontSize: 12, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: (urlN + titleN) == 0
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: Text('Migrate ${urlN + titleN}')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // Phase 3 — commit.
    await _commit(plan, fromId, toId);
  }

  Future<_PlanItem> _plan(LibraryManga e, InstalledSource to) async {
    // Exact URL first — works for same-site swaps and most Kotlin imports.
    try {
      final detail = await withExtensionService(
        to.source, to.sourceCode, (s) => s.getDetail(e.url));
      if ((detail.chapters?.isNotEmpty ?? false) ||
          (detail.name ?? '').isNotEmpty) {
        return _PlanItem(e, matchType: 'url', targetUrl: e.url, detail: detail);
      }
    } catch (_) {/* not a URL match — fall through */}

    if (_matchByTitle && e.title.trim().isNotEmpty) {
      try {
        final res = await withExtensionService(
            to.source, to.sourceCode, (s) => s.search(e.title, 1, []));
        final matched = filterSearchResults(res.list, e.title);
        final link = matched.isNotEmpty ? matched.first.link : null;
        if (link != null && link.isNotEmpty) {
          final detail = await withExtensionService(
              to.source, to.sourceCode, (s) => s.getDetail(link));
          return _PlanItem(e,
              matchType: 'title', targetUrl: link, detail: detail);
        }
      } catch (_) {/* no title match */}
    }
    return _PlanItem(e, matchType: 'none');
  }

  Future<void> _commit(
      List<_PlanItem> plan, String fromId, String toId) async {
    final lib = context.read<LibraryProvider>();
    final tracking = context.read<TrackingProvider>();
    final movable = plan.where((p) => p.matchType != 'none').toList();

    setState(() {
      _busy = true;
      _busyLabel = 'Migrating';
      _progress = 0;
      _progressTotal = movable.length;
    });

    for (final p in movable) {
      if (!mounted) return;
      setState(() => _progress++);
      try {
        await _move(lib, tracking, p, fromId, toId);
      } catch (_) {
        // A single failed move shouldn't abort the batch; leave it in place.
        _unmatched.add(p.entry.title);
        continue;
      }
      if (p.matchType == 'url') {
        _movedUrl++;
      } else {
        _movedTitle++;
      }
    }
    for (final p in plan.where((p) => p.matchType == 'none')) {
      _unmatched.add(p.entry.title);
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _finished = true;
    });
  }

  Future<void> _move(LibraryProvider lib, TrackingProvider tracking,
      _PlanItem p, String fromId, String toId) async {
    final old = p.entry;
    final targetUrl = p.targetUrl ?? old.url;
    final detail = p.detail;
    final sameUrl = targetUrl == old.url;

    // Which chapters were read on the old entry — matched to the new list by
    // URL (same-site) or by chapter number (cross-site).
    final readUrls = <String>{};
    final readNums = <String>{};
    for (final ch in lib.getCachedChapters(fromId, old.url)) {
      if (lib.isChapterRead(fromId, ch.chapterUrl)) {
        readUrls.add(ch.chapterUrl);
        final n = _chapterNumber(ch.title);
        if (n != null) readNums.add(n);
      }
    }

    final newManga = LibraryManga(
      sourceId: toId,
      url: targetUrl,
      title: detail?.name?.isNotEmpty == true ? detail!.name! : old.title,
      coverUrl: (detail?.imageUrl?.isNotEmpty ?? false)
          ? detail!.imageUrl!
          : old.coverUrl,
      author: detail?.author ?? old.author,
      description: detail?.description ?? old.description,
      genres: old.genres,
      status: old.status,
      categories: old.categories,
      lastReadAt: old.lastReadAt,
      lastReadChapterUrl: sameUrl ? old.lastReadChapterUrl : null,
      lastReadPage: sameUrl ? old.lastReadPage : 0,
      totalChapters: detail?.chapters?.length ?? old.totalChapters,
      readChapters: old.readChapters,
    );
    await lib.addToLibrary(newManga);

    final chapters = detail?.chapters ?? const [];
    if (chapters.isNotEmpty) {
      await lib.cacheChapters(
          toId, targetUrl, chapters.map((c) => c.toJson()).toList());
      for (final ch in chapters) {
        final u = ch.url ?? '';
        final n = _chapterNumber(ch.name ?? '');
        if (readUrls.contains(u) || (n != null && readNums.contains(n))) {
          await lib.markChapterRead(toId, targetUrl, u);
        }
      }
    }

    // Carry tracker bindings, then drop the original.
    try {
      await tracking.copyBindings(
        fromSourceId: fromId,
        fromUrl: old.url,
        toSourceId: toId,
        toUrl: targetUrl,
        removeOld: true,
      );
    } catch (_) {}
    await lib.removeFromLibrary(fromId, old.url);
  }

  // ── UI ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        title: Text('Migrate a source',
            style: GoogleFonts.manrope(
                fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: _finished
          ? _buildResult(cs)
          : _busy
              ? _buildBusy(cs)
              : _buildForm(cs),
    );
  }

  Widget _buildForm(ColorScheme cs) {
    final fromGroups = _fromGroups();
    final toSources = _toSources();
    final fromSel = fromGroups.where((g) => g.id == _fromId).firstOrNull;
    final toSel = toSources.where((s) => s.source.id == _toId).firstOrNull;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Move every library entry from one source to another. Same-site '
            'swaps match exactly by URL; imported entries from a backup can be '
            're-homed to a real source too.',
            style: GoogleFonts.manrope(
                fontSize: 12.5, height: 1.4, color: cs.onSurfaceVariant)),
        const SizedBox(height: 20),
        _label('FROM', cs),
        _picker(
          cs,
          fromSel == null
              ? 'Select a source…'
              : '${fromSel.label}  ·  ${fromSel.count}',
          fromGroups.isEmpty,
          () => _pickFrom(fromGroups),
        ),
        const SizedBox(height: 16),
        _label('TO', cs),
        _picker(
          cs,
          toSel == null ? 'Select a source…' : toSel.source.name,
          _fromId == null || toSources.isEmpty,
          () => _pickTo(toSources),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _matchByTitle,
          activeColor: cs.primary,
          title: Text('Also match by title',
              style: GoogleFonts.manrope(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text(
              'For cross-site moves: if an entry isn’t found by URL, search the '
              'new source by title and take the closest match. Off by default '
              'so it can’t attach the wrong series.',
              style: GoogleFonts.manrope(fontSize: 11.5, color: cs.outline)),
          onChanged: (v) => setState(() => _matchByTitle = v),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: (_fromId != null && _toId != null) ? _start : null,
          icon: const Icon(Icons.swap_horiz_rounded),
          label: const Text('Migrate source'),
          style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              padding: const EdgeInsets.symmetric(vertical: 14)),
        ),
      ],
    );
  }

  Widget _buildBusy(ColorScheme cs) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('$_busyLabel  $_progress/$_progressTotal',
              style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w600, color: cs.onSurface)),
        ]),
      );

  Widget _buildResult(ColorScheme cs) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(Icons.check_circle_rounded, color: cs.primary, size: 48),
          const SizedBox(height: 12),
          Text('Migration complete',
              style: GoogleFonts.manrope(
                  fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _summaryRow(context, '$_movedUrl moved by URL', Icons.link_rounded),
          if (_movedTitle > 0)
            _summaryRow(
                context, '$_movedTitle moved by title', Icons.title_rounded),
          _summaryRow(context, '${_unmatched.length} left in place',
              Icons.remove_circle_outline_rounded),
          if (_unmatched.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Not migrated (still on the old source):',
                style: GoogleFonts.manrope(
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            ..._unmatched.take(50).map((t) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• $t',
                      style: GoogleFonts.manrope(
                          fontSize: 12, color: cs.onSurfaceVariant)),
                )),
            Text('Use the per-title Migrate for these.',
                style: GoogleFonts.manrope(fontSize: 11.5, color: cs.outline)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(backgroundColor: cs.primary),
            child: const Text('Done'),
          ),
        ],
      );

  Widget _label(String t, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t,
            style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: cs.primary)),
      );

  Widget _picker(
      ColorScheme cs, String text, bool disabled, VoidCallback onTap) {
    return InkWell(
      onTap: disabled ? null : onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withAlpha(disabled ? 60 : 255),
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(children: [
          Expanded(
              child: Text(text,
                  style: GoogleFonts.manrope(
                      fontSize: 14,
                      color: disabled ? cs.outline : cs.onSurface))),
          Icon(Icons.expand_more_rounded, color: cs.outline),
        ]),
      ),
    );
  }

  void _pickFrom(List<_SourceGroup> groups) {
    _sheet(groups
        .map((g) => _SheetOption('${g.label}  ·  ${g.count}',
            g.installed ? Icons.extension_rounded : Icons.download_done_rounded,
            () => setState(() {
                  _fromId = g.id;
                  if (_toId == g.id) _toId = null;
                })))
        .toList());
  }

  void _pickTo(List<InstalledSource> sources) {
    _sheet(sources
        .map((s) => _SheetOption(s.source.name, Icons.extension_rounded,
            () => setState(() => _toId = s.source.id)))
        .toList());
  }

  void _sheet(List<_SheetOption> options) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const SizedBox(height: 8),
          ...options.map((o) => ListTile(
                leading: Icon(o.icon, color: cs.primary),
                title: Text(o.label,
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  o.onTap();
                },
              )),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _summaryRow(BuildContext ctx, String text, IconData icon) {
    final cs = Theme.of(ctx).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: GoogleFonts.manrope(
                    fontSize: 13.5, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

class _SheetOption {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _SheetOption(this.label, this.icon, this.onTap);
}
