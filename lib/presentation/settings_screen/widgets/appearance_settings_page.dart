import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../theme/app_theme.dart';
import 'vault_settings_page.dart';

// ── Theme Breed Data ─────────────────────────────────────────
class ThemeBreed {
  final String id;
  final String name;
  final String emoji;
  final String description;
  final Color primaryLight;
  final Color primaryDark;
  final Color accentLight;
  final Color accentDark;
  final Color backgroundLight;
  final Color backgroundDark;

  const ThemeBreed({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.primaryLight,
    required this.primaryDark,
    required this.accentLight,
    required this.accentDark,
    required this.backgroundLight,
    required this.backgroundDark,
  });
}

const List<ThemeBreed> kThemeBreeds = [
  ThemeBreed(
    id: 'red_fox',
    name: 'Red Fox',
    emoji: '🦊',
    description: 'Classic orange & white',
    primaryLight: Color(0xFFE85D4A),
    primaryDark: Color(0xFFFF7A5C),
    accentLight: Color(0xFFF59E0B),
    accentDark: Color(0xFFFFB830),
    backgroundLight: Color(0xFFFFF8F5),
    backgroundDark: Color(0xFF1A1008),
  ),
  ThemeBreed(
    id: 'arctic_fox',
    name: 'Arctic Fox',
    emoji: '🤍',
    description: 'Snow white & ice blue',
    primaryLight: Color(0xFF5B9BD5),
    primaryDark: Color(0xFF90C8F0),
    accentLight: Color(0xFF7EC8E3),
    accentDark: Color(0xFFAEDFF7),
    backgroundLight: Color(0xFFF5F8FF),
    backgroundDark: Color(0xFF0D1520),
  ),
  ThemeBreed(
    id: 'silver_fox',
    name: 'Silver Fox',
    emoji: '🩶',
    description: 'Sleek black & silver',
    primaryLight: Color(0xFF6B7280),
    primaryDark: Color(0xFFB0B8C8),
    accentLight: Color(0xFF9CA3AF),
    accentDark: Color(0xFFD1D5DB),
    backgroundLight: Color(0xFFF4F5F7),
    backgroundDark: Color(0xFF0F1117),
  ),
  ThemeBreed(
    id: 'marble_fox',
    name: 'Marble Fox',
    emoji: '🖤',
    description: 'Black & white contrast',
    primaryLight: Color(0xFF1F2937),
    primaryDark: Color(0xFFF9FAFB),
    accentLight: Color(0xFF374151),
    accentDark: Color(0xFFE5E7EB),
    backgroundLight: Color(0xFFF9FAFB),
    backgroundDark: Color(0xFF111827),
  ),
  ThemeBreed(
    id: 'cross_fox',
    name: 'Cross Fox',
    emoji: '🟤',
    description: 'Warm brown & amber',
    primaryLight: Color(0xFF92400E),
    primaryDark: Color(0xFFD97706),
    accentLight: Color(0xFFB45309),
    accentDark: Color(0xFFF59E0B),
    backgroundLight: Color(0xFFFFFBF5),
    backgroundDark: Color(0xFF1C1208),
  ),
  ThemeBreed(
    id: 'fennec_fox',
    name: 'Fennec Fox',
    emoji: '🏜️',
    description: 'Sandy desert tones',
    primaryLight: Color(0xFFD4A574),
    primaryDark: Color(0xFFE8C49A),
    accentLight: Color(0xFFC8956C),
    accentDark: Color(0xFFDDB88A),
    backgroundLight: Color(0xFFFDF8F0),
    backgroundDark: Color(0xFF1A1508),
  ),
  ThemeBreed(
    id: 'digi_fox',
    name: 'Digi Fox',
    emoji: '💜',
    description: 'Digital purple & violet',
    primaryLight: Color(0xFF7C3AED),
    primaryDark: Color(0xFF9D5CF6),
    accentLight: Color(0xFFA855F7),
    accentDark: Color(0xFFC084FC),
    backgroundLight: Color(0xFFF5F0FF),
    backgroundDark: Color(0xFF0F0A1A),
  ),
];

