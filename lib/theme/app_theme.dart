import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // Radius
  static const double radiusSmall = 6.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 20.0;
  static const double radiusFull = 100.0;

  // Animation durations
  static const Duration fastMicro = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration entrance = Duration(milliseconds: 320);

  // Curves
  static const Curve defaultCurve = Curves.easeOutCubic;
  static const Curve primaryCurve = Curves.easeOutCubic;
  static const Curve springCurve = Curves.easeOutBack;

  // Semantic colors (use cs.primary from Theme instead of these for themed elements)
  static const Color secondary = Color(0xFF7C6FF7);
  static const Color secondaryContainer = Color(0x1A7C6FF7);
  static const Color success = Color(0xFF4CAF82);
  static const Color successContainer = Color(0x1A4CAF82);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningContainer = Color(0x1AF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color errorContainer = Color(0x1AEF4444);
  static const Color mutedDark = Color(0xFF6B6B8A);
  static const Color mutedLight = Color(0xFF6B7280);
  static const Color captionDark = Color(0xFF8888A8);

  /// Secondary text on dark surfaces.
  ///
  /// `mutedDark` (#6B6B8A) is a *border* tone — as text it only reaches 2.73:1
  /// on #2A2A3E and 3.19:1 on #1E1E2E, both under the 4.5:1 AA floor. This
  /// clears AA on every surface the app uses (4.6:1 on #2A2A3E, 5.7:1 on
  /// #1E1E2E) while still reading as clearly secondary.
  static const Color secondaryTextDark = Color(0xFF9A9AB8);
  static const Color secondaryTextLight = Color(0xFF5A5A70);
  static const Color surfaceElevatedDark = Color(0xFF252538);

  // Snackbar utilities
  static void showSnackBar(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 2),
  }) {
    final cs = Theme.of(context).colorScheme;

    // The default used to be `cs.surfaceContainerHighest`, which sits a hair
    // above `cs.surface` — so the toast barely separated from the page behind
    // it and read as unstyled grey text floating on the UI. Use a deliberately
    // distinct panel plus a visible border and shadow instead.
    final bg = backgroundColor ??
        (cs.brightness == Brightness.dark
            ? const Color(0xFF2E2E44)
            : const Color(0xFF1A1A2E));

    // Derive the text colour from whatever background we actually ended up
    // with. Callers pass red for errors and green for success, and previously
    // the label stayed `onSurface` regardless — which is what made a light
    // success toast unreadable.
    final fg = ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
        ? Colors.white
        : const Color(0xFF12121C);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.manrope(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: fg,
            height: 1.35,
          ),
        ),
        backgroundColor: bg,
        elevation: 8,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          side: BorderSide(color: fg.withAlpha(38)),
        ),
        duration: duration,
      ),
    );
  }

  static void showSuccessSnackBar(BuildContext context, String message) {
    showSnackBar(context, message, backgroundColor: success);
  }

  static void showErrorSnackBar(BuildContext context, String message) {
    showSnackBar(context, message, backgroundColor: error);
  }

  // Default fallback colors
  static const Color _backgroundDark = Color(0xFF12121C);
  static const Color _backgroundLight = Color(0xFFF5F5F5);
  static const Color _surfaceDark = Color(0xFF1E1E2E);
  static const Color _surfaceLight = Color(0xFFFFFFFF);
  static const Color _onSurfaceDark = Color(0xFFE8E8F0);
  static const Color _onSurfaceLight = Color(0xFF1A1A2E);

  static ThemeData darkTheme({Color? primaryColor}) {
    return _buildTheme(
      brightness: Brightness.dark,
      primary: primaryColor ?? const Color(0xFFFF7A5C),
      background: _backgroundDark,
      surface: _surfaceDark,
      onSurface: _onSurfaceDark,
      muted: mutedDark,
    );
  }

  static ThemeData lightTheme({Color? primaryColor}) {
    return _buildTheme(
      brightness: Brightness.light,
      primary: primaryColor ?? const Color(0xFFE85D4A),
      background: _backgroundLight,
      surface: _surfaceLight,
      onSurface: _onSurfaceLight,
      muted: mutedLight,
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required Color primary,
    required Color background,
    required Color surface,
    required Color onSurface,
    required Color muted,
  }) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      // White on the default coral (#FF7A5C) is only 2.56:1 — and the primary
      // is user-configurable, including near-white presets that would make a
      // white label invisible. Derive the label from the actual primary so it
      // stays readable whatever the user picks.
      onPrimary: ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
          ? Colors.white
          : const Color(0xFF1A1008),
      secondary: secondary,
      onSecondary: Colors.white,
      error: error,
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
      // Explicit secondary-text token. Without it Flutter falls back to
      // `onSurface`, so `cs.onSurfaceVariant` was full-brightness and gave no
      // hierarchy at all.
      onSurfaceVariant: isDark ? secondaryTextDark : secondaryTextLight,
      // `outline` is Material's *border* token, but this app uses it for
      // secondary text in ~250 places, where `muted` (#6B6B8A) is only 2.73:1
      // on #2A2A3E. Raising it here fixes every one of those at once — and it
      // also makes borders and dividers visible, which at 1.2–1.5:1 they
      // effectively weren't. Border-only tones stay on `outlineVariant`.
      outline: isDark ? secondaryTextDark : secondaryTextLight,
      outlineVariant: isDark
          ? const Color(0xFF3A3A4E)
          : const Color(0xFFD8D8DC),
      surfaceContainerHighest: isDark
          ? const Color(0xFF2A2A3E)
          : const Color(0xFFE8E8EC),
    );

    // `muted` is the outline/border tone. Using it for small text is what put
    // most of the app's captions and subtitles below the AA floor, so secondary
    // TEXT gets its own token while borders keep `muted`.
    final secondaryText = isDark ? secondaryTextDark : secondaryTextLight;

    final textTheme = GoogleFonts.manropeTextTheme(
      TextTheme(
        displayLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: onSurface),
        displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: onSurface),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: onSurface),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: onSurface),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: onSurface),
        bodyLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: onSurface),
        bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: onSurface),
        bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: secondaryText),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: onSurface),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: onSurface),
        labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: secondaryText),
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLarge)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE8E8EC),
        selectedColor: primary.withAlpha(51),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusFull),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF2A2A3E) : const Color(0xFFE8E8EC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        // Placeholders were `outline` on the fill colour — 2.73:1, well under
        // AA. Setting it once here covers every field in the app.
        hintStyle: TextStyle(color: secondaryText),
      ),
      dividerTheme: DividerThemeData(
        // muted.withAlpha(51) composites to 1.22:1 — every Divider was
        // effectively invisible. outlineVariant is the intended divider tone.
        color: isDark ? const Color(0xFF3A3A4E) : muted.withAlpha(90),
        thickness: 1,
      ),
    );
  }
}
