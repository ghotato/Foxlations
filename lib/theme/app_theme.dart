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
  static const Color surfaceElevatedDark = Color(0xFF252538);

  // Snackbar utilities
  static void showSnackBar(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    Duration duration = const Duration(seconds: 2),
  }) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.manrope(
            fontSize: 13,
            color: cs.onSurface,
          ),
        ),
        backgroundColor: backgroundColor ?? cs.surfaceContainerHighest,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
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
      onPrimary: Colors.white,
      secondary: secondary,
      onSecondary: Colors.white,
      error: error,
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
      outline: muted,
      outlineVariant: isDark
          ? const Color(0xFF3A3A4E)
          : const Color(0xFFD8D8DC),
      surfaceContainerHighest: isDark
          ? const Color(0xFF2A2A3E)
          : const Color(0xFFE8E8EC),
    );

    final textTheme = GoogleFonts.manropeTextTheme(
      TextTheme(
        displayLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, color: onSurface),
        displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: onSurface),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: onSurface),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: onSurface),
        titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: onSurface),
        bodyLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: onSurface),
        bodyMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: onSurface),
        bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: muted),
        labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: onSurface),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: onSurface),
        labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: muted),
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
      ),
      dividerTheme: DividerThemeData(
        color: muted.withAlpha(51),
        thickness: 1,
      ),
    );
  }
}
