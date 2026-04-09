import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class NotificationsSettingsPage extends StatefulWidget {
  const NotificationsSettingsPage({super.key});

  @override
  State<NotificationsSettingsPage> createState() => _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState extends State<NotificationsSettingsPage> {
  bool _newChapters = true;
  bool _downloadComplete = true;
  bool _downloadError = true;
  bool _libraryUpdate = false;
  bool _sound = true;
  bool _vibration = true;
  bool _groupNotifications = true;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface, elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: cs.onSurface, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: Text('Notifications',
            style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(title: 'Chapter Updates'),
          _SwitchTile(icon: Icons.new_releases_rounded, iconColor: cs.primary,
              title: 'New Chapters', subtitle: 'Notify when new chapters are available',
              value: _newChapters, onChanged: (v) => setState(() => _newChapters = v)),
          _SwitchTile(icon: Icons.update_rounded, iconColor: cs.primary,
              title: 'Library Updates', subtitle: 'Notify after library update completes',
              value: _libraryUpdate, onChanged: (v) => setState(() => _libraryUpdate = v)),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Downloads'),
          _SwitchTile(icon: Icons.download_done_rounded, iconColor: AppTheme.success,
              title: 'Download Complete', subtitle: 'Notify when chapters finish downloading',
              value: _downloadComplete, onChanged: (v) => setState(() => _downloadComplete = v)),
          _SwitchTile(icon: Icons.error_outline_rounded, iconColor: AppTheme.error,
              title: 'Download Error', subtitle: 'Notify when a download fails',
              value: _downloadError, onChanged: (v) => setState(() => _downloadError = v)),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Behavior'),
          _SwitchTile(icon: Icons.volume_up_rounded, iconColor: AppTheme.secondary,
              title: 'Sound', subtitle: 'Play sound for notifications',
              value: _sound, onChanged: (v) => setState(() => _sound = v)),
          _SwitchTile(icon: Icons.vibration_rounded, iconColor: AppTheme.secondary,
              title: 'Vibration', subtitle: 'Vibrate for notifications',
              value: _vibration, onChanged: (v) => setState(() => _vibration = v)),
          _SwitchTile(icon: Icons.groups_rounded, iconColor: AppTheme.secondary,
              title: 'Group Notifications', subtitle: 'Combine multiple notifications',
              value: _groupNotifications, onChanged: (v) => setState(() => _groupNotifications = v)),
          const SizedBox(height: 24),
        ],
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
      child: Text(title.toUpperCase(),
          style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: cs.primary)),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon; final Color iconColor; final String title; final String subtitle;
  final bool value; final ValueChanged<bool> onChanged;
  const _SwitchTile({required this.icon, required this.iconColor, required this.title,
      required this.subtitle, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: cs.outlineVariant)),
      child: Row(children: [
        Container(width: 36, height: 36,
            decoration: BoxDecoration(color: iconColor.withAlpha(25), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
          Text(subtitle, style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
        ])),
        Switch(value: value, onChanged: onChanged, activeThumbColor: cs.onPrimary, activeTrackColor: cs.primary),
      ]),
    );
  }
}
