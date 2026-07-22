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
    // NOTE: there is deliberately no "AniList API" signature. AniList is a
    // tracking/metadata service (already integrated as a tracker) with no
    // readable chapter content, and the generator has no path to build a source
    // from it — so detecting it produced nothing usable. Its loose 'anilist'
    // pattern also misclassified any manga site that merely LINKED to AniList.
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

    // ── lib-multisrc expansion (build 25) ─────────────────────────────────
    // Detection signatures for the full keiyoushi/yuzono/NovelSourcery
    // multi-source theme set. Markers are observable public-site facts drawn
    // from each framework's base class as reference (not copied code). Patterns
    // are the most distinctive 3-6 per framework; confidence reflects marker
    // uniqueness (API/header endpoints highest, generic WP themes lowest).

    // Manga themes (keiyoushi lib-multisrc)
    _FrameworkSig(name: 'FoOlSlide', patterns: ['div.group', '/directory/', 'div.meta_r', 'var pages = ['], confidence: 88, contentType: 'Manga', version: 'FoolSlide'),
    _FrameworkSig(name: 'GigaViewer', patterns: ['data-giga_series', 'pagination_readable_products', 'episode-json', 'series-header-title'], confidence: 95, contentType: 'Manga', version: 'GigaViewer'),
    _FrameworkSig(name: 'LibGroup API', patterns: ['api.cdnlibs.org', '/api/constants?fields', '/api/latest-updates', 'site_id[]='], confidence: 96, contentType: 'Manga', version: 'API'),
    _FrameworkSig(name: 'GroupLe', patterns: ['rm_h.readerInit', 'cr-hero-names__main', 'user_hash', 'sortType=updated'], confidence: 92, contentType: 'Manga', version: 'GroupLe'),
    _FrameworkSig(name: 'MCCMS', patterns: ['/api/data/comic?', '/api/data/chapter?mid=', 'order=addtime'], confidence: 93, contentType: 'Manga', version: 'MCCMS'),
    _FrameworkSig(name: 'SinMH', patterns: ['chapterImages = [', 'chapterPath =', 'book-title', 'contList'], confidence: 90, contentType: 'Manga', version: 'SinMH'),
    _FrameworkSig(name: 'MangaHub API', patterns: ['mghcdn.com', 'x-mhub-access', 'mhub_access', 'imgx.mghcdn.com'], confidence: 96, contentType: 'Manga', version: 'GraphQL'),
    _FrameworkSig(name: 'Iken API', patterns: ['/api/query', '/api/post?postSlug=', '/api/chapters?postId=', '/series/'], confidence: 94, contentType: 'Manga', version: 'API'),
    _FrameworkSig(name: 'Liliana', patterns: ['/ajax/image/list/chap/', 'const CHAPTER_ID', 'div.separator', 'ranking/week'], confidence: 91, contentType: 'Manga', version: 'Liliana'),
    _FrameworkSig(name: 'UzayManga', patterns: ['__data.json', 'x-sveltekit-invalidated', 'sort=popular'], confidence: 93, contentType: 'Manga', version: 'SvelteKit'),
    _FrameworkSig(name: 'FuzzyDoodle', patterns: ['card-real', 'chapter-container', 'chapters-list', 'name=type'], confidence: 90, contentType: 'Manga', version: 'FuzzyDoodle'),
    _FrameworkSig(name: 'MangaReader', patterns: ['ani_detail', 'manga_list-sbs', 'en-chapters', 'mode=vertical'], confidence: 91, contentType: 'Manga', version: 'MangaReader'),
    _FrameworkSig(name: 'MangaWorld', patterns: ['noidungm', 'comics-grid', 'chapters-wrapper', 'page-image'], confidence: 91, contentType: 'Manga', version: 'MangaWorld'),
    _FrameworkSig(name: 'MangaCatalog', patterns: ['bg-bg-secondary', 'col-span-4'], confidence: 84, contentType: 'Manga', version: 'MangaCatalog'),
    _FrameworkSig(name: 'PizzaReader', patterns: ['/api/comics', '/api/search/'], confidence: 90, contentType: 'Manga', version: 'PizzaReader'),
    _FrameworkSig(name: 'MangAdventure', patterns: ['/api/v2/series', '/api/v2/chapters/', 'sort=-latest_upload'], confidence: 93, contentType: 'Manga', version: 'API v2'),
    _FrameworkSig(name: 'MonochromeCMS', patterns: ['/api/media/', '/api/manga?limit=', '/chapters/'], confidence: 91, contentType: 'Manga', version: 'MonochromeCMS'),
    _FrameworkSig(name: 'ManhwaZ', patterns: ['slide-top', 'img-item', 'info-item', 'item-summary'], confidence: 82, contentType: 'Manhwa', version: 'ManhwaZ'),
    _FrameworkSig(name: 'ZManga', patterns: ['flexbox2-item', 'flexch-infoz', 'series-chapterlist', 'reader-area'], confidence: 90, contentType: 'Manga', version: 'ZManga'),
    _FrameworkSig(name: 'Senkuro', patterns: ['api.senkuro', 'fetchTachiyomiManga', 'searchTachiyomiManga'], confidence: 94, contentType: 'Manga', version: 'GraphQL'),
    _FrameworkSig(name: 'Multi-Chan', patterns: ['content_row', 'table_cha', 'fullimg', 'do=search&subaction=search'], confidence: 89, contentType: 'Manga', version: 'Chan'),
    _FrameworkSig(name: 'Comici Viewer', patterns: ['series-list-item-link', '#scramble=', 'series-list-item-img'], confidence: 92, contentType: 'Manga', version: 'Comici'),
    _FrameworkSig(name: 'EZManhwa API', patterns: ['perPage=20&sort=popular', 'pref_show_locked_chapters', '/series/search?q='], confidence: 92, contentType: 'Manhwa', version: 'API'),
    _FrameworkSig(name: 'GoDa', patterns: ['chapcontent', '/manga/get?mid=', '/chapter/getcontent?m=', 'mangachapters'], confidence: 91, contentType: 'Manga', version: 'GoDa'),
    _FrameworkSig(name: 'GreenShit API', patterns: ['/obras/ranking', '/obras/atualizacoes', '/capitulos/'], confidence: 92, contentType: 'Manga', version: 'API'),
    _FrameworkSig(name: 'Hiper (tRPC)', patterns: ['/api/trpc/', 'series.bySlugWithGenres', 'reader.chapterPages'], confidence: 94, contentType: 'Manga', version: 'tRPC'),
    _FrameworkSig(name: 'InitManga', patterns: ['/wp-json/initlise/v1/search', 'InitMangaEncryptedChapter', 'manga-item-grid'], confidence: 93, contentType: 'Manga', version: 'InitManga'),
    _FrameworkSig(name: 'MangaTaro', patterns: ['/auth/manga-chapters', '/wp-json/manga/v1/load', '/auth/chapter-content'], confidence: 93, contentType: 'Manga', version: 'MangaTaro'),
    _FrameworkSig(name: 'MangaWork', patterns: ['imgch', '/manga_auto_capitulos/', 'chapter_list_container'], confidence: 90, contentType: 'Manga', version: 'MangaWork'),
    _FrameworkSig(name: 'MangoTheme API', patterns: ['X-MangoTheme-Stored-Slug', '/api/obras/top10/views', '/api/capitulos/recentes'], confidence: 94, contentType: 'Manga', version: 'API'),
    _FrameworkSig(name: 'Masonry', patterns: ['list-gallery', 'mpage/', 'pagination-a'], confidence: 87, contentType: 'Comic', version: 'Masonry'),
    _FrameworkSig(name: 'MoonlightTL', patterns: ['/api/showProject/', '/api/topSerie', '/api/lastUpdates'], confidence: 92, contentType: 'Manga', version: 'MoonlightTL'),
    _FrameworkSig(name: 'NatsuId', patterns: ['action=advanced_search', 'search_nonce', 'action=chapter_list'], confidence: 91, contentType: 'Manhwa', version: 'NatsuId'),
    _FrameworkSig(name: 'OceanWP', patterns: ['blog-entry', 'blog-entry-title', 'tagcloud'], confidence: 70, contentType: 'Manga', version: 'WordPress'),
    _FrameworkSig(name: 'Pam (Inertia)', patterns: ['X-Inertia', 'data-page', '/api/v1/search/series'], confidence: 92, contentType: 'Manga', version: 'Inertia'),
    _FrameworkSig(name: 'ScanReader', patterns: ['secure-chapters-container', '/chapitre/', 'manga-card'], confidence: 90, contentType: 'Manga', version: 'ScanReader'),
    _FrameworkSig(name: 'SpicyTheme API', patterns: ['/filtrar?orderBy=ID_POPULAR', '/home/buscar?query='], confidence: 92, contentType: 'Manga', version: 'API'),
    _FrameworkSig(name: 'StalkerCMS', patterns: ['chapter-image-canvas', 'load-more-releases', 'comic-card-link'], confidence: 91, contentType: 'Manga', version: 'StalkerCMS'),
    _FrameworkSig(name: 'VerComics', patterns: ['popimg', 'wp-pagenavi', 'div#lector', 'tax_box'], confidence: 88, contentType: 'Comic', version: 'VerComics'),
    _FrameworkSig(name: 'BakkinReaderX', patterns: ['main.php', '#m=', '#v=', '#c='], confidence: 88, contentType: 'Manga', version: 'Bakkin'),

    // Anime themes (yuzono lib-multisrc)
    _FrameworkSig(name: 'DooPlay', patterns: ['w_item_a', 'ul.episodios', 'numerando', 'doo_player_ajax'], confidence: 91, contentType: 'Anime', version: 'DooPlay'),
    _FrameworkSig(name: 'AnimeStream', patterns: ['eplister', 'listupd', 'epl-num', 'data-em'], confidence: 91, contentType: 'Anime', version: 'AnimeStream'),
    _FrameworkSig(name: 'DataLifeEngine', patterns: ['dle-content', 'do=search', 'div.mov', 'dle_root'], confidence: 88, contentType: 'Anime', version: 'DLE'),
    _FrameworkSig(name: 'DopeFlix', patterns: ['flw-item', 'detail_page-infor', '/ajax/episode/sources/', 'eps-item'], confidence: 92, contentType: 'Anime', version: 'FlixHQ'),
    _FrameworkSig(name: 'WcoTheme', patterns: ['sidebar_cat', 'wcostream', 'watchanimesub', 'recent-release'], confidence: 91, contentType: 'Anime', version: 'WcoTheme'),
    _FrameworkSig(name: 'AnimeKai', patterns: ['ani_id=', 'aitem', '/ajax/links/list?token=', 'enc-dec.app'], confidence: 92, contentType: 'Anime', version: 'AnimeKai'),
    _FrameworkSig(name: 'Anikoto', patterns: ['flexserieslist', 'vrf=', '/ajax/episode/list/', 'ani.items'], confidence: 91, contentType: 'Anime', version: 'Anikoto'),
    _FrameworkSig(name: 'YFlix', patterns: ['enc-movies-flix', 'film-section', '/ajax/links/view?id='], confidence: 92, contentType: 'Anime', version: 'YFlix'),
    _FrameworkSig(name: 'PelisPlus', patterns: ['pelisplus', '/drive/v1/shares/'], confidence: 78, contentType: 'Anime', version: 'PelisPlus'),

    // Novel themes (NovelSourcery + lnreader-plugins, reference only)
    _FrameworkSig(name: 'LightNovelWP', patterns: ['epcontent', 'ts-post-image', 'sertogenre', 'epl-price'], confidence: 91, contentType: 'Novel', version: 'LightNovelWP'),
    _FrameworkSig(name: 'ReadWN', patterns: ['novel-item', '-newstime-', '-lastdotime-', 'chapter-content'], confidence: 91, contentType: 'Novel', version: 'ReadWN'),
    _FrameworkSig(name: 'ReadNovelFull', patterns: ['chr-content', 'list-novel', 'novel-title', 'og:novel:status'], confidence: 91, contentType: 'Novel', version: 'NovelFull'),
    _FrameworkSig(name: 'LightNovelWorld', patterns: ['chapter-container', 'novel-item', 'lnsearchlive', 'PagedList-skipToNext'], confidence: 92, contentType: 'Novel', version: 'LNW'),
    _FrameworkSig(name: 'Fictioneer', patterns: ['story__identity-title', 'chapter-group__list-item', 'story__thumbnail'], confidence: 92, contentType: 'Novel', version: 'Fictioneer'),
    _FrameworkSig(name: 'HotNovelPub API', patterns: ['/server/getContent?slug=', 'books/hot/', 'key_search'], confidence: 92, contentType: 'Novel', version: 'API'),
    _FrameworkSig(name: 'MTLNovel', patterns: ['div.par', 'ch-link', 'amp-img', 'chapter-list'], confidence: 89, contentType: 'Novel', version: 'MTLNovel'),
    _FrameworkSig(name: 'Ranobes', patterns: ['arrticle', 'short-cont', 'category grey ellipses'], confidence: 90, contentType: 'Novel', version: 'Ranobes'),
    _FrameworkSig(name: 'Rulate API', patterns: ['/api3/', 'bookChapters?book_id=', 'ready_new'], confidence: 93, contentType: 'Novel', version: 'API'),
    _FrameworkSig(name: 'NovelCool API', patterns: ['api.novelcool.com', '/chapter/info/', 'lc_type=novel'], confidence: 93, contentType: 'Novel', version: 'API'),
    _FrameworkSig(name: 'iFreedom', patterns: ['one-book-home', 'item-book-slide', 'chapter-setting'], confidence: 89, contentType: 'Novel', version: 'iFreedom'),
  ];

  // Near-unique, high-signal tokens (brands, domains, JS globals). A single
  // one of these is enough to accept a framework even at match-score 1.
  static const Set<String> _strongTokens = {
    'wp-manga', 'madara', 'mangathemesia', 'themesia', 'mangadex.org',
    // 'anilist' intentionally absent: it's a link/ad reference on countless
    // manga sites, not proof the site is anything. The AniList API signature
    // was removed entirely (AniList has no readable content to generate from).
    'ytinitialplayerresponse', 'ytinitialdata', 'vm.pages',
    // ── lib-multisrc expansion: near-unique single-match markers ──
    // Manga
    'api.cdnlibs.org', 'rm_h.readerinit', '/api/data/comic?', 'mghcdn.com',
    'x-mhub-access', 'data-giga_series', 'pagination_readable_products',
    '/ajax/image/list/chap/', '__data.json', 'x-sveltekit-invalidated',
    '/api/trpc/', 'x-mangotheme-stored-slug', '/wp-json/initlise/v1/search',
    'initmangaencryptedchapter', '/auth/manga-chapters', '/manga_auto_capitulos/',
    'api.senkuro', '/api/v2/series', '/api/showproject/', 'flexch-infoz',
    'flexbox2-item', 'secure-chapters-container', 'chapter-image-canvas',
    'load-more-releases', 'series-list-item-link', '/manga/get?mid=',
    '/obras/ranking', '/filtrar?orderby=id_popular', 'card-real',
    // Anime
    'w_item_a', 'eplister', 'doo_player_ajax', 'enc-movies-flix',
    'flexserieslist', 'ani_id=', 'wcostream', 'watchanimesub',
    // Novel
    'story__identity-title', 'chapter-group__list-item', 'og:novel:status',
    'lnsearchlive', 'api.novelcool.com', '/api3/', '/server/getcontent?slug=',
    '-newstime-', '-lastdotime-', 'one-book-home', 'chr-content',
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

    // Fresh growable copy so the catalog-endpoint merge below can't hit a
    // fixed-length/const list from _buildEndpoints.
    final endpoints = [
      ..._buildEndpoints(
        framework == 'Custom' ? null : _sigByName(framework),
        normalizedUrl,
        lowerHtml,
      )
    ];
    // Merge the framework's catalog endpoints (API/GraphQL routes) so an
    // API-based source generates against the right paths.
    final catalogEndpoints = _frameworkEndpoints[framework];
    if (catalogEndpoints != null) {
      endpoints.addAll(catalogEndpoints.map((e) => {
            'name': e['name'] ?? '',
            'path': e['path'] ?? '',
            'status': 'catalog',
            'type': 'api',
          }));
    }

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
    } else {
      // Known framework: emit its catalog selectors so the Create Source
      // screen auto-fills each slot and the generator uses real selectors
      // rather than generic defaults.
      final known = _frameworkSelectors[framework];
      if (known != null) extractedSelectors = Map<String, String>.from(known);
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

  // ─── lib-multisrc listing selectors (build 25) ────────────────────────────
  // Per-framework listing/detail/chapter/page CSS selectors, from each theme's
  // base class as reference. Emitted by detect() for KNOWN frameworks so the
  // generator fills real selectors instead of generic defaults. Also the source
  // of truth for the Scraping Studio's per-role selector picker. Roles:
  // item, title, cover, chapters, page_images, detailTitle, nextPage, episodes.
  // API/GraphQL frameworks carry no CSS selectors (they use _frameworkEndpoints).
  static const Map<String, Map<String, String>> _frameworkSelectors = {
    // Manga — HTML themes
    'FoOlSlide': {'item': 'div.group', 'title': 'a[title]', 'cover': 'img', 'chapters': 'div.group div.element, div.list div.element', 'detailTitle': 'h1.title'},
    'GigaViewer': {'item': 'ul.series-list li a', 'title': 'h2.series-list-title', 'cover': 'div.series-list-thumb img', 'detailTitle': 'h1.series-header-title'},
    'GroupLe': {'item': 'div.tile', 'title': 'h3 > a', 'cover': 'img.lazy', 'chapters': 'a.chapter-link', 'detailTitle': '.cr-hero-names__main'},
    'SinMH': {'item': '#contList > li, li.list-comic', 'title': 'p > a, h3 > a', 'cover': 'img', 'chapters': '.chapter-body li > a', 'detailTitle': '.book-title > h1'},
    'Liliana': {'item': 'div#main div.grid > div', 'title': '.text-center a', 'cover': 'img', 'chapters': 'ul > li.chapter', 'page_images': 'div.separator'},
    'FuzzyDoodle': {'item': 'div#card-real', 'title': 'h2.text-sm', 'cover': 'img', 'chapters': 'div#chapters-list > a[href]', 'page_images': 'div#chapter-container > img'},
    'MangaReader': {'item': '.manga_list-sbs .manga-poster', 'title': '.manga-name', 'chapters': '#en-chapters > li.chapter-item', 'detailTitle': '.manga-name', 'page_images': '.container-reader-chapter > div > img'},
    'MangaWorld': {'item': 'div.comics-grid .entry', 'title': 'a', 'cover': 'a.thumb img', 'chapters': '.chapters-wrapper .chapter', 'page_images': 'div#page img.page-image', 'detailTitle': 'h1'},
    'MangaCatalog': {'item': 'div.bg-bg-secondary > div.px-6 > div.flex-col', 'title': 'div.container > h1', 'cover': 'div.flex > img', 'page_images': 'img[data-src]'},
    'ManhwaZ': {'item': '#slide-top > .item, .page-item-detail', 'title': '.info-item a, .item-summary a', 'cover': '.img-item img', 'chapters': 'li.wp-manga-chapter', 'page_images': 'div.page-break img', 'detailTitle': 'div.post-title h1'},
    'ZManga': {'item': 'div.flexbox2-item', 'title': 'div.flexbox2-title > span', 'cover': 'img', 'chapters': 'ul.series-chapterlist div.flexch-infoz a', 'page_images': 'div.reader-area img'},
    'Multi-Chan': {'item': 'div.content_row', 'cover': 'img#cover', 'chapters': 'table.table_cha tr:gt(1)', 'detailTitle': 'h1'},
    'Comici Viewer': {'item': 'div.series-list-item', 'title': 'div.series-list-item-h span', 'cover': 'img.series-list-item-img'},
    'GoDa': {'item': '.container > .cardlist .pb-2 a', 'title': 'h3', 'cover': 'img', 'chapters': '.chapteritem', 'page_images': '#chapcontent > div > img'},
    'InitManga': {'item': 'div.manga-item-grid > div.uk-panel', 'title': 'h3 a', 'cover': 'img', 'chapters': 'div.chapter-item', 'page_images': 'div#chapter-content img[src]'},
    'MangaWork': {'item': "div.w-full.h-full", 'title': 'h1', 'cover': 'img', 'chapters': '#chapter_list li', 'page_images': 'div.reader-area img#imagech'},
    'Masonry': {'item': '.list-gallery:not(.static) figure', 'title': 'a', 'cover': 'img', 'page_images': '.list-gallery a'},
    'NatsuId': {'item': 'div > a[href*=/manga/]', 'chapters': 'div a:has(time)', 'page_images': 'main .relative section > img'},
    'OceanWP': {'item': 'article.blog-entry', 'title': 'h2.blog-entry-title a', 'cover': 'div.thumbnail img', 'page_images': 'div.entry-content img', 'detailTitle': '.entry-title'},
    'ScanReader': {'item': 'div.manga-card', 'title': 'h1.manga-title', 'cover': "meta[property='og:image']", 'chapters': '#secure-chapters-container', 'detailTitle': 'h1.manga-title'},
    'StalkerCMS': {'item': '.comics-grid a.comic-card-link', 'title': 'h1', 'cover': '.sidebar-cover-image img', 'chapters': '.chapter-item-list a.chapter-link', 'page_images': '.chapter-image-canvas'},
    'VerComics': {'item': 'header:has(h1) ~ * .entry', 'cover': 'img:not(noscript img)', 'page_images': 'div.wp-content div#lector > img'},
    'MangaTaro': {'item': '.manga-card', 'title': 'h1', 'cover': 'img', 'detailTitle': 'h1'},
    'MoonlightTL': {'page_images': 'main.contenedor.read img, main > img'},
    // Anime — HTML/AJAX themes
    'DooPlay': {'item': 'article.w_item_a > a', 'title': 'img.alt', 'cover': 'div.poster img', 'episodes': 'ul.episodios > li'},
    'AnimeStream': {'item': 'div.listupd article a.tip', 'title': 'h1.entry-title', 'cover': 'div.thumb > img, div.limage > img', 'episodes': 'div.eplister > ul > li > a'},
    'DataLifeEngine': {'item': 'div#dle-content > div.mov', 'title': 'a', 'cover': 'img'},
    'DopeFlix': {'item': 'div.flw-item', 'cover': 'div.film-poster img', 'episodes': '.eps-item'},
    'WcoTheme': {'item': 'div#sidebar_right2 ul.items > li', 'title': 'div.video-title a', 'cover': 'div#sidebar_cat img', 'episodes': 'div#episodeList a.dark-episode-item'},
    'AnimeKai': {'item': '.aitem-col a.aitem', 'episodes': 'div.eplist a'},
    'Anikoto': {'item': 'div.ani.items > div.item', 'title': 'a.name', 'cover': 'div.poster img', 'episodes': 'div.episodes ul > li > a'},
    'YFlix': {'item': 'div.film-section div.item', 'title': 'a.title', 'cover': 'img[data-src]', 'episodes': 'ul.episodes[data-season]'},
    // Novel — HTML themes (page_images = chapter TEXT content selector for novels)
    'LightNovelWP': {'item': 'article', 'title': '.entry-title', 'cover': 'img.ts-post-image', 'chapters': '.eplister li', 'page_images': '.epcontent.entry-content', 'detailTitle': '.entry-title'},
    'ReadWN': {'item': 'li.novel-item', 'title': 'h4', 'cover': '.novel-cover img', 'chapters': '.chapter-list li', 'page_images': '.chapter-content', 'detailTitle': 'h1.novel-title'},
    'ReadNovelFull': {'item': 'div.list-novel div.row', 'title': 'h3.novel-title a', 'cover': 'div.pic img', 'chapters': '#list-chapter li a', 'page_images': 'div#chr-content', 'detailTitle': 'h3.title'},
    'LightNovelWorld': {'item': '.novel-item', 'title': '.novel-title > a', 'cover': 'img[data-src]', 'chapters': '.chapter-list li', 'page_images': '#chapter-container', 'detailTitle': 'h1.novel-title'},
    'Fictioneer': {'item': '#list-of-stories > li > div > div', 'title': 'h3 > a', 'cover': 'a.cell-img', 'chapters': 'li.chapter-group__list-item', 'page_images': 'section#chapter-content > div', 'detailTitle': 'h1.story__identity-title'},
    'MTLNovel': {'item': 'div.box.wide', 'title': 'a.list-title', 'cover': 'amp-img', 'chapters': 'div.ch-list a.ch-link', 'page_images': 'div.par', 'detailTitle': 'h1.entry-title'},
    'Ranobes': {'item': '.short-cont', 'title': 'h2.title > a', 'page_images': 'div.text#arrticle'},
    'iFreedom': {'item': '.one-book-home, .item-book-slide', 'cover': 'img', 'page_images': 'div.chapter-content'},
  };

  // API/GraphQL/tRPC frameworks: base-relative endpoint paths, emitted so the
  // generator's API body targets the right routes. {query}/{page}/{slug}/{id}
  // are filled at runtime by the generated source.
  static const Map<String, List<Map<String, String>>> _frameworkEndpoints = {
    'LibGroup API': [
      {'name': 'popular', 'path': '/api/manga?site_id[]=&page={page}'},
      {'name': 'latest', 'path': '/api/latest-updates?page={page}'},
      {'name': 'search', 'path': '/api/manga?page={page}&q={query}'},
    ],
    'Iken API': [
      {'name': 'popular', 'path': '/api/query'},
      {'name': 'search', 'path': '/api/query'},
      {'name': 'chapters', 'path': '/api/chapters?postId={id}'},
    ],
    'MangAdventure': [
      {'name': 'latest', 'path': '/api/v2/series?page={page}&sort=-latest_upload'},
      {'name': 'popular', 'path': '/api/v2/series?page={page}&sort=-views'},
      {'name': 'search', 'path': '/api/v2/series?title={query}'},
    ],
    'MonochromeCMS': [
      {'name': 'search', 'path': '/api/manga?limit=10&offset=0&title={query}'},
    ],
    'PizzaReader': [
      {'name': 'popular', 'path': '/api/comics'},
      {'name': 'search', 'path': '/api/search/{query}'},
    ],
    'MCCMS': [
      {'name': 'popular', 'path': '/api/data/comic?page={page}&order=hits'},
      {'name': 'latest', 'path': '/api/data/comic?page={page}&order=addtime'},
      {'name': 'search', 'path': '/api/data/comic?key={query}'},
    ],
    'GreenShit API': [
      {'name': 'popular', 'path': '/obras/ranking'},
      {'name': 'latest', 'path': '/obras/atualizacoes'},
      {'name': 'search', 'path': '/obras/buscar'},
    ],
    'MangoTheme API': [
      {'name': 'popular', 'path': '/api/obras/top10/views?periodo=total'},
      {'name': 'latest', 'path': '/api/capitulos/recentes?pagina={page}'},
      {'name': 'search', 'path': '/api/obras?pagina={page}&busca={query}'},
    ],
    'SpicyTheme API': [
      {'name': 'popular', 'path': '/filtrar?page={page}&orderBy=ID_POPULAR'},
      {'name': 'latest', 'path': '/filtrar?page={page}&orderBy=ID_LATEST'},
      {'name': 'search', 'path': '/home/buscar?query={query}'},
    ],
    'EZManhwa API': [
      {'name': 'popular', 'path': '/series?page={page}&perPage=20&sort=popular'},
      {'name': 'latest', 'path': '/series?page={page}&perPage=20&sort=latest'},
      {'name': 'search', 'path': '/series/search?q={query}'},
    ],
    'HotNovelPub API': [
      {'name': 'popular', 'path': '/books/hot/?page={page}&limit=20'},
      {'name': 'latest', 'path': '/books/new/'},
      {'name': 'search', 'path': '/search'},
    ],
    'Rulate API': [
      {'name': 'search', 'path': '/api3/searchBooks?limit=40&page={page}&t={query}'},
      {'name': 'chapters', 'path': '/api3/bookChapters?book_id={id}'},
    ],
    'NovelCool API': [
      {'name': 'popular', 'path': '/elite/hot'},
      {'name': 'latest', 'path': '/elite/latest'},
      {'name': 'search', 'path': '/book/search/'},
    ],
    'UzayManga': [
      {'name': 'popular', 'path': '/manga/__data.json?sort=popular&page={page}'},
      {'name': 'latest', 'path': '/manga/__data.json?sort=new&page={page}'},
      {'name': 'search', 'path': '/manga/__data.json?search={query}&page={page}'},
    ],
  };

  /// All known selectors cataloged for a role (item/title/cover/chapters/
  /// page_images/detailTitle/nextPage/episodes), aggregated across every
  /// framework and de-duplicated. Powers the Scraping Studio's per-field
  /// selector picker, so a user who doesn't know CSS can choose a known-good
  /// selector instead of typing one. [detected] (the framework's own selector
  /// for this role, if any) is surfaced first.
  static List<String> candidateSelectorsForRole(String role, {String? detected}) {
    final seen = <String>{};
    final out = <String>[];
    void add(String? s) {
      if (s == null) return;
      // A framework selector may be a comma list of alternatives — offer each.
      for (final part in s.split(',')) {
        final t = part.trim();
        if (t.isEmpty || !seen.add(t)) continue;
        out.add(t);
      }
    }

    add(detected);
    for (final m in _frameworkSelectors.values) {
      add(m[role]);
    }
    return out;
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
