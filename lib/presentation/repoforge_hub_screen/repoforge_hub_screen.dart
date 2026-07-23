import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/models/source_model.dart';
import '../../core/providers/source_provider.dart';
import '../../core/repoforge/local_repo_service.dart';
import '../../core/repoforge/selector_knowledge_base.dart';
import '../../core/repoforge/mangayomi_js_generator.dart';
import '../../routes/app_routes.dart';
import '../../theme/app_theme.dart';
import 'repoforge_coverage_screen.dart';

/// RepoForge's dedicated home (Settings › RepoForge). Deeper than the old
/// magic-wand shortcut: create sources, manage the ones you've generated,
/// import/export them, and see what RepoForge can build.
class RepoForgeHubScreen extends StatefulWidget {
  const RepoForgeHubScreen({super.key});

  @override
  State<RepoForgeHubScreen> createState() => _RepoForgeHubScreenState();
}

class _RepoForgeHubScreenState extends State<RepoForgeHubScreen> {
  final _repo = LocalRepoService();
  List<MangaSource> _sources = [];
  bool _loading = true;
  int _mangaKbCount = 0;
  int _novelKbCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sources = await _repo.listSources();
    final mangaKb = await SelectorKnowledgeBase.siteCount();
    // Novel KB count via a cheap lookup of a sentinel is not possible; expose
    // the size by reading the bundled asset count through the KB helper.
    final novelKb = await _novelKbSize();
    if (!mounted) return;
    setState(() {
      _sources = sources;
      _mangaKbCount = mangaKb;
      _novelKbCount = novelKb;
      _loading = false;
    });
  }

  Future<int> _novelKbSize() async {
    // The novel KB is small; count via a known-loaded map by probing one host
    // is unreliable — instead re-read the asset count through the KB.
    return SelectorKnowledgeBase.novelSiteCount();
  }

  Future<void> _newSource() async {
    await Navigator.pushNamed(context, AppRoutes.sourceCreator);
    if (mounted) {
      context.read<SourceProvider>().refreshRepos();
      _load();
    }
  }

  Future<void> _editSource(MangaSource s) async {
    await Navigator.pushNamed(context, AppRoutes.sourceCreator,
        arguments: {'seedUrl': s.baseUrl});
    if (mounted) {
      context.read<SourceProvider>().refreshRepos();
      _load();
    }
  }

  Future<void> _openInBrowse(MangaSource s) async {
    Navigator.pushNamed(context, AppRoutes.sourceCatalog, arguments: {
      'sourceId': s.id,
      'sourceName': s.name,
    });
  }

  Future<void> _deleteSource(MangaSource s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete source?'),
        content: Text('"${s.name}" will be removed from My Sources.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteSource(s.id);
    if (!mounted) return;
    final provider = context.read<SourceProvider>();
    await provider.uninstallSource(s.id);
    await provider.refreshRepos();
    if (mounted) AppTheme.showSnackBar(context, 'Deleted "${s.name}"');
    _load();
  }

  Future<void> _exportAll() async {
    if (_sources.isEmpty) {
      AppTheme.showSnackBar(context, 'No sources to export');
      return;
    }
    try {
      final bundle = await _repo.exportBundle();
      final bytes = Uint8List.fromList(utf8.encode(bundle));
      String? path = await FilePicker.saveFile(
        dialogTitle: 'Export RepoForge sources',
        fileName: 'foxlations_sources.json',
        bytes: bytes,
      );
      // Some platforms return a path but don't write bytes themselves.
      if (path != null && !await File(path).exists()) {
        await File(path).writeAsBytes(bytes);
      }
      if (!mounted) return;
      if (path == null) {
        // Fallback: drop it in app documents and report the path.
        final docs = await getApplicationDocumentsDirectory();
        final f = File('${docs.path}/foxlations_sources.json');
        await f.writeAsBytes(bytes);
        path = f.path;
      }
      AppTheme.showSnackBar(context, 'Exported ${_sources.length} sources');
    } catch (e) {
      if (mounted) AppTheme.showSnackBar(context, 'Export failed: $e');
    }
  }

  Future<void> _import() async {
    try {
      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      final path = res?.files.single.path;
      if (path == null) return;
      final content = await File(path).readAsString();
      final n = await _repo.importBundle(content);
      if (!mounted) return;
      final provider = context.read<SourceProvider>();
      await provider.addRepo(await _repo.indexPath());
      await provider.refreshRepos();
      if (mounted) AppTheme.showSnackBar(context, 'Imported $n source(s)');
      _load();
    } catch (e) {
      if (mounted) AppTheme.showSnackBar(context, 'Import failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('RepoForge',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            _heroCard(cs),
            const SizedBox(height: 18),
            _actionsRow(cs),
            const SizedBox(height: 24),
            _mySourcesHeader(cs),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_sources.isEmpty)
              _emptyState(cs)
            else
              ..._sources.map((s) => _sourceCard(s, cs)),
          ],
        ),
      ),
    );
  }

  Widget _heroCard(ColorScheme cs) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cs.primaryContainer, cs.surfaceContainerHighest],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.auto_fix_high_rounded, color: cs.primary, size: 24),
            const SizedBox(width: 10),
            Text('Build sources from any URL',
                style: GoogleFonts.manrope(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary.withAlpha(38),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: cs.primary.withAlpha(120)),
              ),
              child: Text('BETA',
                  style: GoogleFonts.manrope(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: cs.primary)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            'Detect a site’s framework, tune selectors, and install a working '
            'manga / anime / novel source — no server, all on-device. RepoForge '
            'is in beta, so it won’t always get a source right — check the '
            'result and tweak the selectors if a site doesn’t come out correct.',
            style: GoogleFonts.manrope(
                fontSize: 12.5, height: 1.4, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const RepoForgeCoverageScreen())),
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surface.withAlpha(140),
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
              child: Row(children: [
                Icon(Icons.dataset_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${MangayomiJsGenerator.supportedFrameworks.length} frameworks · '
                    '$_mangaKbCount manga + $_novelKbCount novel sites known',
                    style: GoogleFonts.manrope(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: cs.outline),
              ]),
            ),
          ),
        ]),
      );

  Widget _actionsRow(ColorScheme cs) => Row(children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _newSource,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New Source'),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.file_download_rounded, size: 18),
            label: const Text('Import'),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ),
      ]);

  Widget _mySourcesHeader(ColorScheme cs) => Row(children: [
        Text('MY SOURCES${_sources.isEmpty ? '' : ' (${_sources.length})'}',
            style: GoogleFonts.manrope(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: cs.primary)),
        const Spacer(),
        if (_sources.isNotEmpty)
          TextButton.icon(
            onPressed: _exportAll,
            icon: const Icon(Icons.file_upload_rounded, size: 16),
            label: const Text('Export all'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
      ]);

  Widget _emptyState(ColorScheme cs) => Container(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        alignment: Alignment.center,
        child: Column(children: [
          Icon(Icons.travel_explore_rounded, size: 40, color: cs.outline),
          const SizedBox(height: 12),
          Text('No sources yet',
              style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface)),
          const SizedBox(height: 6),
          Text('Tap “New Source” to generate one from a site URL.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 12.5, color: cs.outline)),
        ]),
      );

  Widget _sourceCard(MangaSource s, ColorScheme cs) {
    final installed = context.watch<SourceProvider>().isInstalled(s.id);
    final icon = s.isAnime
        ? Icons.movie_rounded
        : s.isNovel
            ? Icons.menu_book_rounded
            : Icons.import_contacts_rounded;
    final host = Uri.tryParse(s.baseUrl)?.host.replaceFirst('www.', '') ?? s.baseUrl;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: ListTile(
        onTap: () => _openInBrowse(s),
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          child: Icon(icon, color: cs.primary, size: 20),
        ),
        title: Text(s.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Text(
          '$host · ${s.framework}${s.isNsfw ? ' · 18+' : ''}'
          '${installed ? '' : ' · not installed'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.manrope(fontSize: 11.5, color: cs.outline),
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: cs.outline),
          onSelected: (v) {
            switch (v) {
              case 'open':
                _openInBrowse(s);
                break;
              case 'edit':
                _editSource(s);
                break;
              case 'delete':
                _deleteSource(s);
                break;
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'open', child: Text('Open in browse')),
            PopupMenuItem(value: 'edit', child: Text('Edit / re-detect')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}
