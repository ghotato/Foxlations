import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../presentation/webview_screen/cf_challenge_screen.dart';
import 'package:dio/dio.dart';

import 'selector_extractor.dart';
import 'selector_knowledge_base.dart';

/// Detects the framework of a manga/anime source URL.
///
/// Primary path: loads the URL in a [HeadlessInAppWebView] so that Cloudflare
/// JS challenges are solved by the real browser engine, then extracts the
/// fully-rendered HTML via `document.documentElement.outerHTML`.
///
/// Fallback path (web platform or WebView unavailable): plain Dio HTTP fetch.
class FrameworkDetectorService {
  // ─── Dio fallback ────────────────────────────────────────────────────────
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
        'Accept-Encoding': 'gzip, deflate, br',
        'Cache-Control': 'no-cache',
      },
      followRedirects: true,
      maxRedirects: 5,
    ),
  );

  // ─── Framework signatures (HTML pattern matching) ────────────────────────
  static const List<_FrameworkSig> _signatures = [
    _FrameworkSig(
      name: 'Madara',
      patterns: [
        // Core WordPress/Madara identifiers
        'wp-manga',
        'madara',
        'madara-core',
        'madara-extra-header',
        // Listing page selectors (from Madara.kt source)
        'page-item-detail',
        'c-tabs-item__content',
        'manga__item',
        // Detail page selectors
        'post-title',
        'author-content',
        'artist-content',
        'description-summary',
        'summary__content',
        'summary_image',
        'genres-content',
        'tags-content',
        // Chapter list
        'wp-manga-chapter',
        'chapter-release-date',
        // Page/reading view
        'page-break',
        'blocks-gallery-item',
        'reading-content',
        'manga-reading-content',
        // AJAX admin endpoint
        'admin-ajax.php',
        // Legacy patterns
        'manga-chapters-holder',
        'wp-manga-list',
      ],
      confidence: 92,
      contentType: 'Manga',
      version: '1.6.x',
    ),
    _FrameworkSig(
      name: 'MangaBox',
      patterns: [
        // Listing page class names (from MangaBox.kt source)
        'truyen-list',
        'list-truyen-item-wrap',
        'panel_story_list',
        'story_item',
        'list-comic-item-wrap',
        // Detail page class names
        'manga-info-top',
        'panel-story-info',
        'manga-info-pic',
        'panel-story-info-description',
        // Chapter reader
        'container-chapter-reader',
        'navi-change-chapter-btn',
        'btn-navigation-chap',
        // URL path signals present in href attributes
        'manga-list/hot-manga',
        'manga-list/latest-manga',
        'search/story/',
        '/api/manga/',
        // Legacy class names / site-specific identifiers
        'panel-manga-list',
        'row-content-chapter',
        'manganato',
        'mangakakalot',
        'mangabat',
        'chapmanganato',
      ],
      confidence: 88,
      contentType: 'Manga',
      version: '2.x',
    ),
    _FrameworkSig(
      name: 'MangaStream',
      patterns: [
        // Listing selectors (from MangaThemesia.kt source)
        'listupd',
        'bsx',
        'utao',
        // Detail page selectors
        'entry-title',
        'ts-breadcrumb',
        'infomanga',
        'thumb img',
        'seriestugenre',
        'mgen',
        // Chapter list
        'chapternum',
        'chapterdate',
        'eph-num',
        // Reader area & lazy-load attrs
        'readerarea',
        'data-lazy-src',
        'data-cfsrc',
        // Legacy / site-specific
        'mangastream',
        'readms',
        'wd-manga',
        'bixbox',
        'komikcast',
        'ts-main-image',
      ],
      confidence: 85,
      contentType: 'Manga',
      version: '3.x',
    ),
    _FrameworkSig(
      name: 'Fansub CMS',
      patterns: [
        'fansub',
        'fansubco',
        'fansub-cms',
        'chapter-list-two',
        'fansub-reader',
      ],
      confidence: 80,
      contentType: 'Manga',
      version: '1.x',
    ),
    _FrameworkSig(
      name: 'Zorotheme (Anime)',
      patterns: [
        'zorotheme',
        'aniwave',
        'film_list-wrap',
        'flw-item',
        'film-poster',
        'hianime',
        'aniwatch',
        'film-detail',
        'tick-dub',
        'tick-sub',
        'film-name',
      ],
      confidence: 90,
      contentType: 'Anime',
      version: '2.x',
    ),
    _FrameworkSig(
      name: 'AniList API',
      patterns: [
        'anilist',
        'graphql',
        '"data":{"Page"',
        '"mediaList"',
        'AniList',
      ],
      confidence: 97,
      contentType: 'Anime',
      version: 'GraphQL',
    ),
    _FrameworkSig(
      name: 'REST API',
      patterns: [
        '"results":[',
        '"data":[',
        '"manga":[',
        '"chapters":[',
        '"relationships":[',
        '"total":',
        '"limit":',
        '"offset":',
      ],
      confidence: 95,
      contentType: 'Manga',
      version: 'REST',
    ),
    _FrameworkSig(
      name: 'WordPress (Generic)',
      patterns: [
        'wp-content',
        'wp-includes',
        'wordpress',
        'woocommerce',
        'wp-json',
        'wp-block',
      ],
      confidence: 70,
      contentType: 'Manga',
      version: 'WP',
    ),
    _FrameworkSig(
      name: 'MangaThemesia',
      patterns: [
        // Core theme identifiers
        'themesia',
        'mangathemesia',
        // Site-specific identifiers using this theme
        'komiku',
        'mangasusu',
        'shinigami',
        'mangakita',
        // Unique selectors from MangaThemesia.kt
        'postbody',
        'animefull',
        'bigcontent',
        'seriestucontainer',
        'tls',
        'dynamic_view_ajax',
        'gnr',
        // Also shares some MangaStream patterns
        'bixbox',
        'ts-breadcrumb',
        'readerarea',
      ],
      confidence: 87,
      contentType: 'Manga',
      version: '2.x',
    ),
    _FrameworkSig(
      name: 'MMRCMS',
      patterns: [
        // Distinctive My Manga Reader CMS class names (from mmrcms.dart source)
        'mangalist',
        'manga-item',
        'chapter-container',
        'manga-heading',
        'media-heading',
        'listmanga-header',
        'chapter-title-rtl',
        'date-chapter-title-rtl',
        // Bootstrap-3 scaffolding MMRCMS ships with (weaker on their own)
        'img-responsive',
        'dl-horizontal',
        'mangareadercms',
      ],
      confidence: 85,
      contentType: 'Manga',
      version: 'MMRCMS',
    ),
    _FrameworkSig(
      name: 'HeanCMS',
      patterns: [
        // API-driven manhwa CMS (Laravel + Next.js). Markers appear in the
        // embedded JSON / API request URLs.
        'heancms',
        'series_slug',
        '/api/query',
        '/api/chapter/query',
        'total_views',
        'series_type',
        'series_status',
      ],
      confidence: 88,
      contentType: 'Manga',
      version: 'HeanCMS',
    ),
    _FrameworkSig(
      name: 'MadTheme',
      patterns: [
        'madtheme',
        'book-detailed-item',
        'novel-detailed-item',
        'sb.mbcdn.xyz',
        'image-request',
      ],
      confidence: 85,
      contentType: 'Manga',
      version: 'MadTheme',
    ),
    _FrameworkSig(
      name: 'ZeistManga',
      patterns: [
        // Blogger-based manga theme.
        'zeistmanga',
        'gtc-235fr',
        'y6x11p',
        'clwd.club',
        'dt-init',
      ],
      confidence: 83,
      contentType: 'Manga',
      version: 'ZeistManga',
    ),
    _FrameworkSig(
      name: 'KeyoApp',
      patterns: [
        'keyoapp',
        'data-uid',
        'uid=',
        'grid-cols',
      ],
      confidence: 80,
      contentType: 'Manga',
      version: 'KeyoApp',
    ),
    // FlameComics + clones: Next.js `_next/data/{buildId}` with a series_id
    // schema. Strong 3-pattern match beats KeyoApp's weak (Tailwind) match.
    _FrameworkSig(
      name: 'FlameComics',
      patterns: [
        'flamecomics',
        '"series_id"',
        '"buildid"',
      ],
      confidence: 92,
      contentType: 'Manga',
      version: 'FlameComics',
    ),
    _FrameworkSig(
      name: 'WPComics',
      patterns: [
        'wpcomics',
        'tim-truyen',
        'article#item-detail',
        'div.items div.item',
        'other-name',
      ],
      confidence: 84,
      contentType: 'Manga',
      version: 'WPComics',
    ),
    _FrameworkSig(
      name: 'FMReader',
      patterns: [
        'fmreader',
        'manga-list.html',
        'm_status',
        'ungenre',
      ],
      confidence: 82,
      contentType: 'Manga',
      version: 'FMReader',
    ),
    _FrameworkSig(
      name: 'Kemono / Coomer',
      patterns: [
        // Creator-aggregator (Patreon/Fanbox/OnlyFans mirrors). JSON API.
        'kemono',
        'coomer',
        '/api/v1/',
        'post-card',
        'data-service',
        '?o=0',
      ],
      confidence: 90,
      contentType: 'Manga',
      version: 'Kemono',
    ),
    _FrameworkSig(
      name: 'GalleryAdults (nhentai-style)',
      patterns: [
        'galleryadults',
        'advsearch',
        'div.gallery',
        'div.thumb',
        '/g/',
        'tag/parody',
      ],
      confidence: 82,
      contentType: 'Manga',
      version: 'GalleryAdults',
    ),
    _FrameworkSig(
      name: 'GuyaMoe / Cubari',
      patterns: [
        'guya.moe',
        'cubari',
        'guya-embed',
        'reader-controls',
        'guya-reader',
        'cubari-reader',
      ],
      confidence: 90,
      contentType: 'Manga',
      version: '1.x',
    ),
    _FrameworkSig(
      name: 'MangaDex',
      patterns: [
        'mangadex',
        '"baseUrl"',
        'at-home/server',
        '"attributes":{"volume"',
        '"chapter":{"hash"',
        'mangadex.org',
        '"relationships":[{"id"',
      ],
      confidence: 96,
      contentType: 'Manga',
      version: 'REST v5',
    ),
    _FrameworkSig(
      name: 'Webtoon (LINE/NAVER)',
      patterns: [
        'webtoon',
        'viewer_lst',
        'viewer-img',
        'episode-viewer',
        'linewebtoon',
        'viewer_img_wrap',
        'naver',
        'webtoons.com',
        'comic-viewer',
      ],
      confidence: 88,
      contentType: 'Manga',
      version: '3.x',
    ),
    _FrameworkSig(
      name: 'Tapas',
      patterns: [
        'tapas-viewer',
        'tapas-episode',
        'tapas.io',
        'episodeviewer',
        'tapastic',
        'tap-episode',
      ],
      confidence: 85,
      contentType: 'Manga',
      version: '2.x',
    ),
    _FrameworkSig(
      name: 'Gogoanime',
      patterns: [
        'gogoanime',
        'anime_video_body',
        'loadserver',
        'anime_info_body',
        'gogo-stream',
        'gogocdn',
        'gogoanime.com',
        'gogoanimetv',
      ],
      confidence: 89,
      contentType: 'Anime',
      version: '3.x',
    ),
    _FrameworkSig(
      name: '9anime / Aniwave',
      patterns: [
        '9anime',
        '9a-js',
        'player-wrapper',
        'a-episodes',
        'aniwave',
        '9animetv',
        'a-filter',
        'nine-anime',
      ],
      confidence: 86,
      contentType: 'Anime',
      version: '2.x',
    ),
    _FrameworkSig(
      name: 'MangaSee / MangaLife',
      patterns: [
        'vm.Pages',
        'vm.CurChapter',
        'vm.IndexName',
        'vm.MMID',
        'vm.CurPathName',
        'mangasee123',
        'manga4life',
        'vm.ChapterDisplay',
      ],
      confidence: 91,
      contentType: 'Manga',
      version: 'JS',
    ),
    _FrameworkSig(
      name: 'Komga',
      patterns: [
        'komga',
        'komga-server',
        '"pageCount"',
        '"mediaType"',
        'komga-user',
        'opds/v1',
        '"readStatus"',
      ],
      confidence: 94,
      contentType: 'Manga',
      version: 'API',
    ),
    _FrameworkSig(
      name: 'Kavita',
      patterns: [
        'kavita',
        'kavita-server',
        '"volumes"',
        '"chapterCount"',
        'api/series',
        'kavitareader',
        '"readingDirection"',
      ],
      confidence: 93,
      contentType: 'Manga',
      version: 'API',
    ),
    _FrameworkSig(
      name: 'KVS (Kernel Video Sharing)',
      patterns: [
        // Core KVS identifiers
        'kvs_',
        'kernel',
        'video_player_code',
        'block_videos',
        // Listing page
        'listingVideos',
        '.item .thumb',
        'player.php',
        // Embed / stream paths
        '/embed/',
        '/get_file/',
        'player_code',
        // Common KVS class names
        'thumb-block',
        'video-box',
        'info-block',
        // KVS player config attribute
        'data-config',
      ],
      confidence: 88,
      contentType: 'Anime',
      version: 'KVS',
    ),
    _FrameworkSig(
      name: 'xVideos Engine',
      patterns: [
        'xvideos',
        'xv-',
        'html5video',
        'video_html5_api',
        'xvideo_url',
        'setVideoUrl(',
        'xvideos-cdn.com',
        'xv-player',
        '.thumb-block',
        'xvideos.com',
      ],
      confidence: 95,
      contentType: 'Anime',
      version: 'XV',
    ),
    _FrameworkSig(
      name: 'xHamster Engine',
      patterns: [
        'xhamster',
        'xhfw-',
        'ham-',
        'xh-player',
        'hamsterporn',
        'xhcdn.com',
        '.thumb-list',
        'xh-icon',
      ],
      confidence: 93,
      contentType: 'Anime',
      version: 'XH',
    ),
    _FrameworkSig(
      name: 'ClipBucket',
      patterns: [
        'clipbucket',
        'clip_bucket',
        'cb_',
        'cbvideo',
        'ClipBucket',
        '/clipbucket/',
        'cb-player',
      ],
      confidence: 90,
      contentType: 'Anime',
      version: 'CB',
    ),
    _FrameworkSig(
      name: 'PHPMotion',
      patterns: [
        'phpmotion',
        'pm_player',
        'phpMotion',
        '/phpmotion/',
        'pm-video',
      ],
      confidence: 88,
      contentType: 'Anime',
      version: 'PHPMotion',
    ),
    _FrameworkSig(
      name: 'WP Ultimate Clips',
      patterns: [
        'wp-clips',
        'wpuc_',
        'ultimate-clips',
        'wpultimatemember',
        'clips-player',
        'wp-clip-',
      ],
      confidence: 85,
      contentType: 'Anime',
      version: 'WPUC',
    ),
    _FrameworkSig(
      name: 'YouTube',
      patterns: [
        'ytInitialData',
        'ytInitialPlayerResponse',
        'ytplayer.config',
        'ytd-video-renderer',
        'ytd-thumbnail',
        'ytd-app',
        'ytd-rich-item-renderer',
        'i.ytimg.com',
        '/youtubei/v1/',
        'yt-formatted-string',
        'youtube.com/watch',
      ],
      confidence: 99,
      contentType: 'Anime',
      version: 'YouTube API v1',
    ),
    _FrameworkSig(
      name: 'Generic Video Host',
      patterns: [
        '<video',
        'video/mp4',
        'video/webm',
        '.m3u8',
        '.mpd',
        'jwplayer',
        'videojs',
        'og:video',
        'hls.js',
        'dash.js',
        'plyr',
        'streamtape',
        'doodstream',
        'mixdrop',
        'filemoon',
        'mp4upload',
        'vidcloud',
        'streamwish',
        'vidhide',
        'embedsito',
      ],
      confidence: 82,
      contentType: 'Anime',
      version: 'Video',
    ),
  ];

  // Near-unique, high-signal tokens (brands, domains, JS globals). A single
  // one of these is enough to accept a framework even at match-score 1.
  static const Set<String> _strongTokens = {
    'wp-manga', 'madara', 'mangathemesia', 'themesia', 'mangadex.org',
    'anilist', 'ytinitialplayerresponse', 'ytinitialdata', 'vm.pages',
    'komga', 'kavita', 'guya.moe', 'cubari', 'webtoons.com', 'tapas.io',
    'gogoanime', '9anime', 'manganato', 'mangakakalot', 'chapmanganato',
    'mangareadercms', 'xvideos', 'xhamster', 'clipbucket', 'phpmotion',
    'at-home/server', 'zorotheme', 'hianime',
    'heancms', 'series_slug', 'madtheme', 'book-detailed-item',
    'zeistmanga', 'gtc-235fr', 'keyoapp', 'sb.mbcdn.xyz',
    'tim-truyen', 'ungenre', 'm_status', 'fmreader', 'wpcomics',
    'kemono', 'coomer', 'galleryadults', 'advsearch',
  };

  // Frameworks that are adult/NSFW by nature. Detection still works when the
  // user has adult sources enabled; the flag drives the generated extension's
  // contentWarning / isNsfw fields and the in-app gating.
  static const Set<String> _nsfwFrameworks = {
    'KVS (Kernel Video Sharing)',
    'xVideos Engine',
    'xHamster Engine',
    'ClipBucket',
    'PHPMotion',
    'WP Ultimate Clips',
    'Kemono / Coomer',
    'GalleryAdults (nhentai-style)',
  };

  // ─── Public API ──────────────────────────────────────────────────────────

  /// Detect the framework for [url].
  /// Uses an invisible WebView on mobile/desktop so Cloudflare challenges are
  /// solved by the real browser engine before HTML is extracted.
  static Future<Map<String, dynamic>> detect(
    String url, {
    void Function(int step)? onStep,
  }) async {
    final normalizedUrl = _normalizeUrl(url);
    final parsedUri = Uri.tryParse(normalizedUrl);
    final host = parsedUri?.host.toLowerCase() ?? '';

    // Step 1 – attempt WebView-based fetch (bypasses Cloudflare)
    onStep?.call(1);
    String html = '';

    if (!kIsWeb) {
      // Mobile / desktop: use headless WebView
      html = await _fetchViaWebView(normalizedUrl);
    }

    // Step 2 – fallback to Dio if WebView returned nothing
    onStep?.call(2);
    if (html.isEmpty) {
      html = await _fetchViaDio(normalizedUrl, parsedUri, host);
    }

    // If the page is still empty or a Cloudflare challenge, ask the user to
    // complete it in a visible WebView, then re-fetch.
    if (html.trim().isEmpty || _looksLikeCfChallenge(html)) {
      final solved = await solveCloudflareInteractively(normalizedUrl);
      if (solved && !kIsWeb) {
        final refetched = await _fetchViaWebView(normalizedUrl);
        if (refetched.trim().isNotEmpty) html = refetched;
      }
    }

    // Fail honestly instead of fabricating a low-confidence "Custom" result:
    // an empty response means the site was unreachable, blocked (Cloudflare),
    // or returned nothing. The caller surfaces this as an error.
    if (html.trim().isEmpty) {
      throw Exception(
        'Could not fetch the page — the site may be unreachable, blocked by '
        'Cloudflare, or returned an empty response.',
      );
    }

    // Step 3 – match framework signatures against the rendered HTML
    onStep?.call(3);
    final lowerHtml = html.toLowerCase();
    _FrameworkSig? bestSig;
    int bestScore = 0;

    for (final sig in _signatures) {
      int score = 0;
      for (final p in sig.patterns) {
        if (lowerHtml.contains(p.toLowerCase())) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        bestSig = sig;
      }
    }

    // Step 4 – scan endpoints
    onStep?.call(4);

    // Step 5 – resolve final result
    onStep?.call(5);

    String framework;
    String contentType;
    String version;
    int confidence;

    final bestMatched = bestSig == null
        ? const <String>[]
        : bestSig.patterns
              .where((p) => lowerHtml.contains(p.toLowerCase()))
              .toList();
    final hasStrongMatch = bestMatched.any(
      (p) => _strongTokens.contains(p.toLowerCase()),
    );

    // Require ≥2 matching patterns to claim a framework, unless the single
    // match is a strong near-unique token. Prevents spurious 1-pattern hits
    // (e.g. a stray "webtoon" / "comic-viewer" string) from mislabelling sites.
    if (bestSig != null &&
        (bestScore >= 2 || (bestScore == 1 && hasStrongMatch))) {
      framework = bestSig.name;
      contentType = bestSig.contentType;
      version = bestSig.version;

      // Confidence from the ABSOLUTE number of matched markers (don't penalise
      // signatures that simply define many possible patterns — a site rarely
      // exposes all of them), capped at the signature's ceiling. A strong
      // near-unique token bumps it further.
      confidence = (50 + bestScore * 9).clamp(45, bestSig.confidence);
      if (hasStrongMatch) {
        confidence = (confidence + 8).clamp(confidence, bestSig.confidence);
      }
    } else {
      // Unknown — custom scraping
      final hasMangaKeywords = _countKeywords(lowerHtml, [
        'manga',
        'chapter',
        'manhwa',
        'manhua',
      ]);
      final hasAnimeKeywords = _countKeywords(lowerHtml, [
        'anime',
        'episode',
        'stream',
        'watch',
      ]);
      final totalKeywords = hasMangaKeywords + hasAnimeKeywords;

      confidence = html.isNotEmpty
          ? (45 + (totalKeywords * 3).clamp(0, 30))
          : 30;
      framework = 'Custom';
      contentType = hasAnimeKeywords > hasMangaKeywords ? 'Anime' : 'Manga';
      version = 'Unknown';
    }

    // Light-novel KB override (reference-derived from LNReader plugin site
    // lists): if this host is a known novel site, force the Novel content type
    // and, when the KB knows the framework, use it — so RepoForge generates a
    // novel source (text reader) with a working browsing body. When the live
    // HTML signature independently found Madara/MangaThemesia, keep that.
    final novelEntry = await SelectorKnowledgeBase.novelLookup(normalizedUrl);
    if (novelEntry != null) {
      contentType = 'Novel';
      final kbFw = (novelEntry['framework'] as String?) ?? 'Custom';
      final sigIsNovelFramework =
          framework == 'Madara' || framework == 'MangaThemesia';
      if (kbFw != 'Custom' && !sigIsNovelFramework) {
        framework = kbFw;
        version = _sigByName(kbFw)?.version ?? version;
      }
      if (confidence < 88) confidence = 88;
    }

    final endpoints = _buildEndpoints(
      framework == 'Custom' ? null : _sigByName(framework),
      normalizedUrl,
      lowerHtml,
    );

    // Detect language from html lang attribute
    final langMatch = RegExp(
      r"""<html[^>]+lang=["']([a-z]{2})""",
      caseSensitive: false,
    ).firstMatch(html);
    final language = langMatch?.group(1)?.toUpperCase() ?? 'EN';

    final mediaSelectors = _buildMediaSelectors(framework);
    final detectedMedia = _extractVideoPatterns(html);

    // For custom/unknown sites: prefer the community-verified selectors for
    // this exact site (knowledge base of ~960 sites), then fall back to
    // heuristic DOM extraction. Known frameworks keep their canonical selectors.
    var extractedSelectors = <String, String>{};
    var fromKb = false;
    if (framework == 'Custom') {
      final known = await SelectorKnowledgeBase.selectorsFor(normalizedUrl);
      if (known != null) {
        extractedSelectors = known;
        fromKb = true;
      } else {
        extractedSelectors = SelectorExtractor.extract(html);
      }
    }

    // Best-effort deep scan for brand-new custom sites: fetch a sample detail +
    // reader page to recover real chapter-list and page-image selectors that a
    // single listing-page fetch can't provide. Isolated — never breaks detect.
    if (framework == 'Custom' &&
        !fromKb &&
        extractedSelectors.isNotEmpty &&
        !extractedSelectors.containsKey('chapters')) {
      onStep?.call(5);
      final deep = await _deepSelectors(normalizedUrl, html, extractedSelectors);
      extractedSelectors = {...extractedSelectors, ...deep};
    }

    final imageSelectors = Map<String, String>.from(
      (mediaSelectors['imageSelectors'] ?? const <String, String>{}),
    );
    final coverAttr = extractedSelectors['coverAttr'];
    if (coverAttr != null && coverAttr.isNotEmpty) {
      imageSelectors['lazyAttr'] = coverAttr;
    }

    return {
      'framework': framework,
      'confidence': confidence,
      'contentType': contentType,
      'version': version,
      'language': language,
      'endpoints': endpoints,
      'sourceUrl': normalizedUrl,
      'nsfw': _nsfwFrameworks.contains(framework),
      'isApiSource':
          framework == 'Custom' &&
          await SelectorKnowledgeBase.isApiSource(normalizedUrl),
      'selectors': extractedSelectors,
      'imageSelectors': imageSelectors,
      'videoSelectors': mediaSelectors['videoSelectors'],
      'detectedMedia': detectedMedia,
      'categories': SelectorExtractor.extractCategories(html, normalizedUrl),
    };
  }

  // ─── WebView fetch (Cloudflare bypass) ───────────────────────────────────

  /// Loads [url] in a [HeadlessInAppWebView], waits for the page to fully
  /// render (including JS challenges), then extracts the outer HTML.
  static Future<String> _fetchViaWebView(String url) async {
    final completer = Completer<String>();
    HeadlessInAppWebView? headlessWebView;

    // Safety timeout — if the page never fires onLoadStop we still continue
    final timeout = Timer(const Duration(seconds: 20), () {
      if (!completer.isCompleted) completer.complete('');
    });

    try {
      headlessWebView = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          userAgent:
              'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
          // Don't load images/media — we only need HTML
          blockNetworkImage: true,
          loadsImagesAutomatically: false,
          mediaPlaybackRequiresUserGesture: true,
          allowsInlineMediaPlayback: false,
          // Follow redirects (important for Cloudflare)
          javaScriptCanOpenWindowsAutomatically: false,
          disableDefaultErrorPage: true,
        ),
        onLoadStop: (controller, loadedUrl) async {
          if (completer.isCompleted) return;
          try {
            // Give JS a moment to finish rendering after load
            await Future.delayed(const Duration(milliseconds: 800));
            final result = await controller.evaluateJavascript(
              source: 'document.documentElement.outerHTML',
            );
            final html = result?.toString() ?? '';
            timeout.cancel();
            completer.complete(html);
          } catch (_) {
            if (!completer.isCompleted) completer.complete('');
          }
        },
        onReceivedError: (controller, request, error) {
          if (!completer.isCompleted) completer.complete('');
        },
      );

      await headlessWebView.run();
      final html = await completer.future;
      return html;
    } catch (_) {
      if (!completer.isCompleted) completer.complete('');
      return '';
    } finally {
      timeout.cancel();
      try {
        await headlessWebView?.dispose();
      } catch (_) {}
    }
  }

  // ─── Dio fallback fetch ───────────────────────────────────────────────────

  static Future<String> _fetchViaDio(
    String url,
    Uri? parsedUri,
    String host,
  ) async {
    try {
      final response = await _dio.get<String>(url);
      return response.data ?? '';
    } catch (_) {
      try {
        final baseOnly =
            '${parsedUri?.scheme ?? "https"}://${parsedUri?.host ?? host}';
        final response = await _dio.get<String>(baseOnly);
        return response.data ?? '';
      } catch (_) {
        return '';
      }
    }
  }

  // ─── Deep scan (sample detail + reader page) ──────────────────────────────

  /// Fetch rendered HTML for [url]: WebView first (solves Cloudflare on device),
  /// Dio fallback.
  static Future<String> _fetchHtml(String url) async {
    var html = kIsWeb ? '' : await _fetchViaWebView(url);
    if (html.isEmpty) {
      final u = Uri.tryParse(url);
      html = await _fetchViaDio(url, u, u?.host.toLowerCase() ?? '');
    }
    return html;
  }

  /// For a brand-new custom site: walk listing → a detail page → a reader page,
  /// extracting the chapter-list and page-image selectors. Best-effort; returns
  /// `{}` on any failure so detection is never blocked.
  static Future<Map<String, String>> _deepSelectors(
    String baseUrl,
    String listingHtml,
    Map<String, String> sel,
  ) async {
    final out = <String, String>{};
    try {
      final detailUrl = SelectorExtractor.firstDetailUrl(
        listingHtml,
        baseUrl,
        itemSel: sel['item'] ?? sel['popular'],
        titleSel: sel['title'],
      );
      if (detailUrl == null) return out;
      final detailHtml = await _fetchHtml(detailUrl);
      if (detailHtml.isEmpty) return out;
      out.addAll(
        SelectorExtractor.extractChapters(
          detailHtml,
          candidates: await SelectorKnowledgeBase.candidatesFor('chapters'),
        ),
      );
      final chapterUrl = SelectorExtractor.firstChapterUrl(detailHtml, baseUrl);
      if (chapterUrl == null) return out;
      final readerHtml = await _fetchHtml(chapterUrl);
      if (readerHtml.isEmpty) return out;
      out.addAll(
        SelectorExtractor.extractPages(
          readerHtml,
          candidates: await SelectorKnowledgeBase.candidatesFor('page_images'),
        ),
      );
    } catch (_) {}
    return out;
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  static int _countKeywords(String text, List<String> keywords) {
    int count = 0;
    for (final k in keywords) {
      if (text.contains(k)) count++;
    }
    return count;
  }

  static bool _looksLikeCfChallenge(String html) {
    if (html.isEmpty || html.length > 60000) return false;
    final b = html.toLowerCase();
    return b.contains('just a moment') ||
        b.contains('challenge-platform') ||
        b.contains('cf-browser-verification') ||
        b.contains('enable javascript and cookies to continue');
  }

  static _FrameworkSig? _sigByName(String name) {
    for (final sig in _signatures) {
      if (sig.name == name) return sig;
    }
    return null;
  }

  static String _normalizeUrl(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    return u;
  }

  // ─── Active video pattern extractor ─────────────────────────────────────────
  // Scans raw HTML for actual video URLs, thumbnails, titles and player type.
  // Returns concrete values found, not just CSS selectors to try later.

  static Map<String, dynamic> _extractVideoPatterns(String html) {
    final result = <String, dynamic>{
      'videoUrls': <String>[],
      'thumbnailUrl': '',
      'title': '',
      'playerType': '',
      'iframeUrl': '',
      'listThumbnailSelector': '',
      'listTitleSelector': '',
      'videoSelector': '',
    };

    // ── Title ────────────────────────────────────────────────────────────────
    final ogTitle = RegExp(
      r'''<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    final h1Title = RegExp(
      r'<h1[^>]*>([^<]{3,120})</h1>',
      caseSensitive: false,
    ).firstMatch(html);
    final pageTitle = RegExp(
      r'<title>([^<]{3,120})</title>',
      caseSensitive: false,
    ).firstMatch(html);
    result['title'] = ogTitle?.group(1)?.trim() ??
        h1Title?.group(1)?.trim() ??
        pageTitle?.group(1)?.trim() ??
        '';

    // ── Thumbnail ────────────────────────────────────────────────────────────
    final ogImage = RegExp(
      r'''<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    final videoPoster = RegExp(
      r'''<video[^>]+poster=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    final twitterImage = RegExp(
      r'''<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    result['thumbnailUrl'] = ogImage?.group(1) ??
        videoPoster?.group(1) ??
        twitterImage?.group(1) ??
        '';

    // ── Video source detection ────────────────────────────────────────────────
    final videoUrls = <String>{};

    // Direct <video src=...> or <source src=...>
    for (final m in RegExp(
      r'''(?:src|file)=["']([^"']+\.(?:mp4|webm|ogv|mkv|avi)[^"']*)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      final u = m.group(1) ?? '';
      if (u.isNotEmpty) videoUrls.add(u);
    }

    // HLS (.m3u8)
    for (final m in RegExp(
      r'''["']([^"']+\.m3u8[^"']*)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      final u = m.group(1) ?? '';
      if (u.startsWith('http') || u.startsWith('/')) videoUrls.add(u);
    }

    // DASH (.mpd)
    for (final m in RegExp(
      r'''["']([^"']+\.mpd[^"']*)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      final u = m.group(1) ?? '';
      if (u.startsWith('http') || u.startsWith('/')) videoUrls.add(u);
    }

    // JWPlayer setup({ file/sources })
    for (final m in RegExp(
      r'''file\s*:\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      final u = m.group(1) ?? '';
      if (u.startsWith('http') || u.contains('.m3u8') || u.contains('.mp4')) {
        videoUrls.add(u);
      }
    }

    // Video.js sources array
    for (final m in RegExp(
      r'''"src"\s*:\s*"([^"]+)"''',
      caseSensitive: false,
    ).allMatches(html)) {
      final u = m.group(1) ?? '';
      if (u.contains('.mp4') || u.contains('.m3u8') || u.contains('.mpd')) {
        videoUrls.add(u);
      }
    }

    result['videoUrls'] = videoUrls.take(10).toList();

    // ── Player type ───────────────────────────────────────────────────────────
    String playerType = '';
    if (html.contains('jwplayer') || html.contains('jwplayer.js')) {
      playerType = 'jwplayer';
    } else if (html.contains('data-setup') || html.contains('videojs')) {
      playerType = 'videojs';
    } else if (html.contains('Plyr') || html.contains('plyr.js')) {
      playerType = 'plyr';
    } else if (html.contains('hls.js') || html.contains('Hls.loadSource')) {
      playerType = 'hls.js';
    } else if (html.contains('dashjs') || html.contains('dash.js')) {
      playerType = 'dash.js';
    } else if (html.contains('<video')) {
      playerType = 'html5';
    } else if (html.contains('<iframe')) {
      playerType = 'iframe';
    }
    result['playerType'] = playerType;

    // ── Iframe embed URL ──────────────────────────────────────────────────────
    final knownPlayerHosts = [
      'streamtape', 'doodstream', 'mixdrop', 'filemoon',
      'mp4upload', 'vidcloud', 'streamwish', 'vidhide',
      'fembed', 'mystream', 'ok.ru', 'vk.com', 'dailymotion',
      'rumble', 'odysee', 'youtube', 'youtu.be',
    ];
    for (final m in RegExp(
      r'''<iframe[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    ).allMatches(html)) {
      final u = m.group(1) ?? '';
      final isPlayer = knownPlayerHosts.any((h) => u.contains(h));
      if (isPlayer || u.contains('/embed/') || u.contains('/player/')) {
        result['iframeUrl'] = u;
        if (playerType.isEmpty) result['playerType'] = 'iframe';
        break;
      }
    }

    // ── CSS selectors for listing pages ──────────────────────────────────────
    // Thumbnail selector heuristics
    const thumbCandidates = [
      'img.thumb', 'img.video-thumb', 'img.thumbnail',
      'div.thumb img', 'div.thumbnail img',
      'figure img', 'article img',
      'img[data-src]', 'img[loading="lazy"]',
    ];
    for (final sel in thumbCandidates) {
      final cls = sel.replaceFirst('img.', '').replaceFirst('div.', '');
      if (html.contains(cls)) {
        result['listThumbnailSelector'] = sel;
        break;
      }
    }
    if ((result['listThumbnailSelector'] as String).isEmpty) {
      result['listThumbnailSelector'] = 'img';
    }

    // Title/link selector heuristics
    const titleCandidates = [
      'a.title', 'h3.title a', 'h2.title a',
      'p.title a', 'span.title a',
      '.video-title a', '.item-title a',
      'div.info a', 'div.detail a',
    ];
    for (final sel in titleCandidates) {
      final cls = sel
          .replaceFirst('a.', '')
          .replaceFirst('h3.', '')
          .replaceFirst('h2.', '')
          .replaceFirst('p.', '')
          .replaceFirst('span.', '')
          .replaceAll(' a', '');
      if (html.contains(cls)) {
        result['listTitleSelector'] = sel;
        break;
      }
    }
    if ((result['listTitleSelector'] as String).isEmpty) {
      result['listTitleSelector'] = 'a';
    }

    // ── KVS data-config player extraction ────────────────────────────────────
    final kvsConfig = RegExp(
      r'''data-config=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    if (kvsConfig != null) {
      result['playerType'] = 'kvs';
      // config value is usually a JSON URL or inline JSON
      final cfg = kvsConfig.group(1) ?? '';
      if (cfg.startsWith('http') || cfg.startsWith('/')) {
        (result['videoUrls'] as List).add(cfg);
      }
    }

    // ── xVideos setVideoUrl / xvideo_url extraction ───────────────────────────
    final xvUrl = RegExp(
      r'''(?:setVideoUrl|xvideo_url)\s*[=(]\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    if (xvUrl != null) {
      result['playerType'] = 'xvideos';
      (result['videoUrls'] as List).insert(0, xvUrl.group(1)!);
    }

    // ── YouTube-specific extraction ───────────────────────────────────────────
    if (html.contains('ytInitialPlayerResponse') ||
        html.contains('ytInitialData')) {
      result['playerType'] = 'youtube';

      // HLS manifest URL
      final hlsMatch = RegExp(
        r'"hlsManifestUrl"\s*:\s*"([^"]+\.m3u8[^"]*)"',
      ).firstMatch(html);
      if (hlsMatch != null) {
        (result['videoUrls'] as List).insert(0, hlsMatch.group(1)!);
      }

      // Direct stream URLs inside streamingData
      for (final m in RegExp(
        r'"url"\s*:\s*"(https://[^"]+googlevideo\.com[^"]+)"',
      ).allMatches(html)) {
        (result['videoUrls'] as List).add(m.group(1)!);
      }

      // Thumbnail from og:image or ytimg CDN
      if ((result['thumbnailUrl'] as String).isEmpty) {
        final ytThumb = RegExp(
          r'https://i\.ytimg\.com/vi/([^/]+)/hqdefault\.jpg',
        ).firstMatch(html);
        if (ytThumb != null) result['thumbnailUrl'] = ytThumb.group(0)!;
      }

      result['videoSelector'] = 'ytInitialPlayerResponse.streamingData';
    }

    // ── Video element selector ────────────────────────────────────────────────
    else if (html.contains('<video')) {
      result['videoSelector'] = 'video source';
    } else if ((result['iframeUrl'] as String).isNotEmpty) {
      result['videoSelector'] = 'iframe';
    }

    return result;
  }

  // ─── Media selector builder ───────────────────────────────────────────────

  static Map<String, Map<String, String>> _buildMediaSelectors(
    String framework,
  ) {
    switch (framework) {
      case 'Madara':
        return {
          'imageSelectors': {
            'cover': 'div.summary_image img',
            'chapterImages': 'div.reading-content img',
            'lazyAttr': 'data-src',
          },
          'videoSelectors': {},
        };
      case 'MangaBox':
        return {
          'imageSelectors': {
            'cover': 'div.media-left img',
            'chapterImages': 'div.container-chapter-reader img',
            'lazyAttr': 'src',
          },
          'videoSelectors': {},
        };
      case 'MangaStream':
        return {
          'imageSelectors': {
            'cover': 'div.thumb img',
            'chapterImages': 'div#readerarea img',
            'lazyAttr': 'data-src',
          },
          'videoSelectors': {},
        };
      case 'MangaThemesia':
        return {
          'imageSelectors': {
            'cover': 'div.thumbook img',
            'chapterImages': 'div#readerarea img',
            'lazyAttr': 'data-src',
          },
          'videoSelectors': {},
        };
      case 'MangaSee / MangaLife':
        return {
          'imageSelectors': {
            'cover': 'img.lazyload',
            'chapterImages': 'img.lazyload',
            'lazyAttr': 'data-src',
            'jsArray': 'vm.Pages',
          },
          'videoSelectors': {},
        };
      case 'Webtoon (LINE/NAVER)':
        return {
          'imageSelectors': {
            'cover': 'span.thmb img',
            'chapterImages': 'div.viewer_lst img',
            'lazyAttr': 'data-url',
          },
          'videoSelectors': {},
        };
      case 'Tapas':
        return {
          'imageSelectors': {
            'cover': 'img.content-img',
            'chapterImages': 'img.content-img',
            'lazyAttr': 'src',
          },
          'videoSelectors': {},
        };
      case 'GuyaMoe / Cubari':
        return {
          'imageSelectors': {
            'cover': 'img.no-copy',
            'chapterImages': 'img.no-copy',
            'lazyAttr': 'src',
          },
          'videoSelectors': {},
        };
      case 'Komga':
        return {
          'imageSelectors': {
            'cover': '/api/v1/books/{id}/thumbnail',
            'chapterImages': '/api/v1/books/{id}/pages/{n}',
            'lazyAttr': 'src',
          },
          'videoSelectors': {},
        };
      case 'Kavita':
        return {
          'imageSelectors': {
            'cover': '/api/image/chapter-cover?chapterId={id}',
            'chapterImages': '/api/reader/image?chapterId={id}&page={n}',
            'lazyAttr': 'src',
          },
          'videoSelectors': {},
        };
      case 'Zorotheme (Anime)':
        return {
          'imageSelectors': {
            'cover': 'div.film-poster img',
            'chapterImages': '',
            'lazyAttr': 'data-src',
          },
          'videoSelectors': {
            'iframe': 'iframe#iframe-embed',
            'serverList': 'div.ps__-list',
            'sourceElem': 'video source',
          },
        };
      case 'Gogoanime':
        return {
          'imageSelectors': {
            'cover': 'div.anime_info_body img',
            'chapterImages': '',
            'lazyAttr': 'src',
          },
          'videoSelectors': {
            'iframe': 'div.anime_video_body iframe',
            'serverList': 'div#load_ep',
            'sourceElem': 'video source',
          },
        };
      case '9anime / Aniwave':
        return {
          'imageSelectors': {
            'cover': 'div.poster img',
            'chapterImages': '',
            'lazyAttr': 'data-src',
          },
          'videoSelectors': {
            'iframe': 'iframe#video-content',
            'serverList': 'ul.episodes',
            'sourceElem': 'video source',
          },
        };
      case 'AniList API':
        return {
          'imageSelectors': {
            'cover': 'coverImage { large }',
            'chapterImages': '',
            'lazyAttr': 'src',
          },
          'videoSelectors': {
            'iframe': 'iframe#iframe-embed',
            'serverList': '',
            'sourceElem': '',
          },
        };
      case 'KVS (Kernel Video Sharing)':
        return {
          'imageSelectors': {
            'cover': 'meta[property="og:image"]',
            'chapterImages': '',
            'lazyAttr': 'data-src',
            'listThumb': '.item .thumb img',
            'duration': '.item .duration',
          },
          'videoSelectors': {
            'iframe': '#player iframe, .player iframe',
            'serverList': '.sources',
            'sourceElem': 'video source',
            'configAttr': '#player[data-config]',
            'streamPath': '/get_file/',
          },
        };
      case 'xVideos Engine':
        return {
          'imageSelectors': {
            'cover': 'meta[property="og:image"]',
            'chapterImages': '',
            'lazyAttr': 'data-src',
            'listThumb': '.thumb-block .thumb img',
            'duration': '.thumb-block .duration',
          },
          'videoSelectors': {
            'iframe': 'iframe#video_html5_api, iframe.html5video',
            'serverList': '',
            'sourceElem': 'video#html5video',
            'jsVar': 'xvideo_url',
            'jsFn': 'setVideoUrl(',
          },
        };
      case 'xHamster Engine':
        return {
          'imageSelectors': {
            'cover': 'meta[property="og:image"]',
            'chapterImages': '',
            'lazyAttr': 'data-src',
            'listThumb': '.thumb-list .thumb img',
            'duration': '.thumb-list .duration',
          },
          'videoSelectors': {
            'iframe': '.xh-player iframe',
            'serverList': '.xhfw-player',
            'sourceElem': 'video source',
            'cdnPattern': 'xhcdn.com',
          },
        };
      case 'ClipBucket':
        return {
          'imageSelectors': {
            'cover': 'meta[property="og:image"]',
            'chapterImages': '',
            'lazyAttr': 'src',
            'listThumb': '.cb-thumb img',
          },
          'videoSelectors': {
            'iframe': '#cb-player iframe',
            'serverList': '',
            'sourceElem': 'video source',
          },
        };
      case 'PHPMotion':
        return {
          'imageSelectors': {
            'cover': 'meta[property="og:image"]',
            'chapterImages': '',
            'lazyAttr': 'src',
            'listThumb': '.pm-thumb img',
          },
          'videoSelectors': {
            'iframe': '#pm_player iframe',
            'serverList': '',
            'sourceElem': 'video source',
          },
        };
      case 'WP Ultimate Clips':
        return {
          'imageSelectors': {
            'cover': 'meta[property="og:image"]',
            'chapterImages': '',
            'lazyAttr': 'data-src',
            'listThumb': '.wp-clip-thumb img',
          },
          'videoSelectors': {
            'iframe': '.clips-player iframe',
            'serverList': '',
            'sourceElem': 'video source',
          },
        };
      case 'YouTube':
        return {
          'imageSelectors': {
            'cover': 'meta[property="og:image"]',
            'chapterImages': '',
            'lazyAttr': 'content',
            'cdnPattern': 'https://i.ytimg.com/vi/{videoId}/{quality}.jpg',
            'qualities': 'maxresdefault, hqdefault, mqdefault, sddefault',
          },
          'videoSelectors': {
            'iframe': 'iframe#player',
            'serverList': 'ytd-video-renderer',
            'sourceElem': 'ytInitialPlayerResponse',
            'streamPath': 'streamingData.formats[].url',
            'hlsPath': 'streamingData.hlsManifestUrl',
          },
        };
      case 'Generic Video Host':
        return {
          'imageSelectors': {
            'cover': 'meta[property="og:image"]',
            'chapterImages': '',
            'lazyAttr': 'content',
          },
          'videoSelectors': {
            'iframe': 'iframe',
            'serverList': '',
            'sourceElem': 'video source',
            'hlsPattern': '.m3u8',
            'dashPattern': '.mpd',
            'posterAttr': 'video[poster]',
          },
        };
      default:
        return {
          'imageSelectors': {
            'cover': 'img',
            'chapterImages': 'div.reading-content img',
            'lazyAttr': 'data-src',
          },
          'videoSelectors': {
            'iframe': 'iframe#iframe-embed',
            'serverList': '',
            'sourceElem': 'video source',
          },
        };
    }
  }

  // ─── Endpoint builders ───────────────────────────────────────────────────

  static List<Map<String, dynamic>> _buildEndpoints(
    _FrameworkSig? sig,
    String baseUrl,
    String html,
  ) {
    if (sig == null) return _buildCustomEndpoints(baseUrl, html);
    switch (sig.name) {
      case 'Madara':
        return [
          {
            'name': 'Popular Manga',
            'path': '/manga/?m_orderby=trending',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest Updates',
            'path': '/manga/?m_orderby=latest',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Manga Detail',
            'path': '/manga/{slug}/',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Chapter List (AJAX)',
            'path': '/wp-admin/admin-ajax.php',
            'status': 'found',
            'type': 'ajax',
          },
          {
            'name': 'Chapter Images',
            'path': '/manga/{slug}/{chapter}/',
            'status': 'found',
            'type': 'page',
          },
          {
            'name': 'Search',
            'path': '/?s={query}&post_type=wp-manga',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'MangaBox':
        return [
          {
            'name': 'Popular Manga',
            'path': '/manga-list/hot-manga',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest Updates',
            'path': '/manga-list/latest-manga',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Manga Detail',
            'path': '/manga/{slug}',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Chapter Images',
            'path': '/chapter/{id}',
            'status': 'found',
            'type': 'page',
          },
          {
            'name': 'Chapter List (API)',
            'path': '/api/manga/{slug}/chapters?limit=-1',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Search',
            'path': '/search/story/{query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'MangaStream':
        return [
          {
            'name': 'Popular Manga',
            'path': '/manga/?order=popular',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest Updates',
            'path': '/manga/?order=update',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Manga Detail',
            'path': '/manga/{slug}/',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Chapter Images',
            'path': '/{slug}/{chapter}/',
            'status': 'found',
            'type': 'page',
          },
          {
            'name': 'Search',
            'path': '/?s={query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'Zorotheme (Anime)':
        return [
          {
            'name': 'Popular Anime',
            'path': '/most-popular',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest Episodes',
            'path': '/recently-updated',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Anime Detail',
            'path': '/{slug}',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Episode List',
            'path': '/ajax/v2/episode/list/{id}',
            'status': 'found',
            'type': 'ajax',
          },
          {
            'name': 'Stream Sources',
            'path': '/ajax/v2/episode/servers?episodeId={id}',
            'status': 'found',
            'type': 'ajax',
          },
          {
            'name': 'Search',
            'path': '/search?keyword={query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'REST API':
        return [
          {
            'name': 'Manga List',
            'path': '/manga?limit=20&offset=0',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Manga Detail',
            'path': '/manga/{id}',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Chapter List',
            'path': '/manga/{id}/feed',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Chapter Images',
            'path': '/at-home/server/{chapterId}',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Search',
            'path': '/manga?title={query}',
            'status': 'found',
            'type': 'api',
          },
        ];
      case 'AniList API':
        return [
          {
            'name': 'GraphQL Endpoint',
            'path': '/graphql',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Media Search',
            'path': '/graphql (query: Media)',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Media List',
            'path': '/graphql (query: MediaList)',
            'status': 'found',
            'type': 'api',
          },
        ];
      case 'MangaThemesia':
        return [
          {
            'name': 'Popular Manga',
            'path': '/manga/?order=popular',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest Updates',
            'path': '/manga/?order=update',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Manga Detail',
            'path': '/manga/{slug}/',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Chapter Images',
            'path': '/{slug}/{chapter}/',
            'status': 'found',
            'type': 'page',
          },
          {
            'name': 'Search',
            'path': '/?s={query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'GuyaMoe / Cubari':
        return [
          {
            'name': 'Series List',
            'path': '/api/series/',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Series Detail',
            'path': '/api/series/{slug}/',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Chapter Pages',
            'path': '/read/{slug}/{chapter}/{page}/',
            'status': 'found',
            'type': 'page',
          },
          {
            'name': 'Search',
            'path': '/search?q={query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'MangaDex':
        return [
          {
            'name': 'Manga List',
            'path': '/manga?limit=20&offset={offset}',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Manga Detail',
            'path': '/manga/{id}?includes[]=cover_art&includes[]=author',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Chapter Feed',
            'path': '/manga/{id}/feed?limit=500&translatedLanguage[]={lang}',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Chapter Images',
            'path': '/at-home/server/{chapterId}',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Cover Art',
            'path': '/cover/{mangaId}/{coverId}.jpg',
            'status': 'found',
            'type': 'media',
          },
          {
            'name': 'Search',
            'path': '/manga?title={query}&limit=20',
            'status': 'found',
            'type': 'api',
          },
        ];
      case 'Webtoon (LINE/NAVER)':
        return [
          {
            'name': 'Popular',
            'path': '/en/genre/all?sortOrder=READ_COUNT',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest',
            'path': '/en/genre/all?sortOrder=UPDATE',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Series Detail',
            'path': '/en/{genre}/{title}/list?title_no={id}',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Episode Images',
            'path': '/en/{genre}/{title}/viewer?title_no={id}&episode_no={ep}',
            'status': 'found',
            'type': 'page',
          },
          {
            'name': 'Search',
            'path': '/search?keyword={query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'Tapas':
        return [
          {
            'name': 'Popular Series',
            'path': '/comics?browse=POPULAR',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest Series',
            'path': '/comics?browse=FRESH',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Series Detail',
            'path': '/series/{id}',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Episode Page',
            'path': '/episode/{id}',
            'status': 'found',
            'type': 'page',
          },
          {
            'name': 'Search',
            'path': '/search?q={query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'Gogoanime':
        return [
          {
            'name': 'Popular Anime',
            'path': '/popular.html?page={page}',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest Episodes',
            'path': '/?page={page}',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Anime Detail',
            'path': '/category/{slug}',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Episode Page',
            'path': '/{slug}-episode-{ep}',
            'status': 'found',
            'type': 'page',
          },
          {
            'name': 'Stream Source (AJAX)',
            'path': '/encrypt-ajax.php?id={id}&alias={alias}&default={ep}',
            'status': 'found',
            'type': 'ajax',
          },
          {
            'name': 'Search',
            'path': '/search.html?keyword={query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case '9anime / Aniwave':
        return [
          {
            'name': 'Popular Anime',
            'path': '/filter?sort=most_watched',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest Updates',
            'path': '/filter?sort=recently_updated',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Anime Detail',
            'path': '/watch/{slug}',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Episode List (AJAX)',
            'path': '/ajax/episode/list/{id}',
            'status': 'found',
            'type': 'ajax',
          },
          {
            'name': 'Stream Servers (AJAX)',
            'path': '/ajax/server/list/{episodeId}?vrf={vrf}',
            'status': 'found',
            'type': 'ajax',
          },
          {
            'name': 'Search',
            'path': '/filter?keyword={query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'MangaSee / MangaLife':
        return [
          {
            'name': 'Hot Today',
            'path': '/hot',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest Updates',
            'path': '/latest-releases',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Manga Detail',
            'path': '/manga/{slug}',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Chapter Reader',
            'path': '/read-online/{slug}-chapter-{ch}.html',
            'status': 'found',
            'type': 'page',
          },
          {
            'name': 'Search (JSON)',
            'path': '/search/?name={query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'Komga':
        return [
          {
            'name': 'Series List',
            'path': '/api/v1/series?page={page}&size=20',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Series Detail',
            'path': '/api/v1/series/{id}',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Books (Chapters)',
            'path': '/api/v1/series/{id}/books?page={page}',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Page List',
            'path': '/api/v1/books/{id}/pages',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Page Image',
            'path': '/api/v1/books/{id}/pages/{n}',
            'status': 'found',
            'type': 'media',
          },
          {
            'name': 'Search',
            'path': '/api/v1/series?search={query}',
            'status': 'found',
            'type': 'api',
          },
        ];
      case 'Kavita':
        return [
          {
            'name': 'Series List',
            'path': '/api/series/all?libraryId=0&pageNumber={page}',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Series Detail',
            'path': '/api/series/{id}',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Volumes',
            'path': '/api/series/volumes?seriesId={id}',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Chapter Pages',
            'path': '/api/reader/image?chapterId={id}&page={n}',
            'status': 'found',
            'type': 'media',
          },
          {
            'name': 'Search',
            'path': '/api/search?queryString={query}',
            'status': 'found',
            'type': 'api',
          },
        ];
      case 'KVS (Kernel Video Sharing)':
        return [
          {
            'name': 'Popular Videos',
            'path': '/?mode=videos&order=most_viewed',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest Videos',
            'path': '/?mode=videos&order=post_date',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Video Page',
            'path': '/videos/{id}/{slug}/',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Embed Player',
            'path': '/embed/{id}/',
            'status': 'found',
            'type': 'page',
          },
          {
            'name': 'Stream File',
            'path': '/get_file/{id}/{quality}.mp4',
            'status': 'found',
            'type': 'media',
          },
          {
            'name': 'Search',
            'path': '/?mode=search&search={query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'xVideos Engine':
        return [
          {
            'name': 'Popular Videos',
            'path': '/?p={page}',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest Videos',
            'path': '/new/{page}',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Video Page',
            'path': '/video{id}/{slug}',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Embed Player',
            'path': '/embedframe/{id}',
            'status': 'found',
            'type': 'page',
          },
          {
            'name': 'Search',
            'path': '/?k={query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'xHamster Engine':
        return [
          {
            'name': 'Popular Videos',
            'path': '/videos/popular',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest Videos',
            'path': '/videos/newest',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Video Page',
            'path': '/videos/{slug}-{id}',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Embed Player',
            'path': '/xembed.php?video={id}',
            'status': 'found',
            'type': 'page',
          },
          {
            'name': 'Search',
            'path': '/search/{query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'ClipBucket':
        return [
          {
            'name': 'Popular Videos',
            'path': '/videos?sort=most_viewed',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest Videos',
            'path': '/videos?sort=date_added',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Video Page',
            'path': '/watch/{id}',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Search',
            'path': '/search?query={query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'PHPMotion':
        return [
          {
            'name': 'Popular Videos',
            'path': '/videos/featured/',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest Videos',
            'path': '/videos/latest/',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Video Page',
            'path': '/video/{id}/',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Search',
            'path': '/search/?search_query={query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'WP Ultimate Clips':
        return [
          {
            'name': 'Popular Videos',
            'path': '/?orderby=views',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest Videos',
            'path': '/?orderby=date',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Video Page',
            'path': '/clip/{slug}/',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Search',
            'path': '/?s={query}',
            'status': 'found',
            'type': 'search',
          },
        ];
      case 'YouTube':
        return [
          {
            'name': 'Browse (Popular/Trending)',
            'path': '/youtubei/v1/browse',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Search',
            'path': '/youtubei/v1/search?query={query}',
            'status': 'found',
            'type': 'api',
          },
          {
            'name': 'Video Page',
            'path': '/watch?v={videoId}',
            'status': 'found',
            'type': 'detail',
          },
          {
            'name': 'Player Data (ytInitialPlayerResponse)',
            'path': '/watch?v={videoId} → ytInitialPlayerResponse JSON',
            'status': 'found',
            'type': 'embedded-json',
          },
          {
            'name': 'Streaming Formats',
            'path': 'ytInitialPlayerResponse.streamingData.formats[]',
            'status': 'found',
            'type': 'embedded-json',
          },
          {
            'name': 'HLS Manifest',
            'path': 'ytInitialPlayerResponse.streamingData.hlsManifestUrl',
            'status': 'found',
            'type': 'media',
          },
          {
            'name': 'Thumbnail CDN',
            'path': 'https://i.ytimg.com/vi/{videoId}/hqdefault.jpg',
            'status': 'found',
            'type': 'media',
          },
          {
            'name': 'Channel Videos',
            'path': '/channel/{channelId}/videos',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Playlist',
            'path': '/playlist?list={playlistId}',
            'status': 'found',
            'type': 'list',
          },
        ];
      case 'Generic Video Host':
        return [
          {
            'name': 'Home / Popular',
            'path': '/',
            'status': 'found',
            'type': 'list',
          },
          {
            'name': 'Latest / New',
            'path': '/new',
            'status': 'unknown',
            'type': 'list',
          },
          {
            'name': 'Video Page',
            'path': '/video/{id}',
            'status': 'unknown',
            'type': 'detail',
          },
          {
            'name': 'Video Stream (HLS)',
            'path': '/hls/{id}/index.m3u8',
            'status': 'unknown',
            'type': 'media',
          },
          {
            'name': 'Video Stream (MP4)',
            'path': '/get_file/{id}',
            'status': 'unknown',
            'type': 'media',
          },
          {
            'name': 'Search',
            'path': '/search?q={query}',
            'status': 'unknown',
            'type': 'search',
          },
        ];
      default:
        return _buildCustomEndpoints(baseUrl, html);
    }
  }

  static List<Map<String, dynamic>> _buildCustomEndpoints(
    String baseUrl,
    String html,
  ) {
    final endpoints = <Map<String, dynamic>>[];
    final pathPatterns = [
      RegExp(r'''href=["']([^"']*manga[^"']*)["\']''', caseSensitive: false),
      RegExp(r'''href=["']([^"']*anime[^"']*)["\']''', caseSensitive: false),
      RegExp(r'''href=["']([^"']*chapter[^"']*)["\']''', caseSensitive: false),
      RegExp(r'''href=["']([^"']*episode[^"']*)["\']''', caseSensitive: false),
    ];
    final found = <String>{};
    for (final pattern in pathPatterns) {
      final matches = pattern.allMatches(html).take(2);
      for (final m in matches) {
        final path = m.group(1) ?? '';
        if (path.isNotEmpty && !found.contains(path) && path.length < 80) {
          found.add(path);
        }
      }
    }
    if (found.isEmpty) {
      endpoints.addAll([
        {
          'name': 'Home / Popular',
          'path': '/',
          'status': 'found',
          'type': 'list',
        },
        {
          'name': 'Latest',
          'path': '/latest',
          'status': 'unknown',
          'type': 'list',
        },
        {
          'name': 'Detail Page',
          'path': '/{slug}',
          'status': 'unknown',
          'type': 'detail',
        },
        {
          'name': 'Search',
          'path': '/search?q={query}',
          'status': 'unknown',
          'type': 'search',
        },
      ]);
    } else {
      for (final path in found.take(6)) {
        endpoints.add({
          'name': _labelFromPath(path),
          'path': path,
          'status': 'found',
          'type': 'page',
        });
      }
    }
    return endpoints;
  }

  static String _labelFromPath(String path) {
    if (path.contains('manga')) return 'Manga Page';
    if (path.contains('anime')) return 'Anime Page';
    if (path.contains('chapter')) return 'Chapter Page';
    if (path.contains('episode')) return 'Episode Page';
    if (path.contains('search')) return 'Search';
    return 'Page';
  }
}

// ─── Data classes ─────────────────────────────────────────────────────────────

class _FrameworkSig {
  final String name;
  final List<String> patterns;
  final int confidence;
  final String contentType;
  final String version;

  const _FrameworkSig({
    required this.name,
    required this.patterns,
    required this.confidence,
    required this.contentType,
    required this.version,
  });
}
