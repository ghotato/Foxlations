import 'package:flutter/foundation.dart';
import '../models/source_model.dart';
import '../models/installed_source_model.dart';
import '../services/app_logger.dart';
import '../services/repo_service.dart';
import '../services/source_manager.dart';

class SourceProvider extends ChangeNotifier {
  final RepoService _repoService = RepoService();
  final SourceManager _sourceManager = SourceManager();

  List<String> _repoUrls = [];
  Map<String, RepoIndexResult> _repoIndexes = {};
  List<InstalledSource> _installedSources = [];
  bool _isLoading = false;
  String? _error;

  List<String> get repoUrls => _repoUrls;
  Map<String, RepoIndexResult> get repoIndexes => _repoIndexes;
  List<InstalledSource> get installedSources => _installedSources;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// All available sources across all repos.
  List<MangaSource> get allSources =>
      _repoIndexes.values.expand((r) => r.sources).toList();

  Future<void> initialize() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
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

  bool isInstalled(String sourceId) => _sourceManager.isInstalled(sourceId);

  InstalledSource? getInstalledSource(String sourceId) {
    try {
      return _installedSources.firstWhere((s) => s.source.id == sourceId);
    } catch (_) {
      return null;
    }
  }
}
