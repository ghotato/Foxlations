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

  bool get isOpen => _mangaBox?.isOpen ?? false;

  /// Closes the boxes and drops the in-memory copies, so locking the vault
  /// actually evicts its data rather than just hiding it behind a flag.
  Future<void> close() async {
    await _mangaBox?.close();
    await _chapterBox?.close();
    await _categoryBox?.close();
    _mangaBox = _chapterBox = null;
    _categoryBox = null;
  }

  static const _defaultCategories = [
    'Reading',
    'Completed',
    'On Hold',
    'Dropped',
    'Plan to Read',
  ];

  /// [cipher] encrypts the underlying Hive files at rest. Used by the vault so
  /// its contents are unreadable without the user's password — Hive refuses to
  /// open an encrypted box with the wrong key, so this is the actual access
  /// control, not the password prompt in the UI.
  Future<void> init({HiveAesCipher? cipher}) async {
    _mangaBox = await Hive.openBox<LibraryManga>('${_prefix}_manga',
        encryptionCipher: cipher);
    _chapterBox = await Hive.openBox<LibraryChapter>('${_prefix}_chapters',
        encryptionCipher: cipher);
    _categoryBox = await Hive.openBox<Category>('${_prefix}_categories',
        encryptionCipher: cipher);
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

  /// Adds an entry together with its full chapter objects, preserving per-
  /// chapter read state and page progress. Used when moving a title between the
  /// normal library and the vault so nothing is lost in the transfer.
  Future<void> addEntryWithChapters(
      LibraryManga manga, List<LibraryChapter> chapters) async {
    await _mangaBox?.put(manga.uniqueKey, manga);
    for (final ch in chapters) {
      // Re-home the chapter to this box exactly as-is (isRead/lastPageRead/
      // readAt intact); the destination has no prior copy to merge with.
      await _chapterBox?.put(ch.uniqueKey, ch);
    }
  }

  /// The full chapter objects for an entry (with read state), for moving.
  List<LibraryChapter> getFullChapters(String sourceId, String mangaUrl) {
    return _chapterBox?.values
            .where((c) => c.sourceId == sourceId && c.mangaUrl == mangaUrl)
            .toList() ??
        [];
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

  Future<void> markChapterUnread(
      String sourceId, String mangaUrl, String chapterUrl) async {
    final key = '${sourceId}_$chapterUrl';
    final chapter = _chapterBox?.get(key);
    if (chapter != null) {
      chapter.isRead = false;
      chapter.readAt = null;
      await chapter.save();
    }
  }

  Future<void> markAllChaptersRead(String sourceId, String mangaUrl) async {
    final manga = getManga(sourceId, mangaUrl);
    if (manga != null) {
      manga.readChapters = manga.totalChapters;
      await manga.save();
    }
  }

  // ── Chapter cache ───────────────────────────────────────────
  /// Cache chapters for a library manga (called after getDetail).
  /// Records each chapter's position in the input list as `sourceIndex` so
  /// that [getCachedChapters] can return them in the original source order
  /// rather than Hive's key insertion order (which causes alphabetical
  /// "Chapter 1, 10, 100, 101..." flickering on first load).
  Future<void> cacheChapters(String sourceId, String mangaUrl, List<LibraryChapter> chapters) async {
    for (var i = 0; i < chapters.length; i++) {
      final ch = chapters[i];
      ch.sourceIndex = i;
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
    final list = _chapterBox?.values
        .where((c) => c.sourceId == sourceId && c.mangaUrl == mangaUrl)
        .toList() ?? <LibraryChapter>[];
    final hasIndices = list.any((c) => c.sourceIndex != null);
    if (hasIndices) {
      // Cached after the sourceIndex fix — preserve the source's exact
      // order. Any stragglers without an index sort to the end.
      list.sort((a, b) {
        final ai = a.sourceIndex;
        final bi = b.sourceIndex;
        if (ai == null && bi == null) return 0;
        if (ai == null) return 1;
        if (bi == null) return -1;
        return ai.compareTo(bi);
      });
    } else {
      // Pre-fix cache — Hive's iteration order is unreliable here
      // (markChapterRead can splice records into the box at random points).
      // Fall back to natural-numeric sort on the chapter title, descending,
      // which matches how almost every source returns chapters (newest
      // first). The first background refresh will stamp real sourceIndex
      // values and switch to the branch above.
      list.sort((a, b) {
        final na = _parseChapterNumber(a.title);
        final nb = _parseChapterNumber(b.title);
        if (na == null && nb == null) return a.title.compareTo(b.title);
        if (na == null) return 1;
        if (nb == null) return -1;
        return nb.compareTo(na);
      });
    }
    return list;
  }

  static final _chapterNumberRegExp = RegExp(r'(\d+(?:\.\d+)?)');
  static double? _parseChapterNumber(String title) {
    final match = _chapterNumberRegExp.firstMatch(title);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
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

  // ── Reading stats ──────────────────────────────────────────────────
  /// Returns a map of `date (midnight) → number of chapters read on that
  /// day`, restricted to the last [days] days. Used by the activity
  /// heatmap.
  Map<DateTime, int> getReadActivityByDay({int days = 365}) {
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final activity = <DateTime, int>{};
    if (_chapterBox == null) return activity;
    for (final ch in _chapterBox!.values) {
      final r = ch.readAt;
      if (r == null || !ch.isRead) continue;
      final day = DateTime(r.year, r.month, r.day);
      if (day.isBefore(cutoff)) continue;
      activity[day] = (activity[day] ?? 0) + 1;
    }
    return activity;
  }

  /// Current streak: consecutive days ending today (or yesterday) on
  /// which at least one chapter was read.
  int getCurrentReadingStreak() {
    final activity = getReadActivityByDay(days: 365);
    if (activity.isEmpty) return 0;
    final now = DateTime.now();
    var day = DateTime(now.year, now.month, now.day);
    // Allow the streak to be "alive" if user hasn't read yet today but did
    // read yesterday — start counting from yesterday in that case.
    if ((activity[day] ?? 0) == 0) {
      day = day.subtract(const Duration(days: 1));
      if ((activity[day] ?? 0) == 0) return 0;
    }
    var streak = 0;
    while ((activity[day] ?? 0) > 0) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Longest streak ever recorded in the chapter history.
  int getLongestReadingStreak() {
    final activity = getReadActivityByDay(days: 365);
    if (activity.isEmpty) return 0;
    final dates = activity.keys.toList()..sort();
    var longest = 1;
    var current = 1;
    for (var i = 1; i < dates.length; i++) {
      final diff = dates[i].difference(dates[i - 1]).inDays;
      if (diff == 1) {
        current++;
        if (current > longest) longest = current;
      } else if (diff > 1) {
        current = 1;
      }
    }
    return longest;
  }
}
