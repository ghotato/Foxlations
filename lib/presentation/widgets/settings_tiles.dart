import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class SettingsSectionHeader extends StatelessWidget {
  final String title;
  const SettingsSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(title.toUpperCase(), style: GoogleFonts.manrope(
          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: cs.primary)),
    );
  }
}

class SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const SettingsSwitchTile({
    super.key,
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle,
    required this.value, required this.onChanged,
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
      child: Row(children: [
        Container(width: 36, height: 36,
          decoration: BoxDecoration(color: iconColor.withAlpha(25), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: iconColor, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
          Text(subtitle, style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
        ])),
        Switch(value: value, onChanged: onChanged,
            activeThumbColor: cs.onPrimary, activeTrackColor: cs.primary),
      ]),
    );
  }
}

class SettingsNavTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const SettingsNavTile({
    super.key,
    required this.icon, required this.iconColor,
    required this.title, required this.subtitle, required this.onTap,
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
        child: Row(children: [
          Container(width: 36, height: 36,
            decoration: BoxDecoration(color: iconColor.withAlpha(25), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
            Text(subtitle, style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
          ])),
          Icon(Icons.chevron_right_rounded, color: cs.outline, size: 20),
        ]),
      ),
    );
  }
}
