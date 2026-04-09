import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

enum ReadingMode { paginated, continuousScroll, webtoon }

class ReaderSettingsSheetWidget extends StatefulWidget {
  final ReadingMode currentMode;
  final ValueChanged<ReadingMode> onModeChanged;

  const ReaderSettingsSheetWidget({
    super.key,
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  State<ReaderSettingsSheetWidget> createState() =>
      _ReaderSettingsSheetWidgetState();
}

class _ReaderSettingsSheetWidgetState extends State<ReaderSettingsSheetWidget> {
  late ReadingMode _selectedMode;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.currentMode;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.7,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusLarge),
          ),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.outline.withAlpha(128),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Reader Settings',
              style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 12),
            // Reading Mode section
            Text(
              'READING MODE',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 12),
            _ReadingModeOption(
              icon: Icons.auto_stories_rounded,
              label: 'Paginated',
              description: 'Page-by-page navigation',
              isSelected: _selectedMode == ReadingMode.paginated,
              onTap: () {
                setState(() => _selectedMode = ReadingMode.paginated);
                widget.onModeChanged(ReadingMode.paginated);
              },
            ),
            const SizedBox(height: 8),
            _ReadingModeOption(
              icon: Icons.view_day_rounded,
              label: 'Continuous Scroll',
              description: 'Scroll through pages vertically',
              isSelected: _selectedMode == ReadingMode.continuousScroll,
              onTap: () {
                setState(
                    () => _selectedMode = ReadingMode.continuousScroll);
                widget.onModeChanged(ReadingMode.continuousScroll);
              },
            ),
            const SizedBox(height: 8),
            _ReadingModeOption(
              icon: Icons.view_agenda_rounded,
              label: 'Webtoon',
              description: 'Optimized for long-strip format',
              isSelected: _selectedMode == ReadingMode.webtoon,
              onTap: () {
                setState(() => _selectedMode = ReadingMode.webtoon);
                widget.onModeChanged(ReadingMode.webtoon);
              },
            ),
            const SizedBox(height: 20),
            // Display section
            Text(
              'DISPLAY',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 12),
            _SettingToggle(
              icon: Icons.brightness_high_rounded,
              label: 'Keep Screen On',
              subtitle: 'Prevent screen from sleeping',
              initialValue: true,
              onChanged: (_) {},
            ),
            _SettingToggle(
              icon: Icons.numbers_rounded,
              label: 'Show Page Number',
              subtitle: 'Display page indicator',
              initialValue: true,
              onChanged: (_) {},
            ),
            _SettingToggle(
              icon: Icons.fullscreen_rounded,
              label: 'Fullscreen',
              subtitle: 'Hide system bars',
              initialValue: true,
              onChanged: (_) {},
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reading Mode Option ──────────────────────────────────────
class _ReadingModeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const _ReadingModeOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primary.withAlpha(26)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: isSelected ? cs.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? cs.primary.withAlpha(38)
                    : cs.surface,
                borderRadius:
                    BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Icon(
                icon,
                size: 18,
                color: isSelected ? cs.primary : cs.outline,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  Text(
                    description,
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      color: cs.outline,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded,
                  size: 20, color: cs.primary),
          ],
        ),
      ),
    );
  }
}

// ── Setting Toggle ───────────────────────────────────────────
class _SettingToggle extends StatefulWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool initialValue;
  final ValueChanged<bool> onChanged;

  const _SettingToggle({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_SettingToggle> createState() => _SettingToggleState();
}

class _SettingToggleState extends State<_SettingToggle> {
  late bool _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(widget.icon, size: 18, color: cs.outline),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                Text(
                  widget.subtitle,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: cs.outline,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _value,
            onChanged: (v) {
              setState(() => _value = v);
              widget.onChanged(v);
            },
            activeColor: cs.primary,
          ),
        ],
      ),
    );
  }
}
