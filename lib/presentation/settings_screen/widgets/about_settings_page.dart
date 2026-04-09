import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

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
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: cs.onSurface, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'About',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          // App hero card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(26),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.menu_book_rounded,
                    size: 36,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Manga Reader',
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 1.0.0 (Build 1)',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: cs.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionHeader(title: 'App'),
          _ActionTile(
            icon: Icons.new_releases_rounded,
            iconColor: cs.primary,
            iconBg: isDark
                ? const Color(0xFF3D1A10)
                : const Color(0xFFFFEDE8),
            title: "What's New",
            subtitle: 'Changelog and release notes',
            onTap: () => _showChangelog(context),
          ),
          _ActionTile(
            icon: Icons.system_update_rounded,
            iconColor: AppTheme.success,
            iconBg: isDark
                ? const Color(0xFF0D2E1E)
                : const Color(0xFFE6F7EF),
            title: 'Check for Updates',
            subtitle: 'You are on the latest version',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Already on the latest version',
                    style: GoogleFonts.manrope(fontSize: 13),
                  ),
                  backgroundColor: cs.surfaceContainerHighest,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Legal'),
          _ActionTile(
            icon: Icons.description_rounded,
            iconColor: AppTheme.secondary,
            iconBg: isDark
                ? const Color(0xFF1A1640)
                : const Color(0xFFEEEDFF),
            title: 'Licenses',
            subtitle: 'Open source licenses',
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Manga Reader',
              applicationVersion: '1.0.0',
            ),
          ),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Links'),
          _ActionTile(
            icon: Icons.code_rounded,
            iconColor: cs.outline,
            iconBg: cs.surfaceContainerHighest,
            title: 'Source Code',
            subtitle: 'View on GitHub',
            onTap: () {},
          ),
          _ActionTile(
            icon: Icons.bug_report_rounded,
            iconColor: AppTheme.error,
            iconBg: isDark
                ? const Color(0xFF2E0A0A)
                : const Color(0xFFFFEEEE),
            title: 'Report a Bug',
            subtitle: 'File an issue',
            onTap: () {},
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showChangelog(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        title: Text(
          "What's New in v1.0.0",
          style: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ChangelogItem('Initial release'),
            _ChangelogItem('Extension system with Dart & JS support'),
            _ChangelogItem('Multiple reading modes'),
            _ChangelogItem('Library management'),
            _ChangelogItem('Source browsing and installation'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangelogItem extends StatelessWidget {
  final String text;
  const _ChangelogItem(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6, right: 10),
            decoration: BoxDecoration(
              color: cs.primary,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: cs.onSurface,
              ),
            ),
          ),
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

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
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
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 12,
                      color: cs.outline,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: cs.outline, size: 20),
          ],
        ),
      ),
    );
  }
}