// ── Appearance Settings Page ─────────────────────────────────
class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  State<AppearanceSettingsPage> createState() =>
      _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  String _selectedBreedId = 'red_fox';
  int _digiFoxTapCount = 0;
  DateTime _lastDigiFoxTap = DateTime(2000);

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    setState(() {
      _selectedBreedId = context.read<ThemeProvider>().breedId;
    });
  }

  ThemeBreed get _currentBreed => kThemeBreeds.firstWhere(
        (b) => b.id == _selectedBreedId,
        orElse: () => kThemeBreeds.first,
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeProvider = context.watch<ThemeProvider>();
    final primaryColor =
        isDark ? _currentBreed.primaryDark : _currentBreed.primaryLight;

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
          'Appearance',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(title: 'Theme'),
          ...kThemeBreeds.map((breed) {
            final isSelected = breed.id == _selectedBreedId;
            final previewPrimary =
                isDark ? breed.primaryDark : breed.primaryLight;
            final previewAccent =
                isDark ? breed.accentDark : breed.accentLight;
            final previewBg =
                isDark ? breed.backgroundDark : breed.backgroundLight;
            return _BreedTile(
              breed: breed,
              isSelected: isSelected,
              previewPrimary: previewPrimary,
              previewAccent: previewAccent,
              previewBg: previewBg,
              primaryColor: primaryColor,
              onTap: () async {
                HapticFeedback.selectionClick();
                setState(() => _selectedBreedId = breed.id);
                context.read<ThemeProvider>().setBreed(breed.id);

                // Secret: tap Digi Fox 9 times to open vault settings
                if (breed.id == 'digi_fox') {
                  final now = DateTime.now();
                  if (now.difference(_lastDigiFoxTap).inMilliseconds < 600) {
                    _digiFoxTapCount++;
                  } else {
                    _digiFoxTapCount = 1;
                  }
                  _lastDigiFoxTap = now;
                  if (_digiFoxTapCount >= 7 && _digiFoxTapCount < 9) {
                    final remaining = 9 - _digiFoxTapCount;
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(SnackBar(
                          content: Text('$remaining more tap${remaining == 1 ? '' : 's'} to open vault settings'),
                          duration: const Duration(milliseconds: 800),
                          behavior: SnackBarBehavior.floating,
                        ));
                    }
                  }
                  if (_digiFoxTapCount >= 9) {
                    _digiFoxTapCount = 0;
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).clearSnackBars();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const VaultSettingsPage()),
                      );
                    }
                  }
                } else {
                  _digiFoxTapCount = 0;
                }
              },
            );
          }),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Display'),
          _DarkModeTile(
            isDark: isDark,
            primaryColor: primaryColor,
            onToggle: () => themeProvider.toggleTheme(),
          ),
          _InvertColorsTile(
            value: themeProvider.invertColors,
            primaryColor: primaryColor,
            onChanged: themeProvider.setInvertColors,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── Section Header ───────────────────────────────────────────
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

// ── Breed Tile ───────────────────────────────────────────────
class _BreedTile extends StatelessWidget {
  final ThemeBreed breed;
  final bool isSelected;
  final Color previewPrimary;
  final Color previewAccent;
  final Color previewBg;
  final Color primaryColor;
  final VoidCallback onTap;

  const _BreedTile({
    required this.breed,
    required this.isSelected,
    required this.previewPrimary,
    required this.previewAccent,
    required this.previewBg,
    required this.primaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withAlpha(26)
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: isSelected ? primaryColor : cs.outlineVariant,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Theme preview strip
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(color: cs.outlineVariant, width: 1),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Expanded(
                    flex: 2,
                    child: Container(color: previewPrimary),
                  ),
                  Expanded(
                    flex: 1,
                    child: Container(color: previewAccent),
                  ),
                  Expanded(
                    flex: 1,
                    child: Container(color: previewBg),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(breed.emoji,
                          style: const TextStyle(fontSize: 16)),
                      const SizedBox(width: 6),
                      Text(
                        breed.name,
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    breed.description,
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: cs.outline),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Selection indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? primaryColor : Colors.transparent,
                border: Border.all(
                  color: isSelected ? primaryColor : cs.outline,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Invert Colors Tile ───────────────────────────────────────
class _InvertColorsTile extends StatelessWidget {
  final bool value;
  final Color primaryColor;
  final ValueChanged<bool> onChanged;

  const _InvertColorsTile({
    required this.value,
    required this.primaryColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => onChanged(!value),
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
                color: primaryColor.withAlpha(25),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Icon(
                Icons.invert_colors_rounded,
                color: primaryColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Invert Colors',
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Inverts the entire app UI',
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: cs.outline),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: cs.onPrimary,
              activeTrackColor: primaryColor,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dark Mode Tile ───────────────────────────────────────────
class _DarkModeTile extends StatelessWidget {
  final bool isDark;
  final Color primaryColor;
  final VoidCallback onToggle;

  const _DarkModeTile({
    required this.isDark,
    required this.primaryColor,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onToggle,
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
                color: primaryColor.withAlpha(25),
                borderRadius: BorderRadius.circular(12.0),
              ),
              child: Icon(
                isDark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                color: primaryColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isDark ? 'Dark Mode' : 'Light Mode',
                    style: GoogleFonts.manrope(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isDark ? 'Currently dark' : 'Currently light',
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: cs.outline),
                  ),
                ],
              ),
            ),
            Switch(
              value: isDark,
              onChanged: (_) => onToggle(),
              activeThumbColor: cs.onPrimary,
              activeTrackColor: primaryColor,
            ),
          ],
        ),
      ),
    );
  }
}
