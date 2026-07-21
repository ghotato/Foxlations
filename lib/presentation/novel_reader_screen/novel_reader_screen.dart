import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:provider/provider.dart';

import '../../core/providers/source_provider.dart';
import '../../eval/lib.dart';

/// Text reader for light-novel sources. Fetches the chapter's HTML via the
/// source's `getHtmlContent`, renders it as readable paragraphs, and supports
/// font sizing + previous/next chapter navigation.
class NovelReaderScreen extends StatefulWidget {
  final String chapterUrl;
  final String sourceId;
  final String? chapterTitle;
  final String? mangaTitle;
  final List<Map<String, dynamic>>? chapters;
  final int currentIndex;

  const NovelReaderScreen({
    super.key,
    required this.chapterUrl,
    required this.sourceId,
    this.chapterTitle,
    this.mangaTitle,
    this.chapters,
    this.currentIndex = 0,
  });

  @override
  State<NovelReaderScreen> createState() => _NovelReaderScreenState();
}

class _NovelReaderScreenState extends State<NovelReaderScreen> {
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
    _load();
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
    if (mounted) setState(() => _loading = false);
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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
