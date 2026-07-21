import 'package:flutter/foundation.dart';
import '../../eval/interface.dart';
import '../../eval/lib.dart';
import '../models/installed_source_model.dart';
import '../models/source_model.dart';
import '../../eval/model/m_manga.dart';
import '../utils/search_filter.dart';
import '../../eval/model/m_pages.dart';

enum CatalogTab { popular, latest, categories, search }

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

  // Category browsing (tube-style): a list of {name, link}; tapping one drills
  // into its videos (loaded via getListing) under the Categories tab.
  List<Map<String, String>> _categories = [];
  bool _categoriesRequested = false;
  Map<String, String>? _selectedCategory;

  List<Map<String, String>> get categories => _categories;
  Map<String, String>? get selectedCategory => _selectedCategory;
  bool get categoriesLoading => _isLoading[CatalogTab.categories] ?? false;

  /// Video sources show a "Categories" tab (in place of "Latest").
  bool get showCategoriesTab => source.isAnime;

  CatalogProvider(this._installedSource) {
    _service = getExtensionService(
        _installedSource.source, _installedSource.sourceCode);
  }

  MangaSource get source => _installedSource.source;
  CatalogTab get currentTab => _currentTab;

  // Whether this source exposes a "Latest" listing. Cached — the first read can
  // initialize the extension runtime. Drives which browse tabs are shown.
  bool? _supportsLatestCache;
  bool get supportsLatest {
    if (_supportsLatestCache != null) return _supportsLatestCache!;
    try {
      _supportsLatestCache = _service?.supportsLatest ?? true;
    } catch (_) {
      _supportsLatestCache = true;
    }
    return _supportsLatestCache!;
  }
  List<MManga> get currentManga => _manga[_currentTab] ?? [];
  bool get hasNextPage => _hasNextPage[_currentTab] ?? true;
  bool get isLoading => _isLoading[_currentTab] ?? false;
  String? get error => _error;
  String get searchQuery => _searchQuery;

  void setTab(CatalogTab tab) {
    _currentTab = tab;
    notifyListeners();
    if (tab == CatalogTab.categories) {
      ensureCategories();
      return;
    }
    if ((_manga[tab] ?? []).isEmpty && !isLoading) {
      loadMore();
    }
  }

  /// Load the category list once (for the Categories tab).
  Future<void> ensureCategories() async {
    if (_categoriesRequested) return;
    _categoriesRequested = true;
    _isLoading[CatalogTab.categories] = true;
    notifyListeners();
    try {
      _categories = await _service?.getCategories() ?? [];
    } catch (e) {
      debugPrint('[Catalog] getCategories failed: $e');
    }
    _isLoading[CatalogTab.categories] = false;
    notifyListeners();
  }

  /// Drill into a category — its videos load under the Categories tab.
  Future<void> selectCategory(Map<String, String> category) async {
    _selectedCategory = category;
    _manga[CatalogTab.categories] = [];
    _currentPage[CatalogTab.categories] = 0;
    _hasNextPage[CatalogTab.categories] = true;
    _error = null;
    notifyListeners();
    await loadMore();
  }

  /// Back out of a category to the category list.
  void clearCategory() {
    _selectedCategory = null;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (isLoading) return;
    // The Categories tab only paginates once a category is drilled into.
    if (_currentTab == CatalogTab.categories && _selectedCategory == null) {
      return;
    }
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
        case CatalogTab.categories:
          result = await _service!.getListing(_selectedCategory!['link']!, page);
        case CatalogTab.search:
          result = await _service!.search(_searchQuery, page, []);
      }

      final existing = _manga[_currentTab] ?? [];
      // Filter out non-matching "popular fallback" results on the search tab
      // (pagination still uses the raw result.hasNextPage, so load-more works).
      final incoming = _currentTab == CatalogTab.search
          ? filterSearchResults(result.list, _searchQuery)
          : result.list;
      existing.addAll(incoming);
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
