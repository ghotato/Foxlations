import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which kind of content the Library tab is currently showing — manga, anime or
/// light novels. Chosen by long-pressing the Library tab (see the nav-bar-style
/// menu) and persisted, so it survives leaving or closing the app.
///
/// The value strings match [MangaSource.itemType] ('manga' | 'anime' | 'novel')
/// so the library can filter entries by looking up each one's source type.
class LibraryTypeProvider extends ChangeNotifier {
  static const _key = 'library_content_type';

  /// Ordered for the menu: manga first (the default and the majority), then
  /// anime, then light novels.
  static const List<String> types = ['manga', 'anime', 'novel'];

  static String label(String type) {
    switch (type) {
      case 'anime':
        return 'Anime';
      case 'novel':
        return 'Light Novels';
      case 'manga':
      default:
        return 'Manga';
    }
  }

  String _type = 'manga';
  String get type => _type;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && types.contains(saved)) {
      _type = saved;
      notifyListeners();
    }
  }

  Future<void> setType(String type) async {
    if (_type == type || !types.contains(type)) return;
    _type = type;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, type);
  }
}
