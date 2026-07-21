import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/library_provider.dart';
import '../../../core/providers/source_provider.dart';
import '../../../core/services/backup_service.dart';
import '../../../theme/app_theme.dart';

class BackupSettingsPage extends StatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  State<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends State<BackupSettingsPage> {
  final _service = BackupService();
  List<BackupFile> _backups = [];
  BackupFrequency _frequency = BackupFrequency.off;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final backups = await _service.listBackups();
    final freq = await _service.getFrequency();
    if (mounted) {
      setState(() {
        _backups = backups;
        _frequency = freq;
      });
    }
  }

  Future<void> _run(Future<String> Function() action, String verb) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) AppTheme.showSnackBar(context, '$verb complete');
    } catch (e) {
      if (mounted) AppTheme.showSnackBar(context, '$verb failed: $e');
    }
    if (mounted) setState(() => _busy = false);
    await _refresh();
  }

  Future<void> _restoreFrom({required bool tachiyomi}) async {
    final res = await FilePicker.pickFiles(type: FileType.any);
    final path = res?.files.single.path;
    if (path == null) return;
    await _restorePath(path, tachiyomi: tachiyomi);
  }

  Future<void> _restorePath(String path, {required bool tachiyomi}) async {
    setState(() => _busy = true);
    try {
      if (tachiyomi) {
        final ids = context
            .read<SourceProvider>()
            .installedSources
            .map((s) => s.source.id)
            .toList();
        final n = await _service.restoreTachiyomiBackup(path,
            installedSourceIds: ids);
        if (mounted) AppTheme.showSnackBar(context, 'Imported $n manga');
      } else {
        await _service.restoreBackup(path);
        if (mounted) AppTheme.showSnackBar(context, 'Restore complete');
      }
      if (mounted) {
        await context.read<LibraryProvider>().reload();
        await context.read<SourceProvider>().refreshRepos();
      }
    } catch (e) {
      if (mounted) AppTheme.showSnackBar(context, 'Restore failed: $e');
    }
    if (mounted) setState(() => _busy = false);
    await _refresh();
  }

  Future<void> _pickFrequency() async {
    final choice = await showModalBottomSheet<BackupFrequency>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final f in BackupFrequency.values)
            RadioListTile<BackupFrequency>(
              value: f,
              groupValue: _frequency,
              onChanged: (v) => Navigator.pop(context, v),
              title: Text(_freqLabel(f)),
            ),
        ]),
      ),
    );
    if (choice != null) {
      await _service.setFrequency(choice);
      await _refresh();
    }
  }

  String _freqLabel(BackupFrequency f) {
    switch (f) {
      case BackupFrequency.off:
        return 'Off';
      case BackupFrequency.daily:
        return 'Daily';
      case BackupFrequency.weekly:
        return 'Weekly';
      case BackupFrequency.monthly:
        return 'Monthly';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded,
                color: cs.onSurface, size: 20),
            onPressed: () => Navigator.pop(context)),
        title: Text('Backup & Restore',
            style: GoogleFonts.manrope(
                fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
      ),
      body: Stack(children: [
        ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
          _header('Foxlations backup', cs),
          _action(Icons.save_rounded, 'Create backup',
              'Save your library, categories, read progress, sources and tracking',
              cs, () => _run(_service.createBackup, 'Backup')),
          _action(Icons.restore_rounded, 'Restore backup',
              'Restore from a Foxlations .fxbackup file', cs,
              () => _restoreFrom(tachiyomi: false)),
          _header('Tachiyomi / Mihon & forks', cs),
          _action(Icons.ios_share_rounded, 'Create compatible backup',
              'Export a .tachibk you can import into Tachiyomi, Mihon and forks',
              cs, () => _run(_service.createTachiyomiBackup, 'Export')),
          _action(Icons.download_rounded, 'Restore from Tachiyomi/Mihon',
              'Import a .tachibk / .tmb / .proto.gz backup (matches sources by name)',
              cs, () => _restoreFrom(tachiyomi: true)),
          _header('Automatic backup', cs),
          ListTile(
            leading: _iconBox(Icons.schedule_rounded, cs),
            title: Text('Frequency',
                style: GoogleFonts.manrope(
                    fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text('Auto-create a backup ${_freqLabel(_frequency).toLowerCase()}',
                style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
            trailing: Text(_freqLabel(_frequency),
                style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700, color: cs.primary)),
            onTap: _pickFrequency,
          ),
          _header('Backups (${_backups.length})', cs),
          if (_backups.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Text('No backups yet.',
                  style: GoogleFonts.manrope(fontSize: 12.5, color: cs.outline)),
            )
          else
            ..._backups.map((b) => _backupRow(b, cs)),
          const SizedBox(height: 24),
        ]),
        if (_busy)
          Container(
            color: Colors.black26,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ]),
    );
  }

  Widget _header(String t, ColorScheme cs) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(t.toUpperCase(),
            style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: cs.primary)),
      );

  Widget _iconBox(IconData icon, ColorScheme cs) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: cs.primary.withAlpha(25),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: cs.primary, size: 20),
      );

  Widget _action(IconData icon, String title, String subtitle, ColorScheme cs,
          VoidCallback onTap) =>
      ListTile(
        leading: _iconBox(icon, cs),
        title: Text(title,
            style:
                GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
        onTap: _busy ? null : onTap,
      );

  Widget _backupRow(BackupFile b, ColorScheme cs) {
    final kb = (b.sizeBytes / 1024).toStringAsFixed(0);
    return ListTile(
      leading: Icon(
        b.isTachiyomi ? Icons.swap_horiz_rounded : Icons.archive_rounded,
        color: b.isAuto ? cs.outline : cs.primary,
      ),
      title: Text(b.name,
          style: GoogleFonts.manrope(
              fontSize: 13.5, fontWeight: FontWeight.w600)),
      subtitle: Text(
        '${b.isTachiyomi ? 'Tachiyomi/Mihon' : 'Foxlations'}'
        '${b.isAuto ? ' · auto' : ''} · ${kb} KB',
        style: GoogleFonts.manrope(fontSize: 11.5, color: cs.outline),
      ),
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert_rounded, color: cs.outline),
        onSelected: (v) {
          if (v == 'restore') {
            _restorePath(b.path, tachiyomi: b.isTachiyomi);
          } else if (v == 'delete') {
            _service.deleteBackup(b.path).then((_) => _refresh());
          }
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'restore', child: Text('Restore')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}
