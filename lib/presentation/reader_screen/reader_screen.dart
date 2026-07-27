import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:rhttp/rhttp.dart' as rhttp;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../core/providers/source_provider.dart';
import '../../core/providers/reader_provider.dart';
import '../../core/providers/library_provider.dart';
import '../../core/providers/tracking_provider.dart';
import '../../core/providers/download_provider.dart';
import '../library_screen/library_screen.dart' show kBookmarkedMangaIdsKey;
import '../../eval/model/page_url.dart';
import '../../theme/app_theme.dart';
import '../widgets/manga_image.dart';
import 'widgets/reader_translation_provider_sheet.dart';
import 'widgets/reader_translation_overlay.dart';
import '../../core/services/ai_translation_service.dart';
import '../../core/services/koharu_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReaderScreen extends StatelessWidget {
  final String chapterUrl;
  final String sourceId;
  final String? mangaUrl;
  final String? chapterTitle;
  final String? mangaTitle;
  final List<Map<String, dynamic>>? chapters;
  final int currentIndex;
  final int startPage;

  const ReaderScreen({
    super.key,
    required this.chapterUrl,
    required this.sourceId,
    this.mangaUrl,
    this.chapterTitle,
    this.mangaTitle,
    this.chapters,
    this.currentIndex = 0,
    this.startPage = 0,
  });

  @override
  Widget build(BuildContext context) {
    final sourceProvider = context.read<SourceProvider>();
    final installed = sourceProvider.getInstalledSource(sourceId);

    if (installed == null) {
      return const Scaffold(
        body: Center(child: Text('Source not installed')),
      );
    }

    return ChangeNotifierProvider(
      create: (_) => ReaderProvider(
        installedSource: installed,
        chapterUrl: chapterUrl,
        sourceId: sourceId,
        mangaTitle: mangaTitle ?? '',
        chapters: chapters,
        currentIndex: currentIndex,
        startPage: startPage,
      )..loadPages(),
      child: _ReaderBody(
        sourceId: sourceId,
        mangaUrl: mangaUrl,
        chapterTitle: chapterTitle,
        mangaTitle: mangaTitle,
      ),
    );
  }
}

class _ReaderBody extends StatefulWidget {
  final String sourceId;
  final String? mangaUrl;
  final String? chapterTitle;
  final String? mangaTitle;

  const _ReaderBody({
    required this.sourceId,
    this.mangaUrl,
    this.chapterTitle,
    this.mangaTitle,
  });

  @override
  State<_ReaderBody> createState() => _ReaderBodyState();
}

