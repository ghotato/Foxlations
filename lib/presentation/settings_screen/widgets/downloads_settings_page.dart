import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/providers/download_provider.dart';
import '../../../core/services/download_service.dart';
import '../../../theme/app_theme.dart';

class DownloadsSettingsPage extends StatefulWidget {
  const DownloadsSettingsPage({super.key});

  @override
  State<DownloadsSettingsPage> createState() => _DownloadsSettingsPageState();
}

class _DownloadsSettingsPageState extends State<DownloadsSettingsPage> {
  int _rebuildKey = 0;

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
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Downloads',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
      body: Consumer<DownloadProvider>(
        builder: (_, dl, __) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _SectionHeader(title: 'Automatic Downloads'),
            _SwitchTile(
              icon: Icons.download_rounded,
              iconColor: cs.primary,
              title: 'Download New Chapters',
              subtitle: 'Automatically download new chapters',
              value: dl.autoDownload,
              onChanged: (v) => dl.saveSetting('dl_auto', v),
            ),
            _SwitchTile(
              icon: Icons.wifi_rounded,
              iconColor: cs.primary,
              title: 'Wi-Fi Only',
              subtitle: 'Only download on Wi-Fi',
              value: dl.wifiOnly,
              onChanged: (v) => dl.saveSetting('dl_wifi_only', v),
            ),
            const SizedBox(height: 8),
            _SectionHeader(title: 'Delete Downloaded Chapters'),
            _SwitchTile(
              icon: Icons.auto_delete_rounded,
              iconColor: AppTheme.secondary,
              title: 'After Reading',
              subtitle: 'Delete chapters after they are read',
              value: dl.deleteAfterRead,
              onChanged: (v) => dl.saveSetting('dl_delete_after_read', v),
            ),
            const SizedBox(height: 8),
            _SectionHeader(title: 'Format'),
            _SwitchTile(
              icon: Icons.archive_rounded,
              iconColor: AppTheme.secondary,
              title: 'Save as CBZ',
              subtitle: 'Archive chapters as CBZ files with metadata',
              value: dl.saveAsCbz,
              onChanged: (v) => dl.saveSetting('dl_save_cbz', v),
            ),
            const SizedBox(height: 8),
            _SectionHeader(title: 'Download Location'),
            FutureBuilder<List<String>>(
              key: ValueKey(_rebuildKey),
              future: Future.wait([
                DownloadService().getDownloadPathSetting(),
                DownloadService().getBasePath(),
              ]),
              builder: (ctx, snap) {
                final custom = snap.data?[0] ?? '';
                final current = snap.data?[1] ?? '...';
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: cs.primary.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.folder_rounded, color: cs.primary, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(custom.isEmpty ? 'Default Location' : 'Custom Location',
                              style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                          Text(current, style: GoogleFonts.manrope(fontSize: 11, color: cs.outline),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      )),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: OutlinedButton.icon(
                        icon: const Icon(Icons.folder_open_rounded, size: 16),
                        label: Text('Choose Folder', style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cs.primary,
                          side: BorderSide(color: cs.primary.withAlpha(80)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        onPressed: () async {
                          final path = await FilePicker.getDirectoryPath();
                          if (path != null) {
                            await DownloadService().setDownloadPath(path);
                            setState(() => _rebuildKey++);
                          }
                        },
                      )),
                      if (custom.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        OutlinedButton(
                          child: Text('Reset', style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w600)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cs.outline,
                            side: BorderSide(color: cs.outlineVariant),
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          ),
                          onPressed: () async {
                            await DownloadService().clearDownloadPath();
                            setState(() => _rebuildKey++);
                          },
                        ),
                      ],
                    ]),
                  ]),
                );
              },
            ),
            const SizedBox(height: 8),
            _SectionHeader(title: 'Storage'),
            FutureBuilder<List<int>>(
              future: Future.wait([
                DownloadService().getTotalSize(isVault: false),
                DownloadService().getTotalSize(isVault: true),
              ]),
              builder: (_, snap) {
                final libBytes = snap.data?[0] ?? 0;
                final vaultBytes = snap.data?[1] ?? 0;
                final libMb = (libBytes / (1024 * 1024)).toStringAsFixed(1);
                final vaultMb = (vaultBytes / (1024 * 1024)).toStringAsFixed(1);
                final totalMb = ((libBytes + vaultBytes) / (1024 * 1024)).toStringAsFixed(1);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Total: $totalMb MB', style: GoogleFonts.manrope(fontSize: 13, color: cs.onSurface, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('Library: $libMb MB  |  Vault: $vaultMb MB',
                        style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
                  ]),
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                Text(subtitle,
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: cs.outline)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: cs.onPrimary,
            activeTrackColor: cs.primary,
          ),
        ],
      ),
    );
  }
}
