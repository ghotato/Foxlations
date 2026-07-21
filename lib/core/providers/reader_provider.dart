import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../eval/lib.dart';
import '../../eval/model/page_url.dart';
import '../models/installed_source_model.dart';
import '../services/download_service.dart';
import '../services/local_source_service.dart';
import '../services/isolate_service.dart';

enum ReadingMode { ltr, rtl, vertical, webtoon }

/// Snapshot of reader preferences loaded from SharedPreferences when a
/// chapter is opened. Read-only — to change values open the Reader settings
/// page; the next chapter open will pick up the new state.
class ReaderSettings {
  final bool fullscreen;
  final bool keepScreenOn;
  final bool showPageNumber;
  final bool grayscale;
  final bool invertColors;
  final bool invertTapZones;
  final bool volumeKeys;
  final bool autoPreload;
  final bool cropBorders;
  final String scaleType;
  final String navLayout;
  final String bgColor;
  final double fontSize;
  final double imageZoom;

  const ReaderSettings({
    this.fullscreen = true,
    this.keepScreenOn = true,
    this.showPageNumber = true,
    this.grayscale = false,
    this.invertColors = false,
    this.invertTapZones = false,
    this.volumeKeys = false,
    this.autoPreload = true,
    this.cropBorders = false,
    this.scaleType = 'Fit Screen',
    this.navLayout = 'Right & Left',
    this.bgColor = 'Black',
    this.fontSize = 16.0,
    this.imageZoom = 1.0,
  });

  static Future<ReaderSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return ReaderSettings(
      fullscreen: p.getBool('reader_fullscreen') ?? true,
      keepScreenOn: p.getBool('reader_keep_screen_on') ?? true,
      showPageNumber: p.getBool('reader_show_page_num') ?? true,
      grayscale: p.getBool('reader_grayscale') ?? false,
      invertColors: p.getBool('reader_invert_colors') ?? false,
      invertTapZones: p.getBool('reader_invert_tap') ?? false,
      volumeKeys: p.getBool('reader_volume_keys') ?? false,
      autoPreload: p.getBool('reader_auto_preload') ?? true,
      cropBorders: p.getBool('reader_crop_borders') ?? false,
      scaleType: p.getString('reader_scale_type') ?? 'Fit Screen',
      navLayout: p.getString('reader_nav_layout') ?? 'Right & Left',
      bgColor: p.getString('reader_bg_color') ?? 'Black',
      fontSize: p.getDouble('reader_font_size') ?? 16.0,
      imageZoom: p.getDouble('reader_image_zoom') ?? 1.0,
    );
  }
}

/// Marks a chapter boundary in the unified page list.
class ChapterBoundary {
  final int pageIndex; // Index in the unified pages list where this boundary sits
  final String? prevChapterName;
  final String? nextChapterName;
  final bool isLastChapter;

  const ChapterBoundary({
    required this.pageIndex,
    this.prevChapterName,
    this.nextChapterName,
    this.isLastChapter = false,
  });
}

class ReaderProvider extends ChangeNotifier {
  static const _readingModeKey = 'reader_reading_mode';

  final InstalledSource _installedSource;
  final String _chapterUrl;
  final List<Map<String, dynamic>> _chapters;
  int _currentChapterIndex;

  List<PageUrl> _pages = [];
  int _currentPage = 0;
  bool _isLoading = false;
  bool _isLoadingNext = false;
  String? _error;
  ReadingMode _readingMode = ReadingMode.ltr;
  bool _showHud = false;
  ReaderSettings _settings = const ReaderSettings();

  final int _startPage;

  // Track chapter boundaries for transition dividers
  final List<ChapterBoundary> _boundaries = [];
  // Track which chapters have been loaded into the unified list
  final Set<int> _loadedChapterIndexes = {};

  final String _sourceId;
  final String _mangaTitle;

  ReaderProvider({
    required InstalledSource installedSource,
    required String chapterUrl,
    required String sourceId,
    String mangaTitle = '',
    List<Map<String, dynamic>>? chapters,
    int currentIndex = 0,
    int startPage = 0,
  })  : _installedSource = installedSource,
        _chapterUrl = chapterUrl,
        _sourceId = sourceId,
        _mangaTitle = mangaTitle,
        _chapters = chapters ?? [],
        _currentChapterIndex = currentIndex,
        _startPage = startPage {
    _loadSavedReadingMode();
  }

