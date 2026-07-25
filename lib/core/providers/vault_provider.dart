import 'package:flutter/foundation.dart' hide Category;
import 'package:hive/hive.dart';
import '../models/manga_model.dart';
import '../models/chapter_model.dart';
import '../models/category_model.dart';
import '../services/library_service.dart';
import '../services/vault_crypto.dart';

/// Arguments for the off-thread key derivation.
class _KdfRequest {
  final String password;
  final Uint8List salt;
  final int iterations;
  const _KdfRequest(this.password, this.salt, this.iterations);
}

/// PBKDF2 with 50k iterations takes ~1s in pure Dart, which would jank the UI
/// on the main isolate — so it runs via `compute`. Must be top-level.
Uint8List _deriveKeyIsolate(_KdfRequest r) =>
    VaultCrypto.deriveKey(r.password, r.salt, iterations: r.iterations);

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

    // Vault contents are NOT opened here when a password is set. Previously
    // they were loaded at startup regardless, so the password only hid the UI
    // — the plaintext Hive files were readable by anything with filesystem
    // access. Now the boxes stay encrypted and closed until [unlock] supplies
    // the key derived from the password.
    if (!hasPassword) {
      await _vaultService.init();
      _manga = _vaultService.getAllManga();
      _categories = _vaultService.getCategories();
    }
    _initialized = true;
    notifyListeners();
  }

  // ── Password protection ─────────────────────────────────────
  bool get hasPassword =>
      (_settingsBox?.get('vault_verifier') as String?)?.isNotEmpty ?? false;

  /// True once [unlock] has succeeded — i.e. the encrypted boxes are open.
  bool get isUnlocked => !hasPassword || _vaultService.isOpen;

  Uint8List _saltOrNew() {
    final stored = _settingsBox?.get('vault_salt');
    if (stored is List && stored.isNotEmpty) {
      return Uint8List.fromList(stored.cast<int>());
    }
    return VaultCrypto.newSalt();
  }

  /// Derives the key, checks it against the stored verifier, and — only on
  /// success — opens the encrypted boxes and loads their contents.
  Future<bool> unlock(String password) async {
    if (!hasPassword) return true;
    final salt = _saltOrNew();
    final iterations =
        (_settingsBox?.get('vault_iterations') as int?) ??
            VaultCrypto.defaultIterations;

    final key = await compute<_KdfRequest, Uint8List>(
      _deriveKeyIsolate,
      _KdfRequest(password, salt, iterations),
    );
    if (VaultCrypto.verifierFor(key) !=
        (_settingsBox?.get('vault_verifier') as String?)) {
      return false;
    }

    await _vaultService.init(cipher: VaultCrypto.cipherFor(key));
    _manga = _vaultService.getAllManga();
    _categories = _vaultService.getCategories();
    notifyListeners();
    return true;
  }

  /// Sets or clears the vault password.
  ///
  /// Changing it re-encrypts: the current contents are read with the old key
  /// (or from the plaintext boxes on first use), the boxes are deleted, then
  /// rewritten under the new key. Without this, existing vault data would be
  /// stranded in files the new key can't open.
  Future<void> setPassword(String? password) async {
    final existingManga = List<LibraryManga>.from(_manga);
    final existingCats = _categories.map((c) => c.name).toList();

    await _vaultService.close();
    await Hive.deleteBoxFromDisk('vault_manga');
    await Hive.deleteBoxFromDisk('vault_chapters');
    await Hive.deleteBoxFromDisk('vault_categories');

    if (password == null || password.isEmpty) {
      await _settingsBox?.delete('vault_verifier');
      await _settingsBox?.delete('vault_salt');
      await _settingsBox?.delete('vault_iterations');
      await _vaultService.init();
    } else {
      final salt = VaultCrypto.newSalt();
      final key = await compute<_KdfRequest, Uint8List>(
        _deriveKeyIsolate,
        _KdfRequest(password, salt, VaultCrypto.defaultIterations),
      );
      await _settingsBox?.put('vault_salt', salt.toList());
      await _settingsBox?.put('vault_iterations', VaultCrypto.defaultIterations);
      await _settingsBox?.put('vault_verifier', VaultCrypto.verifierFor(key));
      await _vaultService.init(cipher: VaultCrypto.cipherFor(key));
    }

    // Restore what was there before, now under the new encryption.
    for (final name in existingCats) {
      if (!_vaultService.getCategories().any((c) => c.name == name)) {
        await _vaultService.addCategory(name);
      }
    }
    for (final m in existingManga) {
      await _vaultService.addManga(m);
    }
    _manga = _vaultService.getAllManga();
    _categories = _vaultService.getCategories();
    notifyListeners();
  }

  // ── Vault mode control ──────────────────────────────────────
  void enterVault() {
    if (!_vaultEnabled) return;
    if (hasPassword && !_vaultService.isOpen) return; // must unlock first
    _vaultActive = true;
    notifyListeners();
  }

  /// Leaving the vault closes the encrypted boxes and drops the decrypted copy
  /// from memory, so the data isn't left readable until the app restarts.
  Future<void> exitVault() async {
    _vaultActive = false;
    if (hasPassword) {
      await _vaultService.close();
      _manga = [];
      _categories = [];
    }
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

  /// Full chapter objects (with read state) for an entry, for moving out.
  List<LibraryChapter> fullChapters(String sourceId, String url) =>
      _vaultService.getFullChapters(sourceId, url);

  /// Adds an entry and its chapters into the vault, preserving read progress.
  Future<void> addEntryWithChapters(
      LibraryManga manga, List<LibraryChapter> chapters) async {
    await _vaultService.addEntryWithChapters(manga, chapters);
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
  Map<DateTime, int> getReadActivityByDay({int days = 365, Set<String>? sourceIds}) =>
      _vaultService.getReadActivityByDay(days: days, sourceIds: sourceIds);

  int getCurrentReadingStreak({Set<String>? sourceIds}) =>
      _vaultService.getCurrentReadingStreak(sourceIds: sourceIds);
  int getLongestReadingStreak({Set<String>? sourceIds}) =>
      _vaultService.getLongestReadingStreak(sourceIds: sourceIds);
}
