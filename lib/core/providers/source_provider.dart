import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/source_model.dart';
import '../models/installed_source_model.dart';
import '../services/app_logger.dart';
import '../services/repo_service.dart';
import '../services/source_manager.dart';

class SourceProvider extends ChangeNotifier {
  // Browse preference keys (also referenced from BrowseSettingsPage).
  static const _showNsfwKey = 'browse_show_nsfw';
  static const _pinnedOnlyBrowseKey = 'browse_pinned_only';
  static const _pinnedOnlyGlobalSearchKey = 'browse_global_search_pinned_only';
  static const _autoUpdateExtKey = 'browse_auto_update_extensions';

  final RepoService _repoService = RepoService();
  final SourceManager _sourceManager = SourceManager();

  List<String> _repoUrls = [];
  Map<String, RepoIndexResult> _repoIndexes = {};
  List<InstalledSource> _installedSources = [];
  bool _isLoading = false;
  String? _error;

  // Browse preferences (persisted)
  bool _showNsfw = false;
  bool _pinnedOnlyBrowse = false;
  bool _pinnedOnlyGlobalSearch = false;
  bool _autoUpdateExtensions = false;

  List<String> get repoUrls => _repoUrls;
  Map<String, RepoIndexResult> get repoIndexes => _repoIndexes;
  List<InstalledSource> get installedSources => _installedSources;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool get showNsfw => _showNsfw;
  bool get pinnedOnlyBrowse => _pinnedOnlyBrowse;
  bool get pinnedOnlyGlobalSearch => _pinnedOnlyGlobalSearch;
  bool get autoUpdateExtensions => _autoUpdateExtensions;

  /// All available sources across all repos.
  List<MangaSource> get allSources =>
      _repoIndexes.values.expand((r) => r.sources).toList();

  Future<void> initialize() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Load browse preferences first so consumers see the right values on
      // their initial build.
      final prefs = await SharedPreferences.getInstance();
      _showNsfw = prefs.getBool(_showNsfwKey) ?? false;
      _pinnedOnlyBrowse = prefs.getBool(_pinnedOnlyBrowseKey) ?? false;
      _pinnedOnlyGlobalSearch =
          prefs.getBool(_pinnedOnlyGlobalSearchKey) ?? false;
      _autoUpdateExtensions = prefs.getBool(_autoUpdateExtKey) ?? false;

      _repoUrls = await _repoService.getSavedRepos();
      _installedSources = await _sourceManager.getInstalledSources();

      // Load cached indexes
      for (final url in _repoUrls) {
        final cached = await _repoService.getCachedIndex(url);
        if (!cached.isEmpty) {
          _repoIndexes[url] = cached;
        }
      }
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();

    // If auto-update is on, refresh installed extension code in the
    // background. Doesn't block the initial app load.
    if (_autoUpdateExtensions) {
      // ignore: unawaited_futures
      refreshAllSourceCode();
    }
  }

  Future<void> setShowNsfw(bool value) async {
    if (_showNsfw == value) return;
    _showNsfw = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showNsfwKey, value);
    notifyListeners();
  }

  Future<void> setPinnedOnlyBrowse(bool value) async {
    if (_pinnedOnlyBrowse == value) return;
    _pinnedOnlyBrowse = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pinnedOnlyBrowseKey, value);
    notifyListeners();
  }

  Future<void> setPinnedOnlyGlobalSearch(bool value) async {
    if (_pinnedOnlyGlobalSearch == value) return;
    _pinnedOnlyGlobalSearch = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pinnedOnlyGlobalSearchKey, value);
    notifyListeners();
  }

  Future<void> setAutoUpdateExtensions(bool value) async {
    if (_autoUpdateExtensions == value) return;
    _autoUpdateExtensions = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoUpdateExtKey, value);
    notifyListeners();
  }

  Future<void> refreshRepos() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      for (final url in _repoUrls) {
        try {
          _repoIndexes[url] = await _repoService.fetchRepoIndex(url);
        } catch (e) {
          // Keep cached version on failure
          debugPrint('Failed to refresh $url: $e');
        }
      }
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> addRepo(String url) async {
    await _repoService.addRepo(url);
    _repoUrls = await _repoService.getSavedRepos();

    try {
      _repoIndexes[url] = await _repoService.fetchRepoIndex(url);
    } catch (e) {
      debugPrint('[SourceProvider] addRepo fetch failed: $e');
      await logger.error('Failed to fetch repo: $url',
          category: LogCategory.repo, detail: e.toString());
    }

    notifyListeners();
  }

  Future<void> removeRepo(String url) async {
    // Uninstall all sources that came from this repo
    final toRemove = _installedSources
        .where((s) => s.source.repoUrl == url)
        .map((s) => s.source.id)
        .toList();
    for (final id in toRemove) {
      await _sourceManager.uninstallSource(id);
    }

    await _repoService.removeRepo(url);
    _repoUrls = await _repoService.getSavedRepos();
    _repoIndexes.remove(url);
    _installedSources = await _sourceManager.getInstalledSources();
    notifyListeners();
  }

  Future<void> installSource(MangaSource source) async {
    try {
      await _sourceManager.installSource(source);
      _installedSources = await _sourceManager.getInstalledSources();
      notifyListeners();
    } catch (e) {
      _error = 'Install failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> uninstallSource(String sourceId) async {
    await _sourceManager.uninstallSource(sourceId);
    _installedSources = await _sourceManager.getInstalledSources();
    notifyListeners();
  }

  /// Re-downloads a single installed source's code from its remote URL.
  Future<void> refreshSourceCode(String sourceId) async {
    try {
      await _sourceManager.refreshSourceCode(sourceId);
      _installedSources = await _sourceManager.getInstalledSources();
      notifyListeners();
    } catch (e) {
      _error = 'Refresh failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  /// Re-downloads every installed source's code. Returns how many succeeded.
  Future<int> refreshAllSourceCode() async {
    final count = await _sourceManager.refreshAllSourceCode();
    _installedSources = await _sourceManager.getInstalledSources();
    notifyListeners();
    return count;
  }

  bool isInstalled(String sourceId) => _sourceManager.isInstalled(sourceId);

  InstalledSource? getInstalledSource(String sourceId) {
    try {
      return _installedSources.firstWhere((s) => s.source.id == sourceId);
    } catch (_) {
      return null;
    }
  }
}
