import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class TrackingSettingsPage extends StatelessWidget {
  const TrackingSettingsPage({super.key});

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
        title: Text('Tracking',
            style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(title: 'Services'),
          _TrackerTile(name: 'MyAnimeList', icon: Icons.list_alt_rounded,
              color: const Color(0xFF2E51A2), isConnected: false),
          _TrackerTile(name: 'AniList', icon: Icons.auto_graph_rounded,
              color: const Color(0xFF02A9FF), isConnected: false),
          _TrackerTile(name: 'Kitsu', icon: Icons.pets_rounded,
              color: const Color(0xFFF75239), isConnected: false),
          _TrackerTile(name: 'MangaUpdates', icon: Icons.update_rounded,
              color: const Color(0xFFF57C25), isConnected: false),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Connect a tracking service to sync your reading progress across devices and platforms.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 12, color: cs.outline, height: 1.5)),
          ),
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

class _TrackerTile extends StatelessWidget {
  final String name; final IconData icon; final Color color; final bool isConnected;
  const _TrackerTile({required this.name, required this.icon, required this.color, required this.isConnected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: cs.outlineVariant)),
      child: Row(children: [
        Container(width: 44, height: 44,
            decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(isConnected ? 'Connected' : 'Not connected',
              style: GoogleFonts.manrope(fontSize: 12,
                  color: isConnected ? AppTheme.success : cs.outline)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isConnected ? AppTheme.error.withAlpha(26) : cs.primary.withAlpha(26),
            borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            border: Border.all(color: isConnected ? AppTheme.error : cs.primary, width: 1)),
          child: Text(isConnected ? 'Disconnect' : 'Connect',
              style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700,
                  color: isConnected ? AppTheme.error : cs.primary)),
        ),
      ]),
    );
  }
}
