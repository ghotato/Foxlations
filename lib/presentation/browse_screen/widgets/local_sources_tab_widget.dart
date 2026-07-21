import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/services/local_source_service.dart';
import '../../../routes/app_routes.dart';
import '../../../theme/app_theme.dart';

class LocalSourcesTabWidget extends StatefulWidget {
  final String searchQuery;
  const LocalSourcesTabWidget({super.key, required this.searchQuery});

  @override
  State<LocalSourcesTabWidget> createState() => _LocalSourcesTabWidgetState();
}

class _LocalSourcesTabWidgetState extends State<LocalSourcesTabWidget> {
  final _service = LocalSourceService();
  List<String> _folders = [];
  List<LocalManga> _manga = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _folders = await _service.getFolders();
    _manga = await _service.scanAll();
    if (mounted) setState(() => _loading = false);
  }

  /// iOS hands back a security-scoped URL from the folder picker that the app
  /// cannot re-open later, so the folder scans to nothing and the user is left
  /// staring at an empty shelf with no error. Say so and point at file import,
  /// which works because it copies the picked file into our own sandbox.
  bool _warnIfFoldersUnsupported() {
    if (!Platform.isIOS) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'iOS does not allow apps to keep access to a folder. '
          'Use "Import File" to add .cbz/.cbr/.zip/.epub/.pdf instead.',
        ),
        duration: Duration(seconds: 5),
      ),
    );
    return true;
  }

  Future<void> _addFolder() async {
    if (_warnIfFoldersUnsupported()) return;
    final path = await FilePicker.getDirectoryPath();
    if (path != null) {
      await _service.addFolder(path);
      _load();
    }
  }

  Future<void> _removeFolder(String path) async {
    await _service.removeFolder(path);
    _load();
  }

  /// Pick one or more archive/PDF files and import them as local manga.
  Future<void> _importFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: LocalSourceService.importableExts.toList(),
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    int imported = 0;
    for (final f in result.files) {
      if (f.path != null && await _service.importFile(f.path!) != null) {
        imported++;
      }
    }
    if (!mounted) return;
    AppTheme.showSnackBar(
      context,
      imported > 0
          ? 'Imported $imported file${imported == 1 ? '' : 's'}'
          : 'Nothing imported (unsupported or unreadable)',
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Filter by search
    var filtered = _manga;
    if (widget.searchQuery.isNotEmpty) {
      final q = widget.searchQuery.toLowerCase();
      filtered = filtered.where((m) => m.title.toLowerCase().contains(q)).toList();
    }

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_folders.isEmpty) {
      return _buildEmptyState(cs);
    }

    return Column(children: [
      // Folder management bar
      Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          Icon(Icons.folder_rounded, size: 16, color: cs.primary),
          const SizedBox(width: 8),
          Text('${_folders.length} folder${_folders.length == 1 ? '' : 's'}',
              style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurface)),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.settings_rounded, size: 18, color: cs.outline),
            tooltip: 'Manage folders',
            visualDensity: VisualDensity.compact,
            onPressed: () => _showFolderManager(context),
          ),
          IconButton(
            icon: Icon(Icons.note_add_rounded, size: 19, color: cs.primary),
            tooltip: 'Import file (CBZ/ZIP/EPUB/PDF)',
            visualDensity: VisualDensity.compact,
            onPressed: _importFile,
          ),
          IconButton(
            icon: Icon(Icons.add_rounded, size: 20, color: cs.primary),
            tooltip: 'Add folder',
            visualDensity: VisualDensity.compact,
            onPressed: _addFolder,
          ),
          IconButton(
            icon: Icon(Icons.refresh_rounded, size: 18, color: cs.outline),
            tooltip: 'Rescan',
            visualDensity: VisualDensity.compact,
            onPressed: _load,
          ),
        ]),
      ),
      Divider(height: 1, color: cs.surfaceContainerHighest),

      // Manga grid
      Expanded(
        child: filtered.isEmpty
            ? Center(child: Text('No manga found',
                style: GoogleFonts.manrope(fontSize: 14, color: cs.outline)))
            : GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.65,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: filtered.length,
                itemBuilder: (_, i) => _LocalMangaCard(
                  manga: filtered[i],
                  onTap: () => Navigator.pushNamed(context, AppRoutes.mangaDetail,
                      arguments: {
                        'mangaUrl': 'local://${filtered[i].path}',
                        'sourceId': 'local',
                        'title': filtered[i].title,
                        'coverUrl': filtered[i].coverPath != null
                            ? 'file://${filtered[i].coverPath}'
                            : null,
                      }),
                ),
              ),
      ),
    ]);
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20)),
            child: Icon(Icons.folder_open_rounded, size: 36, color: cs.outline),
          ),
          const SizedBox(height: 20),
          Text('No local sources',
              style: GoogleFonts.manrope(fontSize: 17, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 8),
          Text(
            'Add a folder of manga, or import a single file.\nSupported: images (JPG, PNG, WebP, GIF), CBZ/ZIP, EPUB and PDF.\n(CBR/RAR only if the file is actually ZIP-packed — true RAR isn\'t supported.)',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(fontSize: 13, color: cs.outline, height: 1.5)),
          const SizedBox(height: 20),
          Row(mainAxisSize: MainAxisSize.min, children: [
            FilledButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text('Add Folder', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary, foregroundColor: cs.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
              onPressed: _addFolder,
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.note_add_rounded, size: 18),
              label: Text('Import File', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.primary,
                side: BorderSide(color: cs.primary.withAlpha(80)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
              onPressed: _importFile,
            ),
          ]),
        ]),
      ),
    );
  }

  void _showFolderManager(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text('Local Source Folders',
                style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 12),
            if (_folders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('No folders added', style: GoogleFonts.manrope(fontSize: 13, color: cs.outline)),
              ),
            ..._folders.map((f) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(Icons.folder_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(f,
                    style: GoogleFonts.manrope(fontSize: 12, color: cs.onSurface),
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.error),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _removeFolder(f);
                    setSheetState(() => _folders.remove(f));
                  },
                ),
              ]),
            )),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text('Add Folder', style: GoogleFonts.manrope(fontWeight: FontWeight.w600, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.primary,
                side: BorderSide(color: cs.primary.withAlpha(80)),
                padding: const EdgeInsets.symmetric(vertical: 10)),
              onPressed: () async {
                if (_warnIfFoldersUnsupported()) return;
                final path = await FilePicker.getDirectoryPath();
                if (path != null) {
                  await _service.addFolder(path);
                  _folders = await _service.getFolders();
                  setSheetState(() {});
                  _load();
                }
              },
            )),
          ]),
        ),
      ),
    );
  }
}

class _LocalMangaCard extends StatelessWidget {
  final LocalManga manga;
  final VoidCallback onTap;

  const _LocalMangaCard({required this.manga, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: Stack(fit: StackFit.expand, children: [
          // Cover
          if (manga.coverPath != null)
            Image.file(File(manga.coverPath!), fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Icon(Icons.image_rounded, color: cs.outline, size: 32)))
          else
            Container(
              color: cs.surfaceContainerHighest,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.book_rounded, color: cs.outline, size: 32),
                const SizedBox(height: 4),
                Text('${manga.chapters.length} ch',
                    style: GoogleFonts.manrope(fontSize: 10, color: cs.outline)),
              ]),
            ),
          // Gradient + title
          Positioned(bottom: 0, left: 0, right: 0, child: Container(
            height: 70,
            decoration: const BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xDD000000)])),
          )),
          Positioned(bottom: 8, left: 8, right: 8,
            child: Text(manga.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700,
                    color: Colors.white, height: 1.3,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 4)]))),
        ]),
      ),
    );
  }
}