class _ReaderBodyState extends State<_ReaderBody>
    with TickerProviderStateMixin {
  late final AnimationController _hudController;
  late final Animation<double> _hudAnimation;
  PageController? _pageController;
  ScrollController? _scrollController;
  // Positioned list for accurate page tracking in vertical scroll mode
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener = ItemPositionsListener.create();
  int _sliderPage = 0; // Tracks slider position during drag
  bool _isInteracting = false; // User is touching HUD elements
  bool _sliderInitialized = false; // One-time sync after pages load
  // Last wakelock state we pushed to the OS, so build() only calls the plugin
  // when the "Keep Screen On" setting actually changes rather than every frame.
  bool? _wakelockApplied;

  // Translation state
  bool _translationEnabled = false; // loaded from settings
  bool _isTranslationActive = false;
  final bool _showTranslated = true; // global translated-vs-original toggle
  String _selectedProviderName = 'Claude';
  String _selectedProviderId = 'gemini';
  // Per-page translation. Bubbles keyed by page index so each image carries its
  // own overlay (positions correctly and scrolls with the image); the image
  // size feeds the overlay's letterbox math; _pageTranslating guards re-runs.
  final Map<int, List<TranslationBubble>> _pageBubbles = {};
  final Map<int, Size> _pageImgSize = {};
  final Set<int> _pageTranslating = {};
  final Set<int> _pageDone = {}; // attempted (success OR fail) — don't re-run
  bool get _isTranslating => _pageTranslating.isNotEmpty;
  final _translationService = AiTranslationService();
  final _koharuService = KoharuService();
  final Map<int, Uint8List> _koharuImageCache = {};
  late final AnimationController _translationAnimController;
  late final Animation<double> _translationAnimation;

  @override
  void initState() {
    super.initState();
    // Default to immersive; the actual mode is reapplied from ReaderSettings
    // once the provider has finished loading prefs (see post-frame callback
    // below).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _hudController = AnimationController(
      duration: AppTheme.standard,
      vsync: this,
    );
    _hudAnimation = CurvedAnimation(
      parent: _hudController,
      curve: AppTheme.primaryCurve,
    );
    _translationAnimController = AnimationController(
      duration: const Duration(milliseconds: 400), vsync: this);
    _translationAnimation = CurvedAnimation(
      parent: _translationAnimController, curve: Curves.easeOutBack);

    // Listen for visible page changes in scroll mode
    _itemPositionsListener.itemPositions.addListener(_onPositionChanged);

    // Sync slider, load AI provider, and show HUD briefly on open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final reader = context.read<ReaderProvider>();
      setState(() => _sliderPage = reader.currentPage);
      _hudController.forward();
      reader.toggleHud();
      _scheduleAutoHide(reader);
      _loadProviderName();
    });
  }

  void _onPositionChanged() {
    if (!mounted) return;
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    final reader = context.read<ReaderProvider>();
    if (reader.totalPages == 0) return;

    // First visible item = current page
    final validPositions = positions.where((p) => p.itemTrailingEdge > 0);
    if (validPositions.isEmpty) return;
    final firstVisible = validPositions.reduce((a, b) => a.index < b.index ? a : b);
    final page = firstVisible.index.clamp(0, reader.totalPages - 1);

    if (page != reader.currentPage) {
      reader.setPage(page);
      if (mounted) setState(() => _sliderPage = page);
      _updateProgress(reader, page);
    }

    // Trigger next chapter when user scrolls to end card (only when
    // auto-preload is enabled in Reader settings).
    final lastVisible = positions.reduce((a, b) => a.index > b.index ? a : b);
    if (reader.settings.autoPreload &&
        lastVisible.index >= reader.totalPages &&
        !reader.isLoadingNext &&
        !reader.isLastChapter &&
        !reader.nextChapterError) {
      reader.loadNextChapter();
    }

    // Live translation: as new pages scroll into view, translate them. Cheap
    // no-op for pages already done or in flight (guarded in _translatePage).
    if (_isTranslationActive) _translateVisiblePages();
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onPositionChanged);
    _hudController.dispose();
    _pageController?.dispose();
    _scrollController?.dispose();
    _translationAnimController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Never leave the wakelock held once the reader is gone.
    if (_wakelockApplied == true) {
      WakelockPlus.disable().catchError((_) {});
    }
    super.dispose();
  }

  /// Enables/disables the OS keep-awake lock to match [on], but only when the
  /// desired state differs from what we last pushed — build() runs on every
  /// frame and the plugin call is a platform round-trip. Wrapped so an
  /// unsupported platform (or a transient failure) can never crash the reader.
  void _applyWakelock(bool on) {
    if (_wakelockApplied == on) return;
    _wakelockApplied = on;
    WakelockPlus.toggle(enable: on).catchError((_) {});
  }

  void _toggleHud(ReaderProvider reader) {
    if (reader.showHud) {
      if (_isInteracting) return; // Don't hide while user is interacting
      _hudController.reverse();
    } else {
      _hudController.forward();
      _scheduleAutoHide(reader);
    }
    reader.toggleHud();
  }

  void _scheduleAutoHide(ReaderProvider reader) {
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && reader.showHud && !_isInteracting) {
        _hudController.reverse();
        reader.toggleHud();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ReaderProvider>(
      builder: (_, reader, __) {
        // Sync slider to currentPage once pages are loaded
        if (!_sliderInitialized && reader.pages.isNotEmpty) {
          _sliderInitialized = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _sliderPage = reader.currentPage);
          });
        }
        // Apply fullscreen pref. Re-issued each build so toggling settings
        // mid-session takes effect on the next rebuild.
        SystemChrome.setEnabledSystemUIMode(reader.settings.fullscreen
            ? SystemUiMode.immersiveSticky
            : SystemUiMode.edgeToEdge);
        // Keep the screen awake while reading if enabled. Guarded so it only
        // hits the plugin when the setting changes.
        _applyWakelock(reader.settings.keepScreenOn);
        final onBg = _onBgFor(reader.settings.bgColor, context);
        _onBg = onBg;
        return Scaffold(
          backgroundColor: _bgColorFor(reader.settings.bgColor, context),
          body: Stack(
            children: [
              // Page content
              if (reader.isLoading && reader.pages.isEmpty)
                Center(
                  child: CircularProgressIndicator(color: onBg),
                )
              else if (reader.error != null && reader.pages.isEmpty)
                _buildError(reader)
              else
                _buildReader(context, reader),

              // Translation bubbles are now drawn per-page (see _buildPageImage
              // and the paginated itemBuilder) so they ride along with each
              // image as the user scrolls, instead of a single viewport overlay
              // that stayed fixed while the page moved underneath it.

              // A subtle top-of-screen indicator while any page is translating.
              if (_translationEnabled && _isTranslationActive && _isTranslating)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(140),
                          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white)),
                          ),
                          const SizedBox(width: 8),
                          Text('Translating…',
                            style: GoogleFonts.manrope(
                              fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                        ]),
                      ),
                    ),
                  ),
                ),

              // HUD overlay (animated fade)
              if (reader.showHud || _hudController.isAnimating)
                IgnorePointer(
                  ignoring: !reader.showHud,
                  child: FadeTransition(
                    opacity: _hudAnimation,
                    child: _buildHud(context, reader),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Foreground for anything painted directly on the reader background.
  ///
  /// Cached so the page/error builders don't need a BuildContext threaded
  /// through them; set from build() where the background is already resolved.
  /// Defaults to white for the common dark case before the first build.
  Color _onBg = Colors.white;

  Widget _buildError(ReaderProvider reader) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              color: _onBg.withAlpha(190), size: 48),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(reader.error!,
                style: GoogleFonts.manrope(color: _onBg.withAlpha(210), fontSize: 13),
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => reader.loadPages(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text('Retry', style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildReader(BuildContext context, ReaderProvider reader) {
    switch (reader.readingMode) {
      case ReadingMode.ltr:
      case ReadingMode.rtl:
        return _buildPagedReader(context, reader);
      case ReadingMode.vertical:
      case ReadingMode.webtoon:
        return _buildScrollReader(context, reader);
    }
  }

  Widget _buildPagedReader(BuildContext context, ReaderProvider reader) {
    _pageController ??= PageController(initialPage: reader.currentPage);
    final screenWidth = MediaQuery.of(context).size.width;
    final s = reader.settings;
    final fit = _boxFitFor(s.scaleType);
    final filter = _imageColorFilter(s);

    void goPrev() {
      if (reader.currentPage > 0) {
        _pageController?.previousPage(
          duration: AppTheme.standard,
          curve: AppTheme.primaryCurve,
        );
      } else if (reader.hasPreviousChapter) {
        reader.goToPreviousChapter();
      }
    }

    void goNext() {
      if (reader.currentPage < reader.totalPages - 1) {
        _pageController?.nextPage(
          duration: AppTheme.standard,
          curve: AppTheme.primaryCurve,
        );
      } else if (reader.hasNextChapter) {
        reader.goToNextChapter();
      }
    }

    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          reverse: reader.readingMode == ReadingMode.rtl,
          itemCount: reader.pages.length,
          onPageChanged: (page) {
            reader.setPage(page);
            setState(() => _sliderPage = page);
            _updateProgress(reader, page);
            // Translate the page that just came into view.
            if (_isTranslationActive) _translatePage(page);
            // Auto-preload next chapter when within last 2 pages.
            if (s.autoPreload &&
                !reader.isLoadingNext &&
                !reader.isLastChapter &&
                page >= reader.totalPages - 2) {
              reader.loadNextChapter();
            }
          },
          itemBuilder: (_, i) {
            final pageUrl = reader.pages[i];
            Widget image = MangaImage(
              imageUrl: pageUrl.url,
              referer: pageUrl.headers?['Referer'],
              fit: fit,
              width: double.infinity,
              height: double.infinity,
              translatedBytes: _isTranslationActive ? _koharuImageCache[i] : null,
              placeholder: Center(
                child: CircularProgressIndicator(color: _onBg.withAlpha(150)),
              ),
              errorWidget: Center(
                child: Icon(Icons.broken_image_rounded, color: _onBg.withAlpha(150), size: 48),
              ),
            );
            if (filter != null) {
              image = ColorFiltered(colorFilter: filter, child: image);
            }
            // Overlay bubbles (non-koharu providers draw boxes; koharu bakes
            // the translation into translatedBytes above). The overlay fills
            // the page box and maps normalized bounds into the displayed image
            // rect, so it stays put over the text as the page zooms/pans.
            final bubbles = _pageBubbles[i];
            if (_isTranslationActive &&
                _selectedProviderId != 'koharu' &&
                bubbles != null &&
                bubbles.isNotEmpty) {
              image = Stack(
                fit: StackFit.expand,
                children: [
                  image,
                  Positioned.fill(
                    child: ReaderTranslationOverlay(
                      bubbles: bubbles,
                      animation: _translationAnimation,
                      imageSize: _pageImgSize[i],
                      fitWidth: fit == BoxFit.fitWidth,
                      showTranslated: _showTranslated,
                    ),
                  ),
                ],
              );
            }
            return InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: image,
            );
          },
        ),
        // Tap zones — layout/inversion driven by Reader settings.
        if (s.navLayout != 'Disabled')
          _buildTapZones(
            screenWidth: screenWidth,
            navLayout: s.navLayout,
            inverted: s.invertTapZones,
            onPrev: goPrev,
            onNext: goNext,
            onCenter: () => _toggleHud(reader),
          ),
      ],
    );
  }

  Widget _buildTapZones({
    required double screenWidth,
    required String navLayout,
    required bool inverted,
    required VoidCallback onPrev,
    required VoidCallback onNext,
    required VoidCallback onCenter,
  }) {
    // Edge layout = thinner side zones (15% each), bigger center.
    final sideFraction = navLayout == 'Edge' ? 0.15 : 0.25;
    final centerFraction = 1.0 - 2 * sideFraction;
    final leftAction = inverted ? onNext : onPrev;
    final rightAction = inverted ? onPrev : onNext;

    return Row(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: leftAction,
          child: SizedBox(
              width: screenWidth * sideFraction, height: double.infinity),
        ),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onCenter,
          child: SizedBox(
              width: screenWidth * centerFraction, height: double.infinity),
        ),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: rightAction,
          child: SizedBox(
              width: screenWidth * sideFraction, height: double.infinity),
        ),
      ],
    );
  }

  Widget _buildScrollReader(BuildContext context, ReaderProvider reader) {
    final itemCount = reader.pages.length + 1;

    return ScrollablePositionedList.builder(
        itemScrollController: _itemScrollController,
        itemPositionsListener: _itemPositionsListener,
        initialScrollIndex: reader.currentPage.clamp(0, reader.pages.length - 1),
        itemCount: itemCount,
        minCacheExtent: 2000,
        itemBuilder: (_, i) {
          // End card (after all loaded pages)
          if (i == reader.pages.length) {
            if (reader.isLoadingNext) {
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(children: [
                  CircularProgressIndicator(color: _onBg.withAlpha(150)),
                  const SizedBox(height: 16),
                  Text('Loading next chapter...',
                      style: GoogleFonts.manrope(fontSize: 13, color: _onBg.withAlpha(165))),
                ]),
              );
            }
            if (reader.isLastChapter) {
              return _buildEndCard(context, isLast: true);
            }
            if (reader.nextChapterError) {
              return _buildEndCard(context, isLast: false, onNext: () {
                reader.loadNextChapter();
              });
            }
            // Auto-loading triggered by _onPositionChanged
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: CircularProgressIndicator(color: _onBg.withAlpha(120)),
              ),
            );
          }

          // Check if this page index is a chapter boundary — show divider
          final boundary = reader.getBoundaryAt(i);
          if (boundary != null) {
            return Column(
              children: [
                _buildChapterTransition(context, boundary),
                _buildPageImage(reader.pages[i], i),
              ],
            );
          }

          return GestureDetector(
            onTap: () => _toggleHud(reader),
            child: _buildPageImage(reader.pages[i], i),
          );
        },
    );
  }


  Widget _buildPageImage(PageUrl pageUrl, int index) {
    final reader = context.read<ReaderProvider>();
    final filter = _imageColorFilter(reader.settings);
    final translatedBytes = _isTranslationActive ? _koharuImageCache[index] : null;

    Widget image;
    // Local file (downloaded chapter)
    if (pageUrl.url.startsWith('file://')) {
      final path = pageUrl.url.replaceFirst('file://', '');
      image = Image.file(
        File(path),
        fit: BoxFit.fitWidth,
        width: double.infinity,
        errorBuilder: (_, __, ___) => SizedBox(
          height: 400,
          child: Center(child: Icon(Icons.broken_image_rounded, color: _onBg.withAlpha(150), size: 48)),
        ),
      );
    } else {
      image = MangaImage(
        imageUrl: pageUrl.url,
        referer: pageUrl.headers?['Referer'],
        fit: BoxFit.fitWidth,
        width: double.infinity,
        translatedBytes: translatedBytes,
        placeholder: SizedBox(
          height: 400,
          child: Center(child: CircularProgressIndicator(color: _onBg.withAlpha(150))),
        ),
        errorWidget: SizedBox(
          height: 400,
          child: Center(child: Icon(Icons.broken_image_rounded, color: _onBg.withAlpha(150), size: 48)),
        ),
      );
    }
    if (filter != null) {
      image = ColorFiltered(colorFilter: filter, child: image);
    }
    // Bubbles ride on top of THIS image. In webtoon mode the image is
    // fit-width with intrinsic height, so the item's box equals the displayed
    // image (no letterbox) — the overlay maps bounds straight onto it. koharu
    // bakes its translation into the bytes, so it needs no overlay.
    final bubbles = _pageBubbles[index];
    if (_isTranslationActive &&
        _selectedProviderId != 'koharu' &&
        bubbles != null &&
        bubbles.isNotEmpty) {
      return Stack(
        children: [
          image,
          Positioned.fill(
            child: ReaderTranslationOverlay(
              bubbles: bubbles,
              animation: _translationAnimation,
              imageSize: _pageImgSize[index],
              fitWidth: true,
              showTranslated: _showTranslated,
            ),
          ),
        ],
      );
    }
    return image;
  }

  Widget _buildChapterTransition(BuildContext context, ChapterBoundary boundary) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      color: const Color(0xFF1A1A2E),
      child: Column(
        children: [
          if (boundary.prevChapterName != null)
            Text('Finished: ${boundary.prevChapterName}',
                style: GoogleFonts.manrope(fontSize: 12, color: _onBg.withAlpha(165)),
                textAlign: TextAlign.center),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              Expanded(child: Divider(color: _onBg.withAlpha(120))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.arrow_downward_rounded, color: cs.primary, size: 20),
              ),
              Expanded(child: Divider(color: _onBg.withAlpha(120))),
            ]),
          ),
          if (boundary.nextChapterName != null)
            Text(boundary.nextChapterName!,
                style: GoogleFonts.manrope(
                    fontSize: 14, fontWeight: FontWeight.w700, color: _onBg.withAlpha(200)),
                textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildEndCard(BuildContext context, {required bool isLast, VoidCallback? onNext}) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
      child: Column(children: [
        Icon(
          isLast ? Icons.check_circle_outline_rounded : Icons.arrow_downward_rounded,
          color: isLast ? Colors.white54 : cs.primary,
          size: 48,
        ),
        const SizedBox(height: 16),
        Text(
          isLast ? 'You\'re all caught up!' : 'End of Chapter',
          style: GoogleFonts.manrope(
              fontSize: 16, fontWeight: FontWeight.w700, color: _onBg.withAlpha(200)),
        ),
        const SizedBox(height: 8),
        if (isLast)
          Text('This is the latest chapter available.',
              style: GoogleFonts.manrope(fontSize: 13, color: _onBg.withAlpha(165)),
              textAlign: TextAlign.center)
        else if (onNext != null)
          FilledButton.icon(
            icon: const Icon(Icons.skip_next_rounded, size: 20),
            label: Text('Load Next Chapter',
                style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: onNext,
          ),
      ]),
    );
  }

  // ── HUD ────────────────────────────────────────────────────────────────

  Widget _buildHud(BuildContext context, ReaderProvider reader) {
    return Column(
      children: [
        GestureDetector(
          onTapDown: (_) => _isInteracting = true,
          onTapUp: (_) { _isInteracting = false; _scheduleAutoHide(reader); },
          onTapCancel: () { _isInteracting = false; _scheduleAutoHide(reader); },
          child: _buildTopBar(context, reader),
        ),
        const Spacer(),
        GestureDetector(
          onTapDown: (_) => _isInteracting = true,
          onTapUp: (_) { _isInteracting = false; _scheduleAutoHide(reader); },
          onTapCancel: () { _isInteracting = false; _scheduleAutoHide(reader); },
          child: _buildBottomBar(context, reader),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context, ReaderProvider reader) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 4,
        left: 8,
        right: 8,
        bottom: 24,
      ),
      child: Row(
        children: [
          _HudButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.mangaTitle ?? 'Reader',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.manrope(
                    fontSize: reader.settings.fontSize * 0.875,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                ),
                if (widget.chapterTitle != null)
                  Text(
                    widget.chapterTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.manrope(
                      fontSize: reader.settings.fontSize * 0.6875,
                      fontWeight: FontWeight.w500,
                      color: _onBg.withAlpha(200),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _HudButton(
            icon: Icons.tune_rounded,
            onTap: () => _showSettingsSheet(context, reader),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, ReaderProvider reader) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 12,
        left: 16,
        right: 16,
        top: 24,
      ),
      child: Column(
        children: [
          // Page slider
          if (reader.totalPages > 0)
            Row(
              children: [
                if (reader.settings.showPageNumber)
                  Text(
                    '${_sliderPage + 1}',
                    style: GoogleFonts.manrope(
                      fontSize: reader.settings.fontSize * 0.75,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: Theme.of(context).colorScheme.primary,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Theme.of(context).colorScheme.primary,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _sliderPage.toDouble().clamp(0, (reader.totalPages - 1).toDouble()),
                      min: 0,
                      max: (reader.totalPages - 1).toDouble().clamp(1, double.infinity),
                      divisions: reader.totalPages > 1 ? reader.totalPages - 1 : 1,
                      onChangeStart: (_) => _isInteracting = true,
                      onChanged: (value) {
                        final page = value.round();
                        setState(() => _sliderPage = page);
                        reader.setPage(page);
                        _jumpToPage(reader, page);
                      },
                      onChangeEnd: (_) {
                        _isInteracting = false;
                        _scheduleAutoHide(reader);
                      },
                    ),
                  ),
                ),
                if (reader.settings.showPageNumber)
                  Text(
                    '${reader.totalPages}',
                    style: GoogleFonts.manrope(
                      fontSize: reader.settings.fontSize * 0.75,
                      fontWeight: FontWeight.w700,
                      color: _onBg.withAlpha(200),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          // AI Translation toggle + provider (hidden if disabled in settings)
          if (_translationEnabled) Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _isTranslationActive = !_isTranslationActive;
                    if (!_isTranslationActive) {
                      _pageBubbles.clear();
                      _pageImgSize.clear();
                      _pageDone.clear();
                      _pageTranslating.clear();
                      _koharuImageCache.clear();
                      _translationAnimController.reset();
                    }
                  });
                  // Kick off translation for whatever's on screen; scrolling
                  // then translates new pages as they come into view.
                  if (_isTranslationActive) _translateVisiblePages();
                },
                child: AnimatedContainer(
                  duration: AppTheme.standard,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: _isTranslationActive
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white.withAlpha(38),
                    borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                    border: Border.all(
                      color: _isTranslationActive
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white38, width: 1),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_isTranslating)
                      const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white)))
                    else
                      Icon(Icons.translate_rounded, size: 14,
                          color: _isTranslationActive ? Colors.white : Colors.white70),
                    const SizedBox(width: 6),
                    Text(
                      _isTranslating ? 'Translating...' : 'AI Translate',
                      style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700,
                          color: _isTranslationActive ? Colors.white : Colors.white70),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _showProviderSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(31),
                      borderRadius: BorderRadius.circular(AppTheme.radiusFull),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_selectedProviderName,
                          style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: _onBg.withAlpha(200))),
                      const SizedBox(width: 3),
                      Icon(Icons.expand_more_rounded, size: 13, color: _onBg.withAlpha(150)),
                    ]),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Chapter navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _HudButton(
                icon: Icons.skip_previous_rounded,
                onTap: reader.hasPreviousChapter
                    ? () => reader.goToPreviousChapter()
                    : () {},
                tooltip: 'Previous chapter',
                size: 20,
              ),
              const SizedBox(width: 24),
              _HudButton(
                icon: Icons.bookmark_border_rounded,
                onTap: () {},
                tooltip: 'Bookmark',
                size: 18,
              ),
              const SizedBox(width: 24),
              _HudButton(
                icon: Icons.skip_next_rounded,
                onTap: reader.hasNextChapter
                    ? () => reader.goToNextChapter()
                    : () {},
                tooltip: 'Next chapter',
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Translate every page currently visible on screen. Works for both readers:
  /// webtoon exposes visible indices via [_itemPositionsListener]; paginated
  /// has one page, so we fall back to [ReaderProvider.currentPage].
  void _translateVisiblePages() {
    if (!_isTranslationActive || !_translationEnabled) return;
    final reader = context.read<ReaderProvider>();
    if (reader.pages.isEmpty) return;

    final indices = <int>{};
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      for (final p in positions) {
        if (p.index >= 0 && p.index < reader.pages.length) indices.add(p.index);
      }
    }
    if (indices.isEmpty) {
      indices.add(reader.currentPage.clamp(0, reader.pages.length - 1));
    }
    for (final i in indices) {
      _translatePage(i);
    }
  }

  /// Translate a single page and store the result keyed by [index]. Guarded so
  /// each page is fetched/OCR'd at most once — repeated scroll callbacks are
  /// cheap no-ops. On failure the page is still marked done (no retry storm).
  Future<void> _translatePage(int index) async {
    final reader = context.read<ReaderProvider>();
    if (index < 0 || index >= reader.pages.length) return;
    if (_pageDone.contains(index) || _pageTranslating.contains(index)) return;

    setState(() => _pageTranslating.add(index));

    try {
      final page = reader.pages[index];
      Uint8List imageBytes;

      if (page.url.startsWith('file://')) {
        final path = page.url.replaceFirst('file://', '');
        imageBytes = await File(path).readAsBytes();
      } else {
        final client = await rhttp.RhttpClient.create();
        try {
          final response = await client.requestBytes(
            method: rhttp.HttpMethod.get, url: page.url,
            headers: page.headers != null ? rhttp.HttpHeaders.rawMap(page.headers!) : null);
          imageBytes = response.body;
        } finally {
          client.dispose();
        }
      }

      // Natural pixel size drives the overlay's letterbox math in paginated
      // (fit-contain) mode. Best-effort; null just means "assume fills box".
      final imgSize = await _decodeImageSize(imageBytes);

      if (_selectedProviderId == 'koharu') {
        final prefs = await SharedPreferences.getInstance();
        final targetLang = prefs.getString('ai_target_language') ?? 'en';
        final translated = await _koharuService.translatePage(
          imageBytes,
          targetLang: targetLang,
          translator: 'google',
        );
        if (mounted) {
          setState(() {
            _koharuImageCache[index] = translated;
            if (imgSize != null) _pageImgSize[index] = imgSize;
            _pageTranslating.remove(index);
            _pageDone.add(index);
          });
        }
        return;
      }

      final cacheKey = '${widget.sourceId}_$index';
      final result = await _translationService.translatePage(imageBytes, cacheKey: cacheKey);

      if (mounted) {
        setState(() {
          _pageBubbles[index] = result.regions.map((r) => TranslationBubble(
            id: '${r.x}_${r.y}',
            bounds: Rect.fromLTWH(r.x, r.y, r.w, r.h),
            originalText: r.originalText,
            translatedText: r.translatedText,
            isTranslated: true,
          )).toList();
          if (imgSize != null) _pageImgSize[index] = imgSize;
          _pageTranslating.remove(index);
          _pageDone.add(index);
        });
        _translationAnimController.forward(from: 0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _pageTranslating.remove(index);
          _pageDone.add(index); // don't hammer a page that keeps failing
        });
        // Only surface the error for the page the user is actually looking at,
        // so background scroll prefetch can't spam snackbars.
        if (index == reader.currentPage) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Translation failed: $e'), duration: const Duration(seconds: 3)));
        }
      }
    }
  }

  /// Decode just the dimensions of an encoded image. Returns null on failure.
  Future<Size?> _decodeImageSize(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadProviderName() async {
    final name = await ReaderTranslationProviderSheet.getProviderName();
    final prefs = await SharedPreferences.getInstance();
    // Default OFF to match Settings > AI (which also defaults false). The old
    // `?? true` here meant the reader showed the Translate button even when the
    // setting read as disabled — the feature must be opt-in.
    final enabled = prefs.getBool('ai_translation_enabled') ?? false;
    final id = prefs.getString('ai_provider') ?? 'gemini';
    if (mounted) setState(() { _selectedProviderName = name; _translationEnabled = enabled; _selectedProviderId = id; });
  }

  void _showProviderSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (_) => ReaderTranslationProviderSheet(
        onChanged: () => _loadProviderName(),
      ),
    );
  }

  void _showSettingsSheet(BuildContext context, ReaderProvider reader) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outline.withAlpha(77),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text('Reading Mode',
                style: GoogleFonts.manrope(
                    fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 12),
            ...ReadingMode.values.map((mode) {
              final isSelected = mode == reader.readingMode;
              return GestureDetector(
                onTap: () {
                  reader.setReadingMode(mode);
                  Navigator.pop(context);
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary.withAlpha(26)
                        : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? Theme.of(context).colorScheme.primary : cs.outlineVariant,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _modeIcon(mode),
                        size: 20,
                        color: isSelected ? Theme.of(context).colorScheme.primary : cs.outline,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_modeLabel(mode),
                                style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Theme.of(context).colorScheme.primary : cs.onSurface,
                                )),
                            Text(_modeSubtitle(mode),
                                style: GoogleFonts.manrope(
                                    fontSize: 11, color: cs.outline)),
                          ],
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.check_circle_rounded,
                            size: 20, color: cs.primary),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _jumpToPage(ReaderProvider reader, int page) {
    if (reader.readingMode == ReadingMode.ltr ||
        reader.readingMode == ReadingMode.rtl) {
      if (_pageController?.hasClients == true) {
        _pageController!.jumpToPage(page);
      }
    } else {
      // Use ScrollablePositionedList's precise item-based scrolling
      if (_itemScrollController.isAttached) {
        _itemScrollController.jumpTo(index: page);
      }
    }
    _updateProgress(reader, page);
  }

  void _updateProgress(ReaderProvider reader, int page) {
    if (widget.mangaUrl == null) return;
    try {
      final libraryProvider = context.read<LibraryProvider>();
      libraryProvider.updateReadingProgress(
        widget.sourceId,
        widget.mangaUrl!,
        reader.currentChapterUrl,
        page,
      );
      // Download Ahead While Reading: once the user is committed to a
      // chapter (~30% in), queue the next chapter for download. The
      // DownloadProvider deduplicates against in-flight + already downloaded.
      final dl = context.read<DownloadProvider>();
      if (dl.downloadWhileReading &&
          reader.totalPages > 0 &&
          page >= (reader.totalPages * 0.3).floor()) {
        final next = reader.nextChapterInfo;
        if (next != null && next['url']!.isNotEmpty) {
          dl.enqueueChapter(
            sourceId: widget.sourceId,
            mangaUrl: widget.mangaUrl!,
            mangaTitle: widget.mangaTitle ?? '',
            chapterUrl: next['url']!,
            chapterName: next['name'] ?? '',
          );
        }
      }
      // Mark chapter as read when reaching the last page
      if (page >= reader.totalPages - 1) {
        libraryProvider.markChapterRead(
          widget.sourceId,
          widget.mangaUrl!,
          reader.currentChapterUrl,
        );
        _syncTracking(reader);
        _applyAutoDeleteRules(reader, dl);
      }
    } catch (_) {}
  }

  /// Push the just-read chapter's number to any connected trackers bound to
  /// this manga. Fire-and-forget; never interrupts reading.
  void _syncTracking(ReaderProvider reader) {
    if (widget.mangaUrl == null) return;
    try {
      final name = reader.currentChapterName.isNotEmpty
          ? reader.currentChapterName
          : (widget.chapterTitle ?? '');
      final n = _chapterNumberOf(name);
      if (n <= 0) return;
      context
          .read<TrackingProvider>()
          .syncChapterRead('${widget.sourceId}_${widget.mangaUrl}', n);
    } catch (_) {}
  }

  /// Best-effort parse of a chapter number from its title (e.g. "Chapter 45.5"
  /// -> 45). Prefers a number after chapter/ch/ep, else the last number found.
  int _chapterNumberOf(String name) {
    final labeled = RegExp(
            r'(?:chapter|chap|ch|episode|ep|#)\s*[.:]?\s*(\d+(?:\.\d+)?)',
            caseSensitive: false)
        .firstMatch(name);
    String? numStr = labeled?.group(1);
    if (numStr == null) {
      final all = RegExp(r'\d+(?:\.\d+)?').allMatches(name).toList();
      if (all.isNotEmpty) numStr = all.last.group(0);
    }
    if (numStr == null) return 0;
    return (double.tryParse(numStr) ?? 0).floor();
  }

  /// Honors `Delete After Reading`, `Auto-Delete Read Chapters`, and
  /// `Include Bookmarked Chapters` from the Downloads settings page. Called
  /// once the current chapter has been marked as read.
  Future<void> _applyAutoDeleteRules(
      ReaderProvider reader, DownloadProvider dl) async {
    if (widget.mangaUrl == null || (widget.mangaTitle ?? '').isEmpty) return;
    final mangaTitle = widget.mangaTitle!;

    // If this manga is bookmarked and the user hasn't opted into deleting
    // bookmarked chapters, skip both delete rules entirely.
    if (!dl.removeBookmarked) {
      final prefs = await SharedPreferences.getInstance();
      final bookmarks =
          (prefs.getStringList(kBookmarkedMangaIdsKey) ?? []).toSet();
      final mangaKey = '${widget.sourceId}::${widget.mangaUrl}';
      if (bookmarks.contains(mangaKey)) return;
    }

    // 1) Delete the just-read chapter outright if the user opted in.
    if (dl.deleteAfterRead) {
      final currentName = _safeChapterName(reader, reader.currentChapterIndex);
      if (currentName.isNotEmpty &&
          dl.isDownloaded(widget.sourceId, reader.currentChapterUrl)) {
        await dl.deleteDownload(
          widget.sourceId,
          mangaTitle,
          currentName,
          reader.currentChapterUrl,
        );
      }
    }

    // 2) Auto-delete the chapter that's `threshold` positions back, keeping
    //    a sliding window of the most recent reads on disk.
    final threshold = dl.autoDeleteThreshold;
    if (threshold > 0) {
      final old = reader.chapterAtOffset(threshold);
      if (old != null && old['url']!.isNotEmpty) {
        if (dl.isDownloaded(widget.sourceId, old['url']!)) {
          await dl.deleteDownload(
            widget.sourceId,
            mangaTitle,
            old['name'] ?? '',
            old['url']!,
          );
        }
      }
    }
  }

  String _safeChapterName(ReaderProvider reader, int idx) {
    if (idx < 0 || idx >= reader.chaptersCount) return '';
    return reader.chapterAtOffset(reader.currentChapterIndex - idx)?['name'] ?? '';
  }

  // ── Settings helpers ──────────────────────────────────────────────────

  /// Foreground for overlays drawn straight onto the reader background.
  ///
  /// The background is user-selectable and can be **white**, so the hardcoded
  /// `Colors.white` spinners, error text and placeholders these replace were
  /// invisible (1:1 contrast) for anyone using the White or light Automatic
  /// theme. Derive from the actual background instead.
  Color _onBgFor(String name, BuildContext context) =>
      ThemeData.estimateBrightnessForColor(_bgColorFor(name, context)) ==
              Brightness.dark
          ? Colors.white
          : Colors.black87;

  Color _bgColorFor(String name, BuildContext context) {
    switch (name) {
      case 'White':
        return Colors.white;
      case 'Gray':
        return const Color(0xFF1A1A1A);
      case 'Automatic':
        return Theme.of(context).brightness == Brightness.dark
            ? Colors.black
            : Colors.white;
      case 'Black':
      default:
        return Colors.black;
    }
  }

  BoxFit _boxFitFor(String name) {
    switch (name) {
      case 'Stretch':
        return BoxFit.fill;
      case 'Fit Width':
        return BoxFit.fitWidth;
      case 'Fit Height':
        return BoxFit.fitHeight;
      case 'Original Size':
        return BoxFit.none;
      case 'Smart Fit':
        return BoxFit.contain;
      case 'Fit Screen':
      default:
        return BoxFit.contain;
    }
  }

  /// Returns a ColorFilter that applies grayscale and/or invert as configured,
  /// or null if neither is enabled.
  ColorFilter? _imageColorFilter(ReaderSettings s) {
    final filters = <List<double>>[];
    if (s.grayscale) {
      filters.add(const [
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0,      0,      0,      1, 0,
      ]);
    }
    if (s.invertColors) {
      filters.add(const [
        -1, 0, 0, 0, 255,
        0, -1, 0, 0, 255,
        0, 0, -1, 0, 255,
        0, 0, 0, 1, 0,
      ]);
    }
    if (filters.isEmpty) return null;
    if (filters.length == 1) return ColorFilter.matrix(filters.first);
    // Compose: invert ∘ grayscale (apply grayscale first, then invert)
    return ColorFilter.matrix(_composeMatrices(filters[0], filters[1]));
  }

  /// 4x5 color matrix multiplication (b applied after a).
  List<double> _composeMatrices(List<double> a, List<double> b) {
    final out = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 5; col++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += b[row * 5 + k] * a[k * 5 + col];
        }
        if (col == 4) sum += b[row * 5 + 4];
        out[row * 5 + col] = sum;
      }
    }
    return out;
  }

  String _modeLabel(ReadingMode mode) => switch (mode) {
        ReadingMode.ltr => 'Left to Right',
        ReadingMode.rtl => 'Right to Left',
        ReadingMode.vertical => 'Continuous Scroll',
        ReadingMode.webtoon => 'Webtoon',
      };

  String _modeSubtitle(ReadingMode mode) => switch (mode) {
        ReadingMode.ltr => 'Tap left/right to turn pages',
        ReadingMode.rtl => 'Manga-style right to left',
        ReadingMode.vertical => 'Scroll vertically through pages',
        ReadingMode.webtoon => 'Optimized for long vertical strips',
      };

  IconData _modeIcon(ReadingMode mode) => switch (mode) {
        ReadingMode.ltr => Icons.auto_stories_rounded,
        ReadingMode.rtl => Icons.menu_book_rounded,
        ReadingMode.vertical => Icons.swap_vert_rounded,
        ReadingMode.webtoon => Icons.view_day_rounded,
      };
}

// ── HUD Button ─────────────────────────────────────────────────────────

class _HudButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final double size;

  const _HudButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusFull),
          splashColor: Colors.white24,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(AppTheme.radiusFull),
            ),
            child: Icon(icon, size: size, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