  List<PageUrl> get pages => _pages;
  int get currentPage => _currentPage;
  bool get isLoading => _isLoading;
  bool get isLoadingNext => _isLoadingNext;
  String? get error => _error;
  ReadingMode get readingMode => _readingMode;
  bool get showHud => _showHud;
  ReaderSettings get settings => _settings;
  int get totalPages => _pages.length;
  bool get hasPreviousChapter => _currentChapterIndex > 0;
  bool get hasNextChapter => _currentChapterIndex < _chapters.length - 1;
  List<ChapterBoundary> get boundaries => _boundaries;

  String get currentChapterUrl =>
      _currentChapterIndex < _chapters.length
          ? _chapters[_currentChapterIndex]['url'] as String? ?? _chapterUrl
          : _chapterUrl;

  /// Display name of the chapter currently being read (for progress parsing).
  String get currentChapterName =>
      _currentChapterIndex < _chapters.length
          ? (_chapters[_currentChapterIndex]['name'] as String? ?? '')
          : '';

  /// Index of the chapter currently being read (0-based, into the chapter
  /// list passed at construction).
  int get currentChapterIndex => _currentChapterIndex;

  /// Total chapters available in the reader's chapter list.
  int get chaptersCount => _chapters.length;

  /// Returns the next chapter's `{url, name}` or null if there is none.
  Map<String, String>? get nextChapterInfo {
    final next = _currentChapterIndex + 1;
    if (next >= _chapters.length) return null;
    return {
      'url': _chapters[next]['url'] as String? ?? '',
      'name': _chapters[next]['name'] as String? ?? '',
    };
  }

  /// Returns the chapter at [offset] positions behind the current one.
  /// Used by Reader settings auto-delete to find the chapter to remove.
  Map<String, String>? chapterAtOffset(int offset) {
    final idx = _currentChapterIndex - offset;
    if (idx < 0 || idx >= _chapters.length) return null;
    return {
      'url': _chapters[idx]['url'] as String? ?? '',
      'name': _chapters[idx]['name'] as String? ?? '',
    };
  }

  String? _chapterName(int index) {
    if (index < 0 || index >= _chapters.length) return null;
    return _chapters[index]['name'] as String?;
  }

