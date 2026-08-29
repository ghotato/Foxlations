import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/source_model.dart';
import '../models/installed_source_model.dart';
import '../models/source_settings.dart';
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
      // SourceSettings.cached() is read from sync hot paths (search fan-out,
      // update loop), so it must be warm before those run.
      await SourceSettings.preload(_installedSources.map((s) => s.source.id));
      // The HTTP layer checks desktop mode by host on every request and can't
      // await, so the host set has to be in memory before any source runs.
      await SourceSettings.preloadDesktopHosts();

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
    } else if (_installedSources.isNotEmpty) {
      // Otherwise just refresh the repo indexes (small JSON) in the background so
      // the "updates available" badge reflects the latest published versions.
      // ignore: unawaited_futures
      refreshReposQuiet();
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

  // ── Extension update detection ────────────────────────────────────────────
  // Compares each installed source's stored version against the current version
  // in its repo index (matched by the stable source id). Drives the "N updates"
  // badge on the Browse tab + the list header in the Extensions tab.

  Map<String, MangaSource> get _availableById {
    final m = <String, MangaSource>{};
    for (final s in allSources) {
      m[s.id] = s;
    }
    return m;
  }

  List<int> _verParts(String v) => v
      .split(RegExp(r'[.\-+ ]'))
      .map((x) => int.tryParse(x.replaceAll(RegExp(r'\D'), '')) ?? 0)
      .toList();

  bool _isNewer(String repoV, String installedV) {
    final pa = _verParts(repoV);
    final pb = _verParts(installedV);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va > vb;
    }
    return false;
  }

  /// Installed sources whose repo now offers a newer version.
  List<InstalledSource> get sourcesWithUpdates {
    final byId = _availableById;
    return _installedSources.where((s) {
      final repo = byId[s.source.id];
      return repo != null && _isNewer(repo.version, s.source.version);
    }).toList();
  }

  /// Sources with updates that belong to the CURRENT space: only vaulted sources
  /// when the vault is open, only non-vault sources otherwise — so a vaulted
  /// source's update never surfaces in the normal Browse view (and vice-versa).
  List<InstalledSource> updatesForContext({
    required bool vaultActive,
    required Set<String> vaultIds,
  }) {
    return sourcesWithUpdates.where((s) {
      final inVault = vaultIds.contains(s.source.id);
      return vaultActive ? inVault : !inVault;
    }).toList();
  }

  bool hasUpdate(String sourceId) {
    final repo = _availableById[sourceId];
    if (repo == null) return false;
    for (final s in _installedSources) {
      if (s.source.id == sourceId) return _isNewer(repo.version, s.source.version);
    }
    return false;
  }

  /// Update one source: re-install from its repo entry, which records the new
  /// version and re-downloads the code/jar (installSource upserts by id).
  /// Returns true if a repo entry was found and (re)installed; false if there was
  /// no matching repo source to update from.
  Future<bool> updateSource(String sourceId) async {
    final repo = _availableById[sourceId];
    if (repo == null) return false;
    await installSource(repo);
    return true;
  }

  /// Update the given sources from their repo entries. Returns how many succeeded.
  /// Callers pass the ids for the current space (see [updatesForContext]) so a
  /// hidden vaulted source is never updated from the normal view.
  Future<int> updateAll(List<String> ids) async {
    var n = 0;
    for (final id in ids) {
      try {
        if (await updateSource(id)) n++;
      } catch (_) {}
    }
    return n;
  }

  /// Refresh repo indexes in the background (no loading spinner) so the update
  /// badge reflects the latest published versions without a manual pull-to-refresh.
  Future<void> refreshReposQuiet() async {
    for (final url in _repoUrls) {
      try {
        _repoIndexes[url] = await _repoService.fetchRepoIndex(url);
      } catch (_) {}
    }
    notifyListeners();
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
