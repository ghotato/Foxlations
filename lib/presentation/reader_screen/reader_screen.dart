import 'dart:io';
import 'package:flutter/material.dart';
import 'package:rhttp/rhttp.dart' as rhttp;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../core/providers/source_provider.dart';
import '../../core/providers/reader_provider.dart';
import '../../core/providers/library_provider.dart';
import '../../eval/model/page_url.dart';
import '../../theme/app_theme.dart';
import '../widgets/manga_image.dart';
import 'widgets/reader_translation_provider_sheet.dart';
import 'widgets/reader_translation_overlay.dart';
import '../../core/services/ai_translation_service.dart';
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

  // Translation state
  bool _translationEnabled = false; // loaded from settings
  bool _isTranslationActive = false;
  bool _isTranslating = false;
  String _selectedProviderName = 'Claude';
  List<TranslationBubble> _translationBubbles = [];
  final _translationService = AiTranslationService();
  late final AnimationController _translationAnimController;
  late final Animation<double> _translationAnimation;

  @override
  void initState() {
    super.initState();
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

    // Trigger next chapter when user scrolls to end card
    final lastVisible = positions.reduce((a, b) => a.index > b.index ? a : b);
    if (lastVisible.index >= reader.totalPages &&
        !reader.isLoadingNext &&
        !reader.isLastChapter &&
        !reader.nextChapterError) {
      reader.loadNextChapter();
    }
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(_onPositionChanged);
    _hudController.dispose();
    _pageController?.dispose();
    _scrollController?.dispose();
    _translationAnimController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
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
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Page content
              if (reader.isLoading && reader.pages.isEmpty)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              else if (reader.error != null && reader.pages.isEmpty)
                _buildError(reader)
              else
                _buildReader(context, reader),

              // Translation overlay
              if (_translationEnabled && _isTranslationActive && (_translationBubbles.isNotEmpty || _isTranslating))
                ReaderTranslationOverlay(
                  bubbles: _translationBubbles,
                  animation: _translationAnimation,
                  isTranslating: _isTranslating,
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

  Widget _buildError(ReaderProvider reader) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white54, size: 48),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(reader.error!,
                style: GoogleFonts.manrope(color: Colors.white70, fontSize: 13),
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
          },
          itemBuilder: (_, i) {
            final pageUrl = reader.pages[i];
            return InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: MangaImage(
                imageUrl: pageUrl.url,
                referer: pageUrl.headers?['Referer'],
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                placeholder: const Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                ),
                errorWidget: const Center(
                  child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48),
                ),
              ),
            );
          },
        ),
        // Tap zones: left 25% = prev, center 50% = toggle HUD, right 25% = next
        Row(
          children: [
            // Left tap zone
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (reader.currentPage > 0) {
                  _pageController?.previousPage(
                    duration: AppTheme.standard,
                    curve: AppTheme.primaryCurve,
                  );
                } else if (reader.hasPreviousChapter) {
                  reader.goToPreviousChapter();
                }
              },
              child: SizedBox(width: screenWidth * 0.25, height: double.infinity),
            ),
            // Center tap zone
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _toggleHud(reader),
              child: SizedBox(width: screenWidth * 0.5, height: double.infinity),
            ),
            // Right tap zone
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (reader.currentPage < reader.totalPages - 1) {
                  _pageController?.nextPage(
                    duration: AppTheme.standard,
                    curve: AppTheme.primaryCurve,
                  );
                } else if (reader.hasNextChapter) {
                  reader.goToNextChapter();
                }
              },
              child: SizedBox(width: screenWidth * 0.25, height: double.infinity),
            ),
          ],
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
                  const CircularProgressIndicator(color: Colors.white54),
                  const SizedBox(height: 16),
                  Text('Loading next chapter...',
                      style: GoogleFonts.manrope(fontSize: 13, color: Colors.white38)),
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
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white24),
              ),
            );
          }

          // Check if this page index is a chapter boundary — show divider
          final boundary = reader.getBoundaryAt(i);
          if (boundary != null) {
            return Column(
              children: [
                _buildChapterTransition(context, boundary),
                _buildPageImage(reader.pages[i]),
              ],
            );
          }

          return GestureDetector(
            onTap: () => _toggleHud(reader),
            child: _buildPageImage(reader.pages[i]),
          );
        },
    );
  }


  Widget _buildPageImage(PageUrl pageUrl) {
    // Local file (downloaded chapter)
    if (pageUrl.url.startsWith('file://')) {
      final path = pageUrl.url.replaceFirst('file://', '');
      return Image.file(
        File(path),
        fit: BoxFit.fitWidth,
        width: double.infinity,
        errorBuilder: (_, __, ___) => const SizedBox(
          height: 400,
          child: Center(child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48)),
        ),
      );
    }
    // Remote image
    return MangaImage(
      imageUrl: pageUrl.url,
      referer: pageUrl.headers?['Referer'],
      fit: BoxFit.fitWidth,
      width: double.infinity,
      placeholder: const SizedBox(
        height: 400,
        child: Center(child: CircularProgressIndicator(color: Colors.white54)),
      ),
      errorWidget: const SizedBox(
        height: 400,
        child: Center(child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 48)),
      ),
    );
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
                style: GoogleFonts.manrope(fontSize: 12, color: Colors.white38),
                textAlign: TextAlign.center),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [
              const Expanded(child: Divider(color: Colors.white24)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.arrow_downward_rounded, color: cs.primary, size: 20),
              ),
              const Expanded(child: Divider(color: Colors.white24)),
            ]),
          ),
          if (boundary.nextChapterName != null)
            Text(boundary.nextChapterName!,
                style: GoogleFonts.manrope(
                    fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white70),
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
              fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white70),
        ),
        const SizedBox(height: 8),
        if (isLast)
          Text('This is the latest chapter available.',
              style: GoogleFonts.manrope(fontSize: 13, color: Colors.white38),
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
                    fontSize: 14,
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
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white70,
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
                Text(
                  '${_sliderPage + 1}',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
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
                Text(
                  '${reader.totalPages}',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
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
                      _translationBubbles = [];
                      _translationAnimController.reset();
                    } else {
                      _translateCurrentPage(reader);
                    }
                  });
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
                          style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70)),
                      const SizedBox(width: 3),
                      const Icon(Icons.expand_more_rounded, size: 13, color: Colors.white54),
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

  Future<void> _translateCurrentPage(ReaderProvider reader) async {
    if (reader.pages.isEmpty) return;
    setState(() { _isTranslating = true; _translationBubbles = []; });

    try {
      final page = reader.pages[reader.currentPage];
      Uint8List? imageBytes;

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

      final cacheKey = '${widget.sourceId}_${reader.currentPage}';
      final result = await _translationService.translatePage(imageBytes, cacheKey: cacheKey);

      if (mounted) {
        setState(() {
          _translationBubbles = result.regions.map((r) => TranslationBubble(
            id: '${r.x}_${r.y}',
            bounds: Rect.fromLTWH(r.x, r.y, r.w, r.h),
            originalText: r.originalText,
            translatedText: r.translatedText,
            isTranslated: true,
          )).toList();
          _isTranslating = false;
        });
        _translationAnimController.forward(from: 0);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isTranslating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Translation failed: $e'), duration: const Duration(seconds: 3)));
      }
    }
  }

  Future<void> _loadProviderName() async {
    final name = await ReaderTranslationProviderSheet.getProviderName();
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('ai_translation_enabled') ?? true;
    if (mounted) setState(() { _selectedProviderName = name; _translationEnabled = enabled; });
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
      // Mark chapter as read when reaching the last page
      if (page >= reader.totalPages - 1) {
        libraryProvider.markChapterRead(
          widget.sourceId,
          widget.mangaUrl!,
          reader.currentChapterUrl,
        );
      }
    } catch (_) {}
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
