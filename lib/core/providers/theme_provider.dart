import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _themeKey = 'theme_mode';
  static const _breedKey = 'theme_breed';
  static const _invertKey = 'theme_invert_colors';

  ThemeMode _themeMode = ThemeMode.dark;
  String _breedId = 'red_fox';
  bool _invertColors = false;

  ThemeMode get themeMode => _themeMode;
  String get breedId => _breedId;
  bool get invertColors => _invertColors;

  /// Get the primary color for the current breed and brightness.
  Color primaryColor(Brightness brightness) {
    final breed = themeBreeds[_breedId] ?? themeBreeds['red_fox']!;
    return brightness == Brightness.dark ? breed.primaryDark : breed.primaryLight;
  }

  Color accentColor(Brightness brightness) {
    final breed = themeBreeds[_breedId] ?? themeBreeds['red_fox']!;
    return brightness == Brightness.dark ? breed.accentDark : breed.accentLight;
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_themeKey);
    _themeMode = value == 'light' ? ThemeMode.light : ThemeMode.dark;
    _breedId = prefs.getString(_breedKey) ?? 'red_fox';
    _invertColors = prefs.getBool(_invertKey) ?? false;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _themeMode =
        _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _themeKey, _themeMode == ThemeMode.dark ? 'dark' : 'light');
    notifyListeners();
  }

  Future<void> setBreed(String breedId) async {
    _breedId = breedId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_breedKey, breedId);
    notifyListeners();
  }

  Future<void> setInvertColors(bool value) async {
    if (_invertColors == value) return;
    _invertColors = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_invertKey, value);
    notifyListeners();
  }

  /// All available theme breeds.
  static const Map<String, ThemeBreedColors> themeBreeds = {
    'red_fox': ThemeBreedColors(
      primaryLight: Color(0xFFE85D4A), primaryDark: Color(0xFFFF7A5C),
      accentLight: Color(0xFFF59E0B), accentDark: Color(0xFFFFB830),
      backgroundDark: Color(0xFF1A1008),
    ),
    'arctic_fox': ThemeBreedColors(
      primaryLight: Color(0xFF5B9BD5), primaryDark: Color(0xFF90C8F0),
      accentLight: Color(0xFF7EC8E3), accentDark: Color(0xFFAEDFF7),
      backgroundDark: Color(0xFF0D1520),
    ),
    'silver_fox': ThemeBreedColors(
      primaryLight: Color(0xFF6B7280), primaryDark: Color(0xFFB0B8C8),
      accentLight: Color(0xFF9CA3AF), accentDark: Color(0xFFD1D5DB),
      backgroundDark: Color(0xFF0F1117),
    ),
    'marble_fox': ThemeBreedColors(
      primaryLight: Color(0xFF1F2937), primaryDark: Color(0xFFF9FAFB),
      accentLight: Color(0xFF374151), accentDark: Color(0xFFE5E7EB),
      backgroundDark: Color(0xFF111827),
    ),
    'cross_fox': ThemeBreedColors(
      primaryLight: Color(0xFF92400E), primaryDark: Color(0xFFD97706),
      accentLight: Color(0xFFB45309), accentDark: Color(0xFFF59E0B),
      backgroundDark: Color(0xFF1C1208),
    ),
    'fennec_fox': ThemeBreedColors(
      primaryLight: Color(0xFFD4A574), primaryDark: Color(0xFFE8C49A),
      accentLight: Color(0xFFC8956C), accentDark: Color(0xFFDDB88A),
      backgroundDark: Color(0xFF1A1508),
    ),
    'digi_fox': ThemeBreedColors(
      primaryLight: Color(0xFF7C3AED), primaryDark: Color(0xFF9D5CF6),
      accentLight: Color(0xFFA855F7), accentDark: Color(0xFFC084FC),
      backgroundDark: Color(0xFF0F0A1A),
    ),
  };
}

class ThemeBreedColors {
  final Color primaryLight;
  final Color primaryDark;
  final Color accentLight;
  final Color accentDark;
  final Color backgroundDark;

  const ThemeBreedColors({
    required this.primaryLight,
    required this.primaryDark,
    required this.accentLight,
    required this.accentDark,
    required this.backgroundDark,
  });
}
