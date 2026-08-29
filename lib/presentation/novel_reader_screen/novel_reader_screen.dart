import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers/library_provider.dart';
import '../../core/providers/source_provider.dart';
import '../../core/services/volume_keys.dart';
import '../../eval/lib.dart';

/// Text reader for light-novel sources. Fetches the chapter's HTML via the
/// source's `getHtmlContent`, renders it as readable paragraphs, and supports
/// font sizing + previous/next chapter navigation.
class NovelReaderScreen extends StatefulWidget {
  final String chapterUrl;
  final String sourceId;
  final String? mangaUrl;
  final String? chapterTitle;
  final String? mangaTitle;
  final List<Map<String, dynamic>>? chapters;
  final int currentIndex;
  final int startOffset;

  const NovelReaderScreen({
    super.key,
    required this.chapterUrl,
    required this.sourceId,
    this.mangaUrl,
    this.chapterTitle,
    this.mangaTitle,
    this.chapters,
    this.currentIndex = 0,
    this.startOffset = 0,
  });

  @override
  State<NovelReaderScreen> createState() => _NovelReaderScreenState();
}

class _NovelReaderScreenState extends State<NovelReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  // Volume-key hold detection: tap = scroll ~a screen, hold = slow fluid scroll.
  Timer? _holdTimer;
  Timer? _holdScrollTimer;
  bool _holdScrolling = false;
  double _volScrollSpeed = 600.0;
  // Continuous-text reading has no "pages", so we persist the exact SCROLL OFFSET
  // (debounced) and restore it, so "continue" lands where you actually stopped.
  Timer? _saveThrottle;
  LibraryProvider? _lib;
  double _lastOffset = 0;
  List<String> _paragraphs = [];
  bool _loading = true;
  String? _error;
  double _fontSize = 18;
  late int _index;
  late String _url;
  String? _title;

  @override
  void initState() {
    super.initState();
    _index = widget.currentIndex;
    _url = widget.chapterUrl;
    _title = widget.chapterTitle;
    _scrollController.addListener(_saveProgress);
    _load();
    _maybeEnableVolumeKeys();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lib ??= context.read<LibraryProvider>();
  }

  // Persist the scroll offset (as the manga's lastReadPage) a second after scrolling
  // stops, so it survives quick exits without saving on every pixel.
  void _saveProgress() {
    if (!_scrollController.hasClients) return;
    _lastOffset = _scrollController.offset;
    if (widget.mangaUrl == null) return;
    _saveThrottle?.cancel();
    _saveThrottle = Timer(const Duration(seconds: 1), () {
      if (!mounted || _lib == null) return;
      _lib!.updateReadingProgress(
          widget.sourceId, widget.mangaUrl!, _url, _lastOffset.round());
    });
  }

  void _restoreScroll() {
    if (widget.startOffset <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(widget.startOffset
          .toDouble()
          .clamp(0.0, _scrollController.position.maxScrollExtent));
    });
  }

  // Volume-button scrolling (Android, opt-in via Reader settings). Only while this
  // reader is open; disabled again in dispose so the buttons control volume elsewhere.
  Future<void> _maybeEnableVolumeKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final on = prefs.getBool('reader_volume_keys') ?? false;
    _volScrollSpeed = prefs.getDouble('reader_volume_scroll_speed') ?? 600.0;
    if (on && mounted) {
      VolumeKeys.enable(_onVolumeKey);
    }
  }

  /// A quick TAP scrolls ~a screen; HOLDING scrolls slowly and fluidly until released.
  void _onVolumeKey(String dir, String phase) {
    if (!mounted) return;
    final delta = dir == 'down' ? 1 : -1;
    if (phase == 'down') {
      _holdScrolling = false;
      _holdTimer?.cancel();
      _holdTimer = Timer(const Duration(milliseconds: 250), () {
        _holdScrolling = true;
        _beginHoldScroll(delta);
      });
    } else {
      _holdTimer?.cancel();
      if (_holdScrolling) {
        _holdScrolling = false;
        _holdScrollTimer?.cancel();
      } else {
        _tapScroll(delta);
      }
    }
  }

  void _tapScroll(int delta) {
    if (!_scrollController.hasClients) return;
    final page = _scrollController.position.viewportDimension * 0.85;
    final target = (_scrollController.offset + delta * page)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(target,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  void _beginHoldScroll(int delta) {
    const tick = Duration(milliseconds: 100);
    final step = delta * _volScrollSpeed * (tick.inMilliseconds / 1000.0);
    void scrollOnce() {
      if (!mounted || !_scrollController.hasClients) return;
      final target = (_scrollController.offset + step)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(target, duration: tick, curve: Curves.linear);
    }

    scrollOnce();
    _holdScrollTimer?.cancel();
    _holdScrollTimer = Timer.periodic(tick, (_) {
      if (!mounted || !_holdScrolling) {
        _holdScrollTimer?.cancel();
        return;
      }
      scrollOnce();
    });
  }

  @override
  void dispose() {
    VolumeKeys.disable();
    _saveThrottle?.cancel();
    _scrollController.removeListener(_saveProgress);
    if (widget.mangaUrl != null && _lib != null && _lastOffset > 0) {
      _lib!.updateReadingProgress(
          widget.sourceId, widget.mangaUrl!, _url, _lastOffset.round());
    }
    _holdTimer?.cancel();
    _holdScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final installed =
          context.read<SourceProvider>().getInstalledSource(widget.sourceId);
      if (installed == null) throw Exception('Source not installed');
      final html = await withExtensionService(
        installed.source,
        installed.sourceCode,
        (service) => service.getHtmlContent(_url),
      );
      _paragraphs = _toParagraphs(html);
      if (_paragraphs.isEmpty) _error = 'No chapter text found';
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) {
      setState(() => _loading = false);
      _restoreScroll();
    }
  }

  List<String> _toParagraphs(String html) {
    if (html.trim().isEmpty) return [];
    final doc = html_parser.parse(html);
    var paras = doc
        .querySelectorAll('p')
        .map((e) => e.text.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    if (paras.isEmpty) {
      final text = doc.body?.text ?? doc.documentElement?.text ?? '';
      paras = text
          .split(RegExp(r'\n\s*\n|\n'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return paras;
  }

  bool get _hasPrev =>
      widget.chapters != null && _index < widget.chapters!.length - 1;
  bool get _hasNext => widget.chapters != null && _index > 0;

  void _go(int delta) {
    final chapters = widget.chapters;
    if (chapters == null) return;
    final next = _index + delta;
    if (next < 0 || next >= chapters.length) return;
    setState(() {
      _index = next;
      _url = (chapters[next]['url'] ?? '').toString();
      _title = (chapters[next]['name'] ?? '').toString();
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title ?? widget.mangaTitle ?? 'Reading',
            style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Smaller text',
            icon: const Icon(Icons.text_decrease_rounded),
            onPressed: () => setState(
                () => _fontSize = (_fontSize - 1).clamp(12, 30).toDouble()),
          ),
          IconButton(
            tooltip: 'Larger text',
            icon: const Icon(Icons.text_increase_rounded),
            onPressed: () => setState(
                () => _fontSize = (_fontSize + 1).clamp(12, 30).toDouble()),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline_rounded, color: cs.error, size: 40),
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.manrope(fontSize: 13, color: cs.outline)),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _load, child: const Text('Retry')),
                ]))
              : ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.fromLTRB(
                      20, 16, 20, 32 + MediaQuery.of(context).viewPadding.bottom),
                  itemCount: _paragraphs.length + 1,
                  itemBuilder: (_, i) {
                    if (i == _paragraphs.length) return _navBar(cs);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SelectableText(
                        _paragraphs[i],
                        style: GoogleFonts.notoSerif(
                            fontSize: _fontSize, height: 1.7, color: cs.onSurface),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _navBar(ColorScheme cs) {
    if (widget.chapters == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        OutlinedButton.icon(
          onPressed: _hasPrev ? () => _go(1) : null,
          icon: const Icon(Icons.chevron_left_rounded, size: 18),
          label: const Text('Previous'),
        ),
        OutlinedButton.icon(
          onPressed: _hasNext ? () => _go(-1) : null,
          icon: const Icon(Icons.chevron_right_rounded, size: 18),
          label: const Text('Next'),
        ),
      ]),
    );
  }
}
