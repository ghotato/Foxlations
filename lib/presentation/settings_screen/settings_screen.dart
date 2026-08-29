import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import './widgets/about_settings_page.dart';
import './widgets/library_settings_page.dart';
import './widgets/reader_settings_page.dart';
import './widgets/player_settings_page.dart';
import './widgets/downloads_settings_page.dart';
import './widgets/browse_settings_page.dart';
import './widgets/appearance_settings_page.dart';
import './widgets/notifications_settings_page.dart';
import './widgets/security_settings_page.dart';
import './widgets/advanced_settings_page.dart';
import './widgets/tracking_settings_page.dart';
import './widgets/ai_settings_page.dart';
import './widgets/backup_settings_page.dart';
import '../repoforge_hub_screen/repoforge_hub_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: cs.onSurface,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
      body: ListView(
        // Pad the bottom by the device's system-bar inset (gesture pill / 3-button
        // bar / none — reported per-phone by the OS) so the last rows clear the
        // Android navigation bar instead of scrolling under it.
        padding: EdgeInsets.only(
          top: 12,
          bottom: 12 + MediaQuery.of(context).viewPadding.bottom,
        ),
        children: [
          _SettingsSectionHeader(title: 'App'),
          _SettingsNavTile(
            icon: Icons.palette_rounded,
            iconColor: const Color(0xFFFF7A5C),
            iconBg: isDark
                ? const Color(0xFF3D1A10)
                : const Color(0xFFFFEDE8),
            title: 'Appearance',
            subtitle: 'Theme, dark mode, display',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AppearanceSettingsPage())),
          ),
          _SettingsNavTile(
            icon: Icons.notifications_rounded,
            iconColor: const Color(0xFFEF4444),
            iconBg: isDark
                ? const Color(0xFF2E0A0A)
                : const Color(0xFFFFEEEE),
            title: 'Notifications',
            subtitle: 'Push alerts, frequency, reminders',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const NotificationsSettingsPage())),
          ),
          _SettingsNavTile(
            icon: Icons.storage_rounded,
            iconColor: const Color(0xFF06B6D4),
            iconBg: isDark
                ? const Color(0xFF052028)
                : const Color(0xFFE0F9FF),
            title: 'Storage',
            subtitle: 'Downloads, folder locations, sync',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DownloadsSettingsPage())),
          ),
          const SizedBox(height: 8),
          _SettingsSectionHeader(title: 'Manga'),
          _SettingsNavTile(
            icon: Icons.library_books_rounded,
            iconColor: cs.primary,
            iconBg: cs.primary.withAlpha(25),
            title: 'Library',
            subtitle: 'Categories, global update, display',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const LibrarySettingsPage())),
          ),
          _SettingsNavTile(
            icon: Icons.menu_book_rounded,
            iconColor: const Color(0xFF4CAF82),
            iconBg: isDark
                ? const Color(0xFF0D2E1E)
                : const Color(0xFFE6F7EF),
            title: 'Reader',
            subtitle: 'Reading mode, display, navigation',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ReaderSettingsPage())),
          ),
          _SettingsNavTile(
            icon: Icons.play_circle_outline_rounded,
            iconColor: const Color(0xFFE0554A),
            iconBg: isDark
                ? const Color(0xFF3D1A10)
                : const Color(0xFFFFEDE8),
            title: 'Player',
            subtitle: 'Seek, gestures, speed, autoplay',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PlayerSettingsPage())),
          ),
          _SettingsNavTile(
            icon: Icons.download_rounded,
            iconColor: const Color(0xFF7C6FF7),
            iconBg: isDark
                ? const Color(0xFF1A1640)
                : const Color(0xFFEEEDFF),
            title: 'Downloads',
            subtitle: 'Automatic downloads, delete chapters',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DownloadsSettingsPage())),
          ),
          _SettingsNavTile(
            icon: Icons.track_changes_rounded,
            iconColor: const Color(0xFF2E51A2),
            iconBg: isDark
                ? const Color(0xFF0A1228)
                : const Color(0xFFE8EDFF),
            title: 'Tracking',
            subtitle: 'MAL, AniList, Kitsu, and more',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const TrackingSettingsPage())),
          ),
          _SettingsNavTile(
            icon: Icons.translate_rounded,
            iconColor: const Color(0xFF7C6FF7),
            iconBg: isDark
                ? const Color(0xFF1A1530)
                : const Color(0xFFF0EDFF),
            title: 'AI & Translation',
            subtitle: 'Provider, API keys, speech bubble detection',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AiSettingsPage())),
          ),
          _SettingsNavTile(
            icon: Icons.explore_rounded,
            iconColor: const Color(0xFFF59E0B),
            iconBg: isDark
                ? const Color(0xFF2E2005)
                : const Color(0xFFFFF3D6),
            title: 'Browse',
            subtitle: 'Sources, extensions, global search',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BrowseSettingsPage())),
          ),
          _SettingsNavTile(
            icon: Icons.auto_fix_high_rounded,
            iconColor: const Color(0xFFE0567B),
            iconBg: isDark
                ? const Color(0xFF2E0A16)
                : const Color(0xFFFFE4EC),
            title: 'RepoForge',
            subtitle: 'Build & manage sources from any URL',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RepoForgeHubScreen())),
          ),
          const SizedBox(height: 8),
          _SettingsSectionHeader(title: 'System'),
          _SettingsNavTile(
            icon: Icons.backup_rounded,
            iconColor: const Color(0xFF16A085),
            iconBg: isDark
                ? const Color(0xFF06231D)
                : const Color(0xFFE2F5EF),
            title: 'Backup & Restore',
            subtitle: 'Create/restore backups, Tachiyomi/Mihon, auto-backup',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BackupSettingsPage())),
          ),
          _SettingsNavTile(
            icon: Icons.security_rounded,
            iconColor: const Color(0xFF5865F2),
            iconBg: isDark
                ? const Color(0xFF10143A)
                : const Color(0xFFEEEFFF),
            title: 'Security & Privacy',
            subtitle: 'App lock, biometrics, screen security',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SecuritySettingsPage())),
          ),
          _SettingsNavTile(
            icon: Icons.settings_applications_rounded,
            iconColor: isDark ? cs.outline : const Color(0xFF6B7280),
            iconBg: isDark
                ? cs.surfaceContainerHighest
                : const Color(0xFFF0F0F8),
            title: 'Advanced',
            subtitle: 'Network, extensions, logging, data',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AdvancedSettingsPage())),
          ),
          _SettingsNavTile(
            icon: Icons.info_rounded,
            iconColor: const Color(0xFF4CAF82),
            iconBg: isDark
                ? const Color(0xFF0D2E1E)
                : const Color(0xFFE6F7EF),
            title: 'About',
            subtitle: 'Version, licenses, links',
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AboutSettingsPage())),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

}

// ── Section Header ──────────────────────────────────────────
class _SettingsSectionHeader extends StatelessWidget {
  final String title;
  const _SettingsSectionHeader({required this.title});

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
          letterSpacing: 1.2,
          color: cs.primary,
        ),
      ),
    );
  }
}

// ── Settings Nav Tile ────────────────────────────────────────
class _SettingsNavTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsNavTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: cs.outline,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.outline, size: 20),
          ],
        ),
      ),
    );
  }
}
