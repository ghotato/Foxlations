import 'package:hive/hive.dart';
import '../models/manga_model.dart';
import '../models/chapter_model.dart';
import '../models/category_model.dart';

class LibraryService {
  final String _prefix;

  LibraryService({String prefix = 'library'}) : _prefix = prefix;

  Box<LibraryManga>? _mangaBox;
  Box<LibraryChapter>? _chapterBox;
  Box<Category>? _categoryBox;

  static const _defaultCategories = [
    'Reading',
    'Completed',
    'On Hold',
    'Dropped',
    'Plan to Read',
  ];

  Future<void> init() async {
    _mangaBox = await Hive.openBox<LibraryManga>('${_prefix}_manga');
    _chapterBox = await Hive.openBox<LibraryChapter>('${_prefix}_chapters');
    _categoryBox = await Hive.openBox<Category>('${_prefix}_categories');
    // Seed default categories on first run
    if (_categoryBox!.isEmpty) {
      for (int i = 0; i < _defaultCategories.length; i++) {
        await _categoryBox!.add(Category(name: _defaultCategories[i], order: i));
      }
    }
  }

  // ── Categories ──────────────────────────────────────────────
  List<Category> getCategories() {
    final cats = _categoryBox?.values.toList() ?? [];
    cats.sort((a, b) => a.order.compareTo(b.order));
    return cats;
  }

  Future<void> addCategory(String name) async {
    final order = (_categoryBox?.values.length ?? 0);
    final cat = Category(name: name, order: order);
    await _categoryBox?.add(cat);
  }

  Future<void> removeCategory(String name) async {
    final entry = _categoryBox?.values.cast<Category?>().firstWhere(
        (c) => c!.name == name,
        orElse: () => null);
    if (entry != null) {
      // Remove this category from all manga
      for (final manga in _mangaBox?.values ?? <LibraryManga>[]) {
        if (manga.categories.contains(name)) {
          manga.categories = List<String>.from(manga.categories)..remove(name);
          await manga.save();
        }
      }
      await entry.delete();
    }
  }

  Future<void> reorderCategories(List<String> orderedNames) async {
    for (int i = 0; i < orderedNames.length; i++) {
      final cat = _categoryBox?.values.cast<Category?>().firstWhere(
          (c) => c!.name == orderedNames[i],
          orElse: () => null);
      if (cat != null) {
        cat.order = i;
        await cat.save();
      }
    }
  }

  Future<void> renameCategory(String oldName, String newName) async {
    final cat = _categoryBox?.values.cast<Category?>().firstWhere(
        (c) => c!.name == oldName,
        orElse: () => null);
    if (cat != null) {
      cat.name = newName;
      await cat.save();
      // Update all manga referencing this category
      for (final manga in _mangaBox?.values ?? <LibraryManga>[]) {
        final idx = manga.categories.indexOf(oldName);
        if (idx != -1) {
          manga.categories = List<String>.from(manga.categories)
            ..[idx] = newName;
          await manga.save();
        }
      }
    }
  }

  List<LibraryManga> getAllManga() {
    return _mangaBox?.values.toList() ?? [];
  }

  LibraryManga? getManga(String sourceId, String url) {
    final key = '${sourceId}_$url';
    try {
      return _mangaBox?.values.firstWhere((m) => m.uniqueKey == key);
    } catch (_) {
      return null;
    }
  }

  bool isInLibrary(String sourceId, String url) {
    return getManga(sourceId, url) != null;
  }

  Future<void> addManga(LibraryManga manga) async {
    await _mangaBox?.put(manga.uniqueKey, manga);
  }

  Future<void> removeManga(String sourceId, String url) async {
    final key = '${sourceId}_$url';
    await _mangaBox?.delete(key);
    // Also remove associated chapters
    final chapterKeys = _chapterBox?.keys.where((k) {
      final chapter = _chapterBox?.get(k);
      return chapter?.sourceId == sourceId && chapter?.mangaUrl == url;
    }).toList();
    if (chapterKeys != null) {
      await _mangaBox?.deleteAll(chapterKeys);
    }
  }

  Future<void> updateManga(LibraryManga manga) async {
    await _mangaBox?.put(manga.uniqueKey, manga);
  }

  Future<void> updateReadingProgress(
    String sourceId,
    String mangaUrl,
    String chapterUrl,
    int page,
  ) async {
    final manga = getManga(sourceId, mangaUrl);
    if (manga != null) {
      manga.lastReadChapterUrl = chapterUrl;
      manga.lastReadPage = page;
      manga.lastReadAt = DateTime.now();
      await manga.save();
    }
  }

  // Chapter tracking
  List<LibraryChapter> getChapters(String sourceId, String mangaUrl) {
    return _chapterBox?.values
            .where((c) => c.sourceId == sourceId && c.mangaUrl == mangaUrl)
            .toList() ??
        [];
  }

  Future<void> markChapterRead(
      String sourceId, String mangaUrl, String chapterUrl) async {
    final key = '${sourceId}_$chapterUrl';
    var chapter = _chapterBox?.get(key);
    if (chapter != null) {
      chapter.isRead = true;
      chapter.readAt = DateTime.now();
      await chapter.save();
    } else {
      chapter = LibraryChapter(
        sourceId: sourceId,
        mangaUrl: mangaUrl,
        chapterUrl: chapterUrl,
        title: '',
        isRead: true,
        readAt: DateTime.now(),
      );
      await _chapterBox?.put(key, chapter);
    }
  }

  bool isChapterRead(String sourceId, String chapterUrl) {
    final key = '${sourceId}_$chapterUrl';
    return _chapterBox?.get(key)?.isRead ?? false;
  }

  Future<void> markAllChaptersRead(String sourceId, String mangaUrl) async {
    final manga = getManga(sourceId, mangaUrl);
    if (manga != null) {
      manga.readChapters = manga.totalChapters;
      await manga.save();
    }
  }

  // ── Chapter cache ───────────────────────────────────────────
  /// Cache chapters for a library manga (called after getDetail)
  Future<void> cacheChapters(String sourceId, String mangaUrl, List<LibraryChapter> chapters) async {
    for (final ch in chapters) {
      final key = ch.uniqueKey;
      final existing = _chapterBox?.get(key);
      if (existing != null) {
        // Preserve read state and page progress
        ch.isRead = existing.isRead;
        ch.lastPageRead = existing.lastPageRead;
        ch.readAt = existing.readAt;
      }
      await _chapterBox?.put(key, ch);
    }

    // Update total chapters count on manga
    final manga = getManga(sourceId, mangaUrl);
    if (manga != null) {
      manga.totalChapters = chapters.length;
      await manga.save();
    }
  }

  /// Get cached chapters for a manga (for instant detail screen load)
  List<LibraryChapter> getCachedChapters(String sourceId, String mangaUrl) {
    return _chapterBox?.values
        .where((c) => c.sourceId == sourceId && c.mangaUrl == mangaUrl)
        .toList() ?? [];
  }

  Future<void> markAllChaptersUnread(String sourceId, String mangaUrl) async {
    final manga = getManga(sourceId, mangaUrl);
    if (manga != null) {
      manga.readChapters = 0;
      manga.lastReadChapterUrl = null;
      manga.lastReadPage = 0;
      await manga.save();
    }
    // Also remove individual chapter read records
    final keysToRemove = _chapterBox?.keys.where((k) {
      final ch = _chapterBox?.get(k);
      return ch?.sourceId == sourceId && ch?.mangaUrl == mangaUrl;
    }).toList();
    if (keysToRemove != null) {
      await _chapterBox?.deleteAll(keysToRemove);
    }
  }
}
