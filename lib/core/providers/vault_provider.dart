import 'package:flutter/foundation.dart' hide Category;
import 'package:hive/hive.dart';
import '../models/manga_model.dart';
import '../models/chapter_model.dart';
import '../models/category_model.dart';
import '../services/library_service.dart';

class VaultProvider extends ChangeNotifier {
  static const _settingsBoxName = 'vault_settings';

  final LibraryService _vaultService = LibraryService(prefix: 'vault');
  Box? _settingsBox;

  List<LibraryManga> _manga = [];
  List<Category> _categories = [];
  bool _initialized = false;
  bool _vaultEnabled = true;
  bool _vaultActive = false;
  Set<String> _vaultSourceIds = {};

  List<LibraryManga> get manga => _manga;
  List<Category> get categories => _categories;
  bool get initialized => _initialized;

  /// Source IDs that are hidden behind vault mode
  Set<String> get vaultSourceIds => _vaultSourceIds;

  /// Whether the vault feature is accessible (secret setting)
  bool get vaultEnabled => _vaultEnabled;

  /// Whether vault mode is currently active (user tapped in)
  bool get vaultActive => _vaultActive;

  Future<void> initialize() async {
    _settingsBox = await Hive.openBox(_settingsBoxName);
    _vaultEnabled = _settingsBox?.get('enabled', defaultValue: true) ?? true;
    _vaultSourceIds = ((_settingsBox?.get('vault_source_ids') as List?) ?? [])
        .cast<String>().toSet();
    await _vaultService.init();
    _manga = _vaultService.getAllManga();
    _categories = _vaultService.getCategories();
    _initialized = true;
    notifyListeners();
  }

  // ── Password protection ─────────────────────────────────────
  bool get hasPassword => (_settingsBox?.get('vault_password') as String?)?.isNotEmpty ?? false;

  bool verifyPassword(String password) {
    final stored = _settingsBox?.get('vault_password') as String?;
    if (stored == null || stored.isEmpty) return true;
    return _hashPassword(password) == stored;
  }

  void setPassword(String? password) {
    if (password == null || password.isEmpty) {
      _settingsBox?.delete('vault_password');
    } else {
      _settingsBox?.put('vault_password', _hashPassword(password));
    }
    notifyListeners();
  }

  String _hashPassword(String password) {
    // Simple hash — not cryptographically strong but sufficient for local vault lock
    var hash = 0x811c9dc5;
    for (var i = 0; i < password.length; i++) {
      hash ^= password.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  // ── Vault mode control ──────────────────────────────────────
  void enterVault() {
    if (!_vaultEnabled) return;
    _vaultActive = true;
    notifyListeners();
  }

  void exitVault() {
    _vaultActive = false;
    notifyListeners();
  }

  void setVaultEnabled(bool enabled) {
    _vaultEnabled = enabled;
    _settingsBox?.put('enabled', enabled);
    if (!enabled) _vaultActive = false;
    notifyListeners();
  }

  // ── Vault source visibility ───────────────────────────────
  bool isSourceInVault(String sourceId) => _vaultSourceIds.contains(sourceId);

  void toggleVaultSource(String sourceId) {
    if (_vaultSourceIds.contains(sourceId)) {
      _vaultSourceIds.remove(sourceId);
    } else {
      _vaultSourceIds.add(sourceId);
    }
    _settingsBox?.put('vault_source_ids', _vaultSourceIds.toList());
    notifyListeners();
  }

  // ── Category management (mirrors LibraryProvider) ───────────
  Future<void> addCategory(String name) async {
    await _vaultService.addCategory(name);
    _categories = _vaultService.getCategories();
    notifyListeners();
  }

  Future<void> removeCategory(String name) async {
    await _vaultService.removeCategory(name);
    _categories = _vaultService.getCategories();
    _manga = _vaultService.getAllManga();
    notifyListeners();
  }

  Future<void> reorderCategories(List<String> orderedNames) async {
    await _vaultService.reorderCategories(orderedNames);
    _categories = _vaultService.getCategories();
    notifyListeners();
  }

  Future<void> renameCategory(String oldName, String newName) async {
    await _vaultService.renameCategory(oldName, newName);
    _categories = _vaultService.getCategories();
    _manga = _vaultService.getAllManga();
    notifyListeners();
  }

  Future<void> setMangaCategories(
      String sourceId, String url, List<String> cats) async {
    final manga = _vaultService.getManga(sourceId, url);
    if (manga != null) {
      manga.categories = cats;
      await _vaultService.updateManga(manga);
      _manga = _vaultService.getAllManga();
      notifyListeners();
    }
  }

  // ── Manga management ────────────────────────────────────────
  bool isInLibrary(String sourceId, String url) {
    return _vaultService.isInLibrary(sourceId, url);
  }

  Future<void> addToLibrary(LibraryManga manga) async {
    await _vaultService.addManga(manga);
    _manga = _vaultService.getAllManga();
    notifyListeners();
  }

  Future<void> removeFromLibrary(String sourceId, String url) async {
    await _vaultService.removeManga(sourceId, url);
    _manga = _vaultService.getAllManga();
    notifyListeners();
  }

  Future<void> updateReadingProgress(
      String sourceId, String mangaUrl, String chapterUrl, int page) async {
    await _vaultService.updateReadingProgress(
        sourceId, mangaUrl, chapterUrl, page);
    _manga = _vaultService.getAllManga();
    notifyListeners();
  }

  Future<void> cacheChapters(String sourceId, String mangaUrl, List<Map<String, dynamic>> chapters) async {
    final libChapters = chapters.map((c) => LibraryChapter(
      sourceId: sourceId,
      mangaUrl: mangaUrl,
      chapterUrl: c['url'] as String? ?? '',
      title: c['name'] as String? ?? '',
      dateUpload: c['dateUpload'] as String?,
    )).toList();
    await _vaultService.cacheChapters(sourceId, mangaUrl, libChapters);
    _manga = _vaultService.getAllManga();
    notifyListeners();
  }

  List<LibraryChapter> getCachedChapters(String sourceId, String mangaUrl) {
    return _vaultService.getCachedChapters(sourceId, mangaUrl);
  }

  Future<void> markChapterRead(
      String sourceId, String mangaUrl, String chapterUrl) async {
    await _vaultService.markChapterRead(sourceId, mangaUrl, chapterUrl);
    notifyListeners();
  }

  bool isChapterRead(String sourceId, String chapterUrl) {
    return _vaultService.isChapterRead(sourceId, chapterUrl);
  }

  Future<void> markAllRead(String sourceId, String url) async {
    await _vaultService.markAllChaptersRead(sourceId, url);
    _manga = _vaultService.getAllManga();
    notifyListeners();
  }

  Future<void> markAllUnread(String sourceId, String url) async {
    await _vaultService.markAllChaptersUnread(sourceId, url);
    _manga = _vaultService.getAllManga();
    notifyListeners();
  }

  // ── Reading stats ──────────────────────────────────────────────────
  Map<DateTime, int> getReadActivityByDay({int days = 365}) =>
      _vaultService.getReadActivityByDay(days: days);

  int getCurrentReadingStreak() => _vaultService.getCurrentReadingStreak();
  int getLongestReadingStreak() => _vaultService.getLongestReadingStreak();
}