  Future<void> _loadSavedReadingMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_readingModeKey);
    if (saved != null && saved < ReadingMode.values.length) {
      _readingMode = ReadingMode.values[saved];
    }
    // Load all reader settings in one shot — used by reader_screen to apply
    // visual / behavior preferences (background, grayscale, tap zones, etc.).
    _settings = await ReaderSettings.load();
    notifyListeners();
  }

  Future<void> loadPages() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Handle local source chapters (file:// = folder, archive:// = CBZ/ZIP/etc)
      if (currentChapterUrl.startsWith('file://') || currentChapterUrl.startsWith('archive://')) {
        List<String> paths = [];
        if (currentChapterUrl.startsWith('archive://')) {
          final archivePath = currentChapterUrl.replaceFirst('archive://', '');
          paths = await LocalSourceService().getChapterPages(
            LocalChapter(name: '', path: archivePath, isArchive: true));
        } else {
          final dirPath = currentChapterUrl.replaceFirst('file://', '');
          paths = await LocalSourceService().getChapterPages(
            LocalChapter(name: '', path: dirPath));
        }
        if (paths.isNotEmpty) {
          _pages = paths.map((p) => PageUrl('file://$p')).toList();
          _currentPage = _startPage.clamp(0, _pages.length - 1);
          _loadedChapterIndexes.add(_currentChapterIndex);
          _isLoading = false;
          notifyListeners();
          debugPrint('[Reader] Loaded ${_pages.length} local pages');
          return;
        }
      }

      // Check for local downloaded files first
      if (_mangaTitle.isNotEmpty) {
        final chapterName = _chapters.isNotEmpty && _currentChapterIndex < _chapters.length
            ? (_chapters[_currentChapterIndex]['name'] as String? ?? '')
            : '';
        if (chapterName.isNotEmpty) {
          final localPages = await DownloadService().getLocalPages(
              _sourceId, _mangaTitle, chapterName);
          if (localPages.isNotEmpty) {
            _pages = localPages.map((path) => PageUrl('file://$path')).toList();
            _currentPage = _startPage.clamp(0, _pages.length - 1);
            _loadedChapterIndexes.add(_currentChapterIndex);
            _isLoading = false;
            notifyListeners();
            debugPrint('[Reader] Loaded ${_pages.length} local pages for "$chapterName"');
            return;
          }
        }
      }

      // Fetch from source
      final pages = await withExtensionService(
        _installedSource.source,
        _installedSource.sourceCode,
        (service) => service.getPageList(currentChapterUrl),
      );
      _pages = pages;
      _currentPage = _startPage.clamp(0, pages.length - 1);
      _loadedChapterIndexes.add(_currentChapterIndex);
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load the next chapter and append its pages seamlessly.
  /// Uses the background isolate to prevent OOM crashes.
  Future<void> loadNextChapter() async {
    final nextIndex = _currentChapterIndex + 1;
    if (nextIndex >= _chapters.length) return;
    if (_loadedChapterIndexes.contains(nextIndex)) return;
    if (_isLoadingNext) return;

    _isLoadingNext = true;
    _nextChapterError = false;
    notifyListeners();

    try {
      final nextUrl = _chapters[nextIndex]['url'] as String? ?? '';

      // Try isolate first (runs off main thread, no OOM risk)
      List<PageUrl>? nextPages;
      try {
        nextPages = await isolateService.call<List<PageUrl>>(
          installedSource: _installedSource,
          serviceType: 'getPageList',
          url: nextUrl,
        );
      } catch (e) {
        debugPrint('[Reader] Isolate failed: $e');
        // Isolate can't handle Cloudflare — fall back to main thread
        // Clear current pages first to free memory before WebView
        _pages = [];
        _boundaries.clear();
        _loadedChapterIndexes.clear();
        _currentPage = 0;
        _currentChapterIndex = nextIndex;
        notifyListeners();

        try {
          nextPages = await withExtensionService(
            _installedSource.source,
            _installedSource.sourceCode,
            (service) => service.getPageList(nextUrl),
          );
        } catch (e2) {
          debugPrint('[Reader] Main thread also failed: $e2');
          _nextChapterError = true;
          _isLoadingNext = false;
          notifyListeners();
          return;
        }
      }

      if (nextPages != null && nextPages.isNotEmpty) {
        if (_pages.isNotEmpty) {
          // Seamless append (isolate succeeded)
          _boundaries.add(ChapterBoundary(
            pageIndex: _pages.length,
            prevChapterName: _chapterName(_currentChapterIndex),
            nextChapterName: _chapterName(nextIndex),
          ));
          _pages.addAll(nextPages);
          _loadedChapterIndexes.add(nextIndex);
          _currentChapterIndex = nextIndex;
        } else {
          // Full reload (main thread fallback cleared pages)
          _pages = nextPages;
          _loadedChapterIndexes.add(nextIndex);
        }
      }
    } catch (e) {
      debugPrint('[Reader] Failed to load next chapter: $e');
      _nextChapterError = true;
    }

    _isLoadingNext = false;
    notifyListeners();
  }

  bool _nextChapterError = false;
  bool get nextChapterError => _nextChapterError;

  /// Check if a page index is a chapter boundary (transition divider).
  ChapterBoundary? getBoundaryAt(int pageIndex) {
    for (final b in _boundaries) {
      if (b.pageIndex == pageIndex) return b;
    }
    return null;
  }

  /// Whether this is the last available chapter.
  bool get isLastChapter => _currentChapterIndex >= _chapters.length - 1;

  void setPage(int page) {
    _currentPage = page.clamp(0, _pages.length - 1);
    notifyListeners();
  }

  void toggleHud() {
    _showHud = !_showHud;
    notifyListeners();
  }

  Future<void> setReadingMode(ReadingMode mode) async {
    _readingMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_readingModeKey, mode.index);
  }

  Future<void> goToNextChapter() async {
    if (!hasNextChapter) return;
    _currentChapterIndex++;
    _pages = [];
    _boundaries.clear();
    _loadedChapterIndexes.clear();
    _currentPage = 0;
    notifyListeners();
    await loadPages();
  }

  Future<void> goToPreviousChapter() async {
    if (!hasPreviousChapter) return;
    _currentChapterIndex--;
    _pages = [];
    _boundaries.clear();
    _loadedChapterIndexes.clear();
    _currentPage = 0;
    notifyListeners();
    await loadPages();
  }
}
