import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/models/manga_model.dart';
import '../../../core/providers/library_provider.dart';
import '../../../core/providers/source_provider.dart';
import '../../../core/providers/vault_provider.dart';
import '../../../theme/app_theme.dart';
import '../../widgets/manga_image.dart';

/// Move individual titles (with their read progress) between the normal library
/// and the encrypted vault.
///
/// Only reachable once the vault is unlocked — moving requires the vault's Hive
/// boxes to be open, and the whole point is that locked content is unreadable.
class VaultContentsPage extends StatefulWidget {
  const VaultContentsPage({super.key});

  @override
  State<VaultContentsPage> createState() => _VaultContentsPageState();
}

class _VaultContentsPageState extends State<VaultContentsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // The three content types, resolved from each entry's source.
  static const _types = ['manga', 'anime', 'novel'];
  static const _labels = ['Manga', 'Anime', 'Novels'];
  int _typeIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (_tabs.index != _typeIndex) {
          setState(() => _typeIndex = _tabs.index);
        }
      });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// A title's content type comes from its source (LibraryManga has none of its
  /// own). Sources that are no longer installed default to manga.
  String _typeOf(BuildContext context, LibraryManga m) {
    final installed =
        context.read<SourceProvider>().getInstalledSource(m.sourceId);
    return installed?.source.itemType ?? 'manga';
  }

  Future<void> _toVault(
      BuildContext context, LibraryManga m) async {
    final lib = context.read<LibraryProvider>();
    final vault = context.read<VaultProvider>();
    final chapters = lib.fullChapters(m.sourceId, m.url);
    await vault.addEntryWithChapters(m, chapters);
    await lib.removeFromLibrary(m.sourceId, m.url);
    if (context.mounted) {
      AppTheme.showSnackBar(context, '"${m.title}" moved to vault');
    }
  }

  Future<void> _fromVault(
      BuildContext context, LibraryManga m) async {
    final lib = context.read<LibraryProvider>();
    final vault = context.read<VaultProvider>();
    final chapters = vault.fullChapters(m.sourceId, m.url);
    await lib.addEntryWithChapters(m, chapters);
    await vault.removeFromLibrary(m.sourceId, m.url);
    if (context.mounted) {
      AppTheme.showSnackBar(context, '"${m.title}" moved out of vault');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final vault = context.watch<VaultProvider>();
    final lib = context.watch<LibraryProvider>();

    // Guard: if the vault is locked, moving can't work — send the user back.
    if (vault.hasPassword && !vault.isUnlocked) {
      return Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          backgroundColor: cs.surface,
          title: Text('Vault Contents',
              style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w700, color: cs.onSurface)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Unlock the vault first to manage its contents.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 14, color: cs.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    final type = _types[_typeIndex];
    final inLibrary =
        lib.manga.where((m) => _typeOf(context, m) == type).toList()
          ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final inVault =
        vault.manga.where((m) => _typeOf(context, m) == type).toList()
          ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        title: Text('Vault Contents',
            style: GoogleFonts.manrope(
                fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
        bottom: TabBar(
          controller: _tabs,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          labelStyle:
              GoogleFonts.manrope(fontSize: 13.5, fontWeight: FontWeight.w700),
          tabs: [for (final l in _labels) Tab(text: l)],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _sectionHeader(cs, 'In your library', '→ move into vault'),
          if (inLibrary.isEmpty)
            _emptyRow(cs, 'No ${_labels[_typeIndex].toLowerCase()} in your library')
          else
            for (final m in inLibrary)
              _entryRow(
                cs,
                m,
                icon: Icons.lock_outline_rounded,
                tint: cs.primary,
                onTap: () => _toVault(context, m),
              ),
          const SizedBox(height: 12),
          _sectionHeader(cs, 'In the vault', '← move back out'),
          if (inVault.isEmpty)
            _emptyRow(cs, 'No ${_labels[_typeIndex].toLowerCase()} in the vault')
          else
            for (final m in inVault)
              _entryRow(
                cs,
                m,
                icon: Icons.lock_open_rounded,
                tint: cs.onSurfaceVariant,
                onTap: () => _fromVault(context, m),
              ),
        ],
      ),
    );
  }

  Widget _sectionHeader(ColorScheme cs, String title, String hint) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: GoogleFonts.manrope(
                    fontSize: 12,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w700,
                    color: cs.primary)),
            Text(hint,
                style: GoogleFonts.manrope(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
      );

  Widget _emptyRow(ColorScheme cs, String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text(text,
            style: GoogleFonts.manrope(fontSize: 13, color: cs.onSurfaceVariant)),
      );

  Widget _entryRow(
    ColorScheme cs,
    LibraryManga m, {
    required IconData icon,
    required Color tint,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 38,
          height: 52,
          child: MangaImage(imageUrl: m.coverUrl, fit: BoxFit.cover),
        ),
      ),
      title: Text(m.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.manrope(
              fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
      subtitle: Text('${m.readChapters}/${m.totalChapters} read',
          style: GoogleFonts.manrope(fontSize: 11.5, color: cs.onSurfaceVariant)),
      trailing: IconButton(
        icon: Icon(icon, color: tint),
        onPressed: onTap,
      ),
      onTap: onTap,
    );
  }
}
