import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class StatusBadgeWidget extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final double fontSize;

  const StatusBadgeWidget({
    super.key,
    required this.label,
    required this.color,
    required this.textColor,
    this.fontSize = 10,
  });

  factory StatusBadgeWidget.fromStatus(String status) {
    final lower = status.toLowerCase();
    Color bg;
    Color text;
    switch (lower) {
      case 'reading':
        bg = AppTheme.success.withAlpha(38);
        text = AppTheme.success;
        break;
      case 'completed':
        bg = AppTheme.secondary.withAlpha(38);
        text = AppTheme.secondary;
        break;
      case 'on hold':
        bg = AppTheme.warning.withAlpha(38);
        text = AppTheme.warning;
        break;
      case 'dropped':
        bg = AppTheme.error.withAlpha(38);
        text = AppTheme.error;
        break;
      default:
        bg = AppTheme.mutedDark.withAlpha(38);
        text = AppTheme.mutedDark;
    }
    return StatusBadgeWidget(
      label: status.isEmpty ? 'Unknown' : status,
      color: bg,
      textColor: text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: textColor,
        ),
      ),
    );
  }
}

class UnreadCountBadge extends StatelessWidget {
  final int count;
  const UnreadCountBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(AppTheme.radiusFull),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: cs.onPrimary,
        ),
      ),
    );
  }
}
