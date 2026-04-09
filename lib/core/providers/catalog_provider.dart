import 'package:flutter/foundation.dart';
import '../../eval/interface.dart';
import '../../eval/lib.dart';
import '../models/installed_source_model.dart';
import '../models/source_model.dart';
import '../../eval/model/m_manga.dart';
import '../../eval/model/m_pages.dart';

enum CatalogTab { popular, latest, search }

class CatalogProvider extends ChangeNotifier {
  final InstalledSource _installedSource;
  ExtensionService? _service;

  CatalogTab _currentTab = CatalogTab.popular;
  final Map<CatalogTab, List<MManga>> _manga = {};
  final Map<CatalogTab, int> _currentPage = {};
  final Map<CatalogTab, bool> _hasNextPage = {};
  final Map<CatalogTab, bool> _isLoading = {};
  String _searchQuery = '';
  String? _error;

  CatalogProvider(this._installedSource) {
    _service = getExtensionService(
        _installedSource.source, _installedSource.sourceCode);
  }

  MangaSource get source => _installedSource.source;
  CatalogTab get currentTab => _currentTab;
  List<MManga> get currentManga => _manga[_currentTab] ?? [];
  bool get hasNextPage => _hasNextPage[_currentTab] ?? true;
  bool get isLoading => _isLoading[_currentTab] ?? false;
  String? get error => _error;
  String get searchQuery => _searchQuery;

  void setTab(CatalogTab tab) {
    _currentTab = tab;
    notifyListeners();
    if ((_manga[tab] ?? []).isEmpty && !isLoading) {
      loadMore();
    }
  }

  Future<void> loadMore() async {
    if (isLoading) return;
    if (!(_hasNextPage[_currentTab] ?? true)) {
      debugPrint('[Catalog] loadMore skipped: hasNextPage=false for ${_currentTab.name}');
      return;
    }

    _isLoading[_currentTab] = true;
    _error = null;
    notifyListeners();

    try {
      final page = (_currentPage[_currentTab] ?? 0) + 1;
      MPages result;

      switch (_currentTab) {
        case CatalogTab.popular:
          result = await _service!.getPopular(page);
        case CatalogTab.latest:
          result = await _service!.getLatestUpdates(page);
        case CatalogTab.search:
          result = await _service!.search(_searchQuery, page, []);
      }

      final existing = _manga[_currentTab] ?? [];
      existing.addAll(result.list);
      _manga[_currentTab] = existing;
      _currentPage[_currentTab] = page;
      _hasNextPage[_currentTab] = result.hasNextPage;
    } catch (e, st) {
      _error = e.toString();
      debugPrint('[Catalog] Error loading ${_currentTab.name} for ${source.name}: $e');
      debugPrint('[Catalog] Stack: $st');
    }

    _isLoading[_currentTab] = false;
    notifyListeners();
  }

  Future<void> search(String query) async {
    _searchQuery = query;
    _manga[CatalogTab.search] = [];
    _currentPage[CatalogTab.search] = 0;
    _hasNextPage[CatalogTab.search] = true;
    _currentTab = CatalogTab.search;
    notifyListeners();
    await loadMore();
  }

  Future<void> refresh() async {
    _manga[_currentTab] = [];
    _currentPage[_currentTab] = 0;
    _hasNextPage[_currentTab] = true;
    notifyListeners();
    await loadMore();
  }

  @override
  void dispose() {
    _service?.dispose();
    super.dispose();
  }
}
