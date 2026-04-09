import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class ReaderSettingsPage extends StatefulWidget {
  const ReaderSettingsPage({super.key});
  @override
  State<ReaderSettingsPage> createState() => _ReaderSettingsPageState();
}

class _ReaderSettingsPageState extends State<ReaderSettingsPage> {
  String _readingMode = 'Paginated';
  String _scaleType = 'Fit Screen';
  String _zoomStart = 'Automatic';
  String _navLayout = 'Right & Left';
  String _bgColor = 'Black';
  String _pageTransition = 'Slide';
  bool _keepScreenOn = true;
  bool _showPageNumber = true;
  bool _fullscreen = true;
  bool _cropBorders = false;
  bool _grayscale = false;
  bool _invertColors = false;
  bool _invertTapZones = false;
  bool _volumeKeys = false;
  bool _autoPreload = true;
  double _fontSize = 16.0;
  double _imageZoom = 1.0;

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
        title: Text('Reader',
            style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(title: 'Preferences'),
          _SegmentedTile(icon: Icons.auto_stories_rounded, iconColor: cs.primary,
              title: 'Reading Mode',
              options: const ['Paginated', 'Scroll', 'Webtoon', 'LTR', 'RTL'],
              selected: _readingMode,
              onChanged: (v) => setState(() => _readingMode = v)),
          _SliderTile(icon: Icons.text_fields_rounded, iconColor: cs.primary,
              title: 'Font Size', value: _fontSize, min: 10, max: 24, divisions: 14,
              onChanged: (v) => setState(() => _fontSize = v)),
          _SliderTile(icon: Icons.zoom_in_rounded, iconColor: cs.primary,
              title: 'Image Zoom', value: _imageZoom, min: 1.0, max: 3.0, divisions: 20,
              onChanged: (v) => setState(() => _imageZoom = v)),
          _SwitchTile(icon: Icons.skip_next_rounded, iconColor: cs.primary,
              title: 'Auto-Preload Next Chapter', subtitle: 'Load next chapter in background',
              value: _autoPreload, onChanged: (v) => setState(() => _autoPreload = v)),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Reading Mode'),
          _SwitchTile(icon: Icons.crop_rounded, iconColor: cs.primary,
              title: 'Crop Borders', subtitle: 'Remove white borders from pages',
              value: _cropBorders, onChanged: (v) => setState(() => _cropBorders = v)),
          _SwitchTile(icon: Icons.filter_b_and_w_rounded, iconColor: cs.primary,
              title: 'Grayscale', subtitle: 'Display pages in grayscale',
              value: _grayscale, onChanged: (v) => setState(() => _grayscale = v)),
          _SwitchTile(icon: Icons.invert_colors_rounded, iconColor: cs.primary,
              title: 'Invert Colors', subtitle: 'Swap light and dark colors',
              value: _invertColors, onChanged: (v) => setState(() => _invertColors = v)),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Display'),
          _ChoiceTile(icon: Icons.aspect_ratio_rounded, iconColor: AppTheme.success,
              title: 'Scale Type', value: _scaleType,
              options: const ['Fit Screen', 'Stretch', 'Fit Width', 'Fit Height', 'Original Size', 'Smart Fit'],
              onChanged: (v) => setState(() => _scaleType = v)),
          _ChoiceTile(icon: Icons.zoom_out_map_rounded, iconColor: AppTheme.success,
              title: 'Zoom Start Position', value: _zoomStart,
              options: const ['Automatic', 'Left', 'Right', 'Center'],
              onChanged: (v) => setState(() => _zoomStart = v)),
          _ChoiceTile(icon: Icons.format_color_fill_rounded, iconColor: AppTheme.success,
              title: 'Background Color', value: _bgColor,
              options: const ['Black', 'Gray', 'White', 'Automatic'],
              onChanged: (v) => setState(() => _bgColor = v)),
          _SwitchTile(icon: Icons.brightness_high_rounded, iconColor: AppTheme.success,
              title: 'Keep Screen On', subtitle: 'Prevent screen from sleeping',
              value: _keepScreenOn, onChanged: (v) => setState(() => _keepScreenOn = v)),
          _SwitchTile(icon: Icons.numbers_rounded, iconColor: AppTheme.success,
              title: 'Show Page Number', subtitle: 'Display page indicator overlay',
              value: _showPageNumber, onChanged: (v) => setState(() => _showPageNumber = v)),
          _SwitchTile(icon: Icons.fullscreen_rounded, iconColor: AppTheme.success,
              title: 'Fullscreen', subtitle: 'Hide system bars while reading',
              value: _fullscreen, onChanged: (v) => setState(() => _fullscreen = v)),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Navigation'),
          _ChoiceTile(icon: Icons.touch_app_rounded, iconColor: AppTheme.secondary,
              title: 'Navigation Layout', value: _navLayout,
              options: const ['Right & Left', 'L-shaped', 'Kindle-like', 'Edge', 'Disabled'],
              onChanged: (v) => setState(() => _navLayout = v)),
          _SwitchTile(icon: Icons.swap_horiz_rounded, iconColor: AppTheme.secondary,
              title: 'Invert Tap Zones', subtitle: 'Swap left/right tap navigation',
              value: _invertTapZones, onChanged: (v) => setState(() => _invertTapZones = v)),
          _SwitchTile(icon: Icons.volume_up_rounded, iconColor: AppTheme.secondary,
              title: 'Volume Keys', subtitle: 'Use volume buttons to navigate pages',
              value: _volumeKeys, onChanged: (v) => setState(() => _volumeKeys = v)),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Transitions'),
          _ChoiceTile(icon: Icons.animation_rounded, iconColor: AppTheme.warning,
              title: 'Page Transition', value: _pageTransition,
              options: const ['Slide', 'Fade', 'None'],
              onChanged: (v) => setState(() => _pageTransition = v)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Shared Tile Widgets ──────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(title.toUpperCase(),
          style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: cs.primary)));
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

class _SegmentedTile extends StatelessWidget {
  final IconData icon; final Color iconColor; final String title;
  final List<String> options; final String selected; final ValueChanged<String> onChanged;
  const _SegmentedTile({required this.icon, required this.iconColor, required this.title,
      required this.options, required this.selected, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: cs.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(color: iconColor.withAlpha(25), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 18)),
          const SizedBox(width: 12),
          Text(title, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: options.map((opt) {
          final isSelected = opt == selected;
          return GestureDetector(
            onTap: () => onChanged(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? cs.primary : cs.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(color: isSelected ? cs.primary : cs.outlineVariant)),
              child: Text(opt, style: GoogleFonts.manrope(fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? cs.onPrimary : cs.onSurface)),
            ),
          );
        }).toList()),
      ]),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final IconData icon; final Color iconColor; final String title;
  final double value; final double min; final double max; final int? divisions;
  final ValueChanged<double> onChanged;
  const _SliderTile({required this.icon, required this.iconColor, required this.title,
      required this.value, required this.min, required this.max, this.divisions, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: cs.outlineVariant)),
      child: Column(children: [
        Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(color: iconColor.withAlpha(25), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: cs.primary.withAlpha(26), borderRadius: BorderRadius.circular(AppTheme.radiusFull)),
            child: Text(value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1),
                style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary))),
        ]),
        SliderTheme(
          data: SliderThemeData(activeTrackColor: cs.primary, inactiveTrackColor: cs.surface,
              thumbColor: cs.primary, overlayColor: cs.primary.withAlpha(26)),
          child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged)),
      ]),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final IconData icon; final Color iconColor; final String title; final String value;
  final List<String> options; final ValueChanged<String> onChanged;
  const _ChoiceTile({required this.icon, required this.iconColor, required this.title,
      required this.value, required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(context: context, backgroundColor: cs.surface,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge))),
          builder: (_) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text(title, style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
              Divider(color: cs.outlineVariant),
              ...options.map((opt) {
                final isSelected = opt == value;
                return InkWell(
                  onTap: () { onChanged(opt); Navigator.pop(context); },
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                        color: isSelected ? cs.primary.withAlpha(26) : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
                    child: Row(children: [
                      Expanded(child: Text(opt, style: GoogleFonts.manrope(
                          fontSize: 14, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: cs.onSurface))),
                      if (isSelected) Icon(Icons.check_rounded, size: 18, color: cs.primary),
                    ])));
              }),
            ])));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: cs.outlineVariant)),
        child: Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(color: iconColor.withAlpha(25), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface))),
          Text(value, style: GoogleFonts.manrope(fontSize: 13, color: cs.outline)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: cs.outline, size: 20),
        ])));
  }
}
