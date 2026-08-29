import 'package:flutter/material.dart';
import '../presentation/browse_screen/browse_screen.dart';
import '../presentation/library_screen/library_screen.dart';
import '../presentation/updates_screen/updates_screen.dart';
import '../presentation/settings_screen/settings_screen.dart';
import '../presentation/global_search_screen/global_search_screen.dart';
import '../presentation/source_catalog_screen/source_catalog_screen.dart';
import '../presentation/manga_detail_screen/manga_detail_screen.dart';
import '../presentation/reader_screen/reader_screen.dart';
import '../presentation/player_screen/player_screen.dart';
import '../presentation/webview_screen/webview_screen.dart';
import '../presentation/source_creator_screen/source_creator_screen.dart';
import '../presentation/repoforge_hub_screen/repoforge_hub_screen.dart';
import '../presentation/novel_reader_screen/novel_reader_screen.dart';

/// Lets a screen know when a route pushed on top of it (e.g. a settings page)
/// has been popped, so it can re-read preferences that page may have changed.
/// The library screen subscribes to pick up Settings > Library changes without
/// an app restart.
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();

class AppRoutes {
  static const String library = '/';
  static const String updates = '/updates';
  static const String browse = '/browse';
  static const String settings = '/settings';
  static const String globalSearch = '/global-search';
  static const String sourceCatalog = '/source-catalog';
  static const String mangaDetail = '/manga-detail';
  static const String reader = '/reader';
  static const String player = '/player';
  static const String webview = '/webview';
  static const String sourceCreator = '/source-creator';
  static const String repoForgeHub = '/repoforge';
  static const String novelReader = '/novel-reader';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case library:
        return _fadeSlide(const LibraryScreen(), settings);
      case updates:
        return _fadeSlide(const UpdatesScreen(), settings);
      case browse:
        return _fadeSlide(const BrowseScreen(), settings);
      case AppRoutes.settings:
        return _fadeSlide(const SettingsScreen(), settings);
      case globalSearch:
        return _fadeSlide(const GlobalSearchScreen(), settings);
      case sourceCatalog:
        final args = settings.arguments as Map<String, dynamic>;
        return _fadeSlide(
          SourceCatalogScreen(
            sourceId: args['sourceId'] as String,
            sourceName: args['sourceName'] as String,
            initialSearchQuery: args['searchQuery'] as String?,
          ),
          settings,
        );
      case mangaDetail:
        final args = settings.arguments as Map<String, dynamic>;
        return _fadeSlide(
          MangaDetailScreen(
            mangaUrl: args['mangaUrl'] as String,
            sourceId: args['sourceId'] as String,
            title: args['title'] as String?,
            coverUrl: args['coverUrl'] as String?,
          ),
          settings,
        );
      case reader:
        final args = settings.arguments as Map<String, dynamic>;
        return _scaleFade(
          ReaderScreen(
            chapterUrl: args['chapterUrl'] as String,
            sourceId: args['sourceId'] as String,
            mangaUrl: args['mangaUrl'] as String?,
            chapterTitle: args['chapterTitle'] as String?,
            mangaTitle: args['mangaTitle'] as String?,
            chapters: args['chapters'] as List<Map<String, dynamic>>?,
            currentIndex: args['currentIndex'] as int? ?? 0,
            startPage: args['startPage'] as int? ?? 0,
          ),
          settings,
        );
      case player:
        final args = settings.arguments as Map<String, dynamic>;
        return _scaleFade(
          PlayerScreen(
            sourceId: args['sourceId'] as String,
            episodeUrl: args['episodeUrl'] as String,
            episodeTitle: args['episodeTitle'] as String?,
            animeTitle: args['animeTitle'] as String?,
            mangaUrl: args['mangaUrl'] as String?,
            episodes: args['episodes'] as List<Map<String, dynamic>>?,
            currentIndex: args['currentIndex'] as int? ?? 0,
          ),
          settings,
        );
      case sourceCreator:
        final args = settings.arguments;
        final seedUrl =
            args is Map<String, dynamic> ? args['seedUrl'] as String? : null;
        return _fadeSlide(SourceCreatorScreen(seedUrl: seedUrl), settings);
      case repoForgeHub:
        return _fadeSlide(const RepoForgeHubScreen(), settings);
      case novelReader:
        final args = settings.arguments as Map<String, dynamic>;
        return _scaleFade(
          NovelReaderScreen(
            chapterUrl: args['chapterUrl'] as String,
            sourceId: args['sourceId'] as String,
            mangaUrl: args['mangaUrl'] as String?,
            chapterTitle: args['chapterTitle'] as String?,
            mangaTitle: args['mangaTitle'] as String?,
            chapters: (args['chapters'] as List?)?.cast<Map<String, dynamic>>(),
            currentIndex: args['currentIndex'] as int? ?? 0,
            startOffset: args['startOffset'] as int? ?? 0,
          ),
          settings,
        );
      case webview:
        final args = settings.arguments as Map<String, dynamic>;
        return _fadeSlide(
          WebViewScreen(
            url: args['url'] as String,
            title: args['title'] as String? ?? 'WebView',
            cloudflareMode: args['cloudflareMode'] as bool? ?? false,
          ),
          settings,
        );
      default:
        return _fadeSlide(const LibraryScreen(), settings);
    }
  }

  static PageRouteBuilder _fadeSlide(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.03, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          ),
        );
      },
    );
  }

  static PageRouteBuilder _scaleFade(Widget page, RouteSettings settings) {
    return PageRouteBuilder(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
            ),
            child: child,
          ),
        );
      },
    );
  }
}
