import 'package:flutter/foundation.dart' hide Category;
import '../models/manga_model.dart';
import '../models/chapter_model.dart';
import '../models/category_model.dart';
import '../services/library_service.dart';

class LibraryProvider extends ChangeNotifier {
  final LibraryService _libraryService = LibraryService();
  List<LibraryManga> _manga = [];
  List<Category> _categories = [];
  bool _initialized = false;

  List<LibraryManga> get manga => _manga;
  List<Category> get categories => _categories;
  bool get initialized => _initialized;

  Future<void> initialize() async {
    await _libraryService.init();
    _manga = _libraryService.getAllManga();
    _categories = _libraryService.getCategories();
    _initialized = true;
    notifyListeners();
  }

  /// Re-read the library from disk (e.g. after a backup restore wrote directly
  /// to the Hive boxes) without re-initializing the service.
  Future<void> reload() async {
    _manga = _libraryService.getAllManga();
    _categories = _libraryService.getCategories();
    notifyListeners();
  }

  // ── Category management ─────────────────────────────────────
  Future<void> addCategory(String name) async {
    await _libraryService.addCategory(name);
    _categories = _libraryService.getCategories();
    notifyListeners();
  }

  Future<void> removeCategory(String name) async {
    await _libraryService.removeCategory(name);
    _categories = _libraryService.getCategories();
    _manga = _libraryService.getAllManga();
    notifyListeners();
  }

  Future<void> reorderCategories(List<String> orderedNames) async {
    await _libraryService.reorderCategories(orderedNames);
    _categories = _libraryService.getCategories();
    notifyListeners();
  }

  Future<void> renameCategory(String oldName, String newName) async {
    await _libraryService.renameCategory(oldName, newName);
    _categories = _libraryService.getCategories();
    _manga = _libraryService.getAllManga();
    notifyListeners();
  }

  Future<void> setMangaCategories(String sourceId, String url, List<String> cats) async {
    final manga = _libraryService.getManga(sourceId, url);
    if (manga != null) {
      manga.categories = cats;
      await _libraryService.updateManga(manga);
      _manga = _libraryService.getAllManga();
      notifyListeners();
    }
  }

  bool isInLibrary(String sourceId, String url) {
    return _libraryService.isInLibrary(sourceId, url);
  }

  Future<void> addToLibrary(LibraryManga manga) async {
    await _libraryService.addManga(manga);
    _manga = _libraryService.getAllManga();
    notifyListeners();
  }

  Future<void> removeFromLibrary(String sourceId, String url) async {
    await _libraryService.removeManga(sourceId, url);
    _manga = _libraryService.getAllManga();
    notifyListeners();
  }

  Future<void> updateReadingProgress(
    String sourceId,
    String mangaUrl,
    String chapterUrl,
    int page,
  ) async {
    await _libraryService.updateReadingProgress(
        sourceId, mangaUrl, chapterUrl, page);
    _manga = _libraryService.getAllManga();
    notifyListeners();
  }

  Future<void> markChapterRead(
      String sourceId, String mangaUrl, String chapterUrl) async {
    await _libraryService.markChapterRead(sourceId, mangaUrl, chapterUrl);
    notifyListeners();
  }

  bool isChapterRead(String sourceId, String chapterUrl) {
    return _libraryService.isChapterRead(sourceId, chapterUrl);
  }

  // ── Chapter cache ─────────────────────────────────────────
  Future<void> cacheChapters(String sourceId, String mangaUrl, List<Map<String, dynamic>> chapters) async {
    final libChapters = chapters.map((c) => LibraryChapter(
      sourceId: sourceId,
      mangaUrl: mangaUrl,
      chapterUrl: c['url'] as String? ?? '',
      title: c['name'] as String? ?? '',
      dateUpload: c['dateUpload'] as String?,
    )).toList();
    await _libraryService.cacheChapters(sourceId, mangaUrl, libChapters);
    _manga = _libraryService.getAllManga();
    notifyListeners();
  }

  List<LibraryChapter> getCachedChapters(String sourceId, String mangaUrl) {
    return _libraryService.getCachedChapters(sourceId, mangaUrl);
  }

  Future<void> markAllRead(String sourceId, String url) async {
    await _libraryService.markAllChaptersRead(sourceId, url);
    _manga = _libraryService.getAllManga();
    notifyListeners();
  }

  Future<void> markAllUnread(String sourceId, String url) async {
    await _libraryService.markAllChaptersUnread(sourceId, url);
    _manga = _libraryService.getAllManga();
    notifyListeners();
  }

  // ── Reading stats ──────────────────────────────────────────────────
  Map<DateTime, int> getReadActivityByDay({int days = 365}) =>
      _libraryService.getReadActivityByDay(days: days);

  int getCurrentReadingStreak() => _libraryService.getCurrentReadingStreak();
  int getLongestReadingStreak() => _libraryService.getLongestReadingStreak();
}
