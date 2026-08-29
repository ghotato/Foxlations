import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/providers/source_provider.dart';
import '../../core/repoforge/framework_detector_service.dart';
import '../../core/repoforge/local_repo_service.dart';
import '../../core/repoforge/repoforge_fetcher.dart';
import '../../core/repoforge/source_adapter.dart';
import '../../theme/app_theme.dart';

/// In-app "Create Source" flow (RepoForge, local-only): enter a site URL,
/// detect its framework + selectors, tune selectors with live match-count
/// testing, then generate a JS source into the on-device "My Sources" repo and
/// install it.
class SourceCreatorScreen extends StatefulWidget {
  /// When provided (e.g. Edit from the RepoForge hub), the URL is prefilled and
  /// detection kicks off automatically.
  final String? seedUrl;

  const SourceCreatorScreen({super.key, this.seedUrl});

  @override
  State<SourceCreatorScreen> createState() => _SourceCreatorScreenState();
}

class _SourceCreatorScreenState extends State<SourceCreatorScreen> {
  // (selectorKey, friendly label)
  static const List<(String, String)> _roles = [
    ('item', 'List item (each card)'),
    ('title', 'Title'),
    ('cover', 'Cover image'),
    ('nextPage', 'Next-page link'),
    ('detailTitle', 'Detail — title'),
    ('chapters', 'Chapter list item'),
    ('page_images', 'Reader page images'),
    ('episodes', 'Episode list (anime)'),
  ];

  static const List<String> _detectSteps = [
    'Fetching page…',
    'Matching framework signatures…',
    'Extracting selectors…',
    'Finalizing…',
  ];

  final _urlCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  final _langCtl = TextEditingController();
  final _testUrlCtl = TextEditingController();
  final Map<String, TextEditingController> _selectorCtls = {
    for (final r in _roles) r.$1: TextEditingController(),
  };

  final _localRepo = LocalRepoService();

  @override
  void initState() {
    super.initState();
    final seed = widget.seedUrl;
    if (seed != null && seed.isNotEmpty) {
      _urlCtl.text = seed;
      WidgetsBinding.instance.addPostFrameCallback((_) => _detect());
    }
  }

  bool _detecting = false;
  int _detectStep = 0;
  String? _error;

  Map<String, dynamic>? _ext;
  String _contentType = 'manga';
  bool _nsfw = false;

  String? _fetchedHtml;
  bool _fetching = false;
  final Map<String, int> _testCounts = {}; // -1 invalid selector

  String? _jsPreview;
  bool _saving = false;

  @override
  void dispose() {
    _urlCtl.dispose();
    _nameCtl.dispose();
    _langCtl.dispose();
    _testUrlCtl.dispose();
    for (final c in _selectorCtls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _hostName(String url) {
    final host = Uri.tryParse(url.startsWith('http') ? url : 'https://$url')?.host ?? '';
    final cleaned = host.replaceFirst('www.', '');
    final base = cleaned.split('.').first;
    return base.isEmpty
        ? 'Source'
        : base[0].toUpperCase() + base.substring(1);
  }

  Future<void> _detect() async {
    final url = _urlCtl.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Enter a site URL first.');
      return;
    }
    setState(() {
      _detecting = true;
      _error = null;
      _detectStep = 0;
    });
    try {
      final ext = await FrameworkDetectorService.detect(
        url,
        onStep: (s) {
          if (mounted) setState(() => _detectStep = s.clamp(0, _detectSteps.length - 1));
        },
      );
      _seedFromExt(ext, url);
    } catch (e) {
      if (mounted) setState(() => _error = 'Detection failed: $e');
    } finally {
      if (mounted) setState(() => _detecting = false);
    }
  }

  void _seedFromExt(Map<String, dynamic> ext, String url) {
    _ext = ext;
    final detectedName = (ext['name'] as String?)?.trim();
    _nameCtl.text =
        (detectedName != null && detectedName.isNotEmpty) ? detectedName : _hostName(url);
    _langCtl.text = ((ext['language'] as String?) ?? 'en').trim();
    final ct = (ext['contentType'] as String?) ?? 'manga';
    _contentType = (ct == 'anime' || ct == 'novel') ? ct : 'manga';
    _nsfw = ext['nsfw'] as bool? ?? false;

    final sel = (ext['selectors'] as Map?) ?? const {};
    for (final r in _roles) {
      _selectorCtls[r.$1]!.text = (sel[r.$1] ?? '').toString();
    }
    _testUrlCtl.text = ((ext['sourceUrl'] as String?)?.isNotEmpty ?? false)
        ? ext['sourceUrl'] as String
        : url;
    _testCounts.clear();
    _jsPreview = null;
    setState(() {});
  }

  /// Merge detection + user edits back into a generator-ready ext map.
  Map<String, dynamic> _buildExt() {
    final ext = Map<String, dynamic>.from(_ext ?? {});
    final name = _nameCtl.text.trim();
    ext['name'] = name.isEmpty ? _hostName(_urlCtl.text.trim()) : name;
    final lang = _langCtl.text.trim();
    ext['language'] = lang.isEmpty ? 'en' : lang;
    ext['contentType'] = _contentType;
    ext['nsfw'] = _nsfw;
    final srcUrl = (ext['sourceUrl'] as String?) ?? '';
    ext['sourceUrl'] = srcUrl.isNotEmpty ? srcUrl : _urlCtl.text.trim();
    ext['framework'] = (ext['framework'] as String?) ?? 'Custom';

    final sel = Map<String, dynamic>.from((ext['selectors'] as Map?) ?? {});
    for (final r in _roles) {
      final v = _selectorCtls[r.$1]!.text.trim();
      if (v.isNotEmpty) sel[r.$1] = v;
    }
    ext['selectors'] = sel;

    // Guarantee the shapes the generator expects.
    ext['endpoints'] = ext['endpoints'] is List ? ext['endpoints'] : <dynamic>[];
    ext['imageSelectors'] =
        ext['imageSelectors'] is Map ? ext['imageSelectors'] : <String, dynamic>{};
    ext['videoSelectors'] =
        ext['videoSelectors'] is Map ? ext['videoSelectors'] : <String, dynamic>{};
    return ext;
  }

  Future<void> _fetchTestPage() async {
    final url = _testUrlCtl.text.trim();
    if (url.isEmpty) return;
    setState(() => _fetching = true);
    final html = await RepoForgeFetcher.fetchHtml(url);
    if (!mounted) return;
    setState(() {
      _fetchedHtml = html;
      _fetching = false;
      _testCounts.clear();
    });
    AppTheme.showSnackBar(
      context,
      html.isEmpty ? 'Fetch failed' : 'Fetched ${html.length} chars — now test selectors',
    );
  }

  void _testSelector(String key) {
    final html = _fetchedHtml;
    if (html == null || html.isEmpty) {
      AppTheme.showSnackBar(context, 'Fetch a page first');
      return;
    }
    setState(() {
      _testCounts[key] =
          RepoForgeFetcher.countMatches(html, _selectorCtls[key]!.text.trim());
    });
  }

  void _preview() {
    try {
      setState(() => _jsPreview = RepoForgeSourceAdapter.generateSourceCode(_buildExt()));
    } catch (e) {
      setState(() => _error = 'Generation failed: $e');
    }
  }

  Future<void> _save() async {
    if (_ext == null) {
      AppTheme.showSnackBar(context, 'Detect a site first');
      return;
    }
    setState(() => _saving = true);
    try {
      final ext = _buildExt();
      final source = await _localRepo.createOrUpdateSource(ext);
      if (!mounted) return;
      final provider = context.read<SourceProvider>();
      await provider.addRepo(await _localRepo.indexPath());
      await provider.installSource(source);
      if (!mounted) return;
      AppTheme.showSnackBar(context, 'Created & installed "${source.name}"');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppTheme.showSnackBar(context, 'Save failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Create Source',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 40 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          _sectionLabel('Site URL', cs),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _urlCtl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: _inputDecoration('https://example.com', cs),
                onSubmitted: (_) => _detect(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _detecting ? null : _detect,
              child: _detecting
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Detect'),
            ),
          ]),
          if (_detecting)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_detectSteps[_detectStep],
                  style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!,
                  style: GoogleFonts.manrope(fontSize: 12.5, color: AppTheme.error)),
            ),
          if (_ext != null) ..._buildDetectedSection(cs),
        ],
      ),
    );
  }

  List<Widget> _buildDetectedSection(ColorScheme cs) {
    final framework = (_ext!['framework'] as String?) ?? 'Custom';
    final confidence = (_ext!['confidence'] as num?)?.toInt() ?? 0;
    final isApi = _ext!['isApiSource'] == true;
    return [
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(children: [
          Icon(Icons.travel_explore_rounded, color: cs.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(framework,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700, fontSize: 15, color: cs.onSurface)),
              Text(
                'confidence $confidence%${isApi ? ' · API source' : ''}',
                style: GoogleFonts.manrope(fontSize: 12, color: cs.outline),
              ),
            ]),
          ),
          _confidenceChip(confidence, cs),
        ]),
      ),

      // ── Metadata ──
      const SizedBox(height: 20),
      _sectionLabel('Details', cs),
      TextField(
        controller: _nameCtl,
        decoration: _inputDecoration('Source name', cs, label: 'Name'),
      ),
      const SizedBox(height: 10),
      Row(children: [
        SizedBox(
          width: 100,
          child: TextField(
            controller: _langCtl,
            decoration: _inputDecoration('en', cs, label: 'Lang'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'manga', label: Text('Manga')),
              ButtonSegment(value: 'anime', label: Text('Anime')),
              ButtonSegment(value: 'novel', label: Text('Novel')),
            ],
            selected: {_contentType},
            onSelectionChanged: (s) => setState(() => _contentType = s.first),
          ),
        ),
      ]),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('NSFW', style: GoogleFonts.manrope(fontSize: 14, color: cs.onSurface)),
        value: _nsfw,
        onChanged: (v) => setState(() => _nsfw = v),
      ),

      // ── Scraping studio ──
      const SizedBox(height: 8),
      _sectionLabel('Scraping Studio', cs),
      Text(
        'Fetch a page, then test each selector to see how many elements it matches.',
        style: GoogleFonts.manrope(fontSize: 12, color: cs.outline),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _testUrlCtl,
            autocorrect: false,
            decoration: _inputDecoration('URL to test against', cs),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: _fetching ? null : _fetchTestPage,
          child: _fetching
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Fetch'),
        ),
      ]),
      if (_fetchedHtml != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _fetchedHtml!.isEmpty
                ? 'Fetch failed — the site may block automated access.'
                : 'Loaded ${_fetchedHtml!.length} chars.',
            style: GoogleFonts.manrope(
                fontSize: 11.5,
                color: _fetchedHtml!.isEmpty ? AppTheme.error : cs.outline),
          ),
        ),
      const SizedBox(height: 12),
      for (final r in _roles) _selectorRow(r.$1, r.$2, cs),

      // ── Actions ──
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _preview,
            icon: const Icon(Icons.code_rounded, size: 18),
            label: const Text('Preview JS'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded, size: 18),
            label: const Text('Create & Install'),
          ),
        ),
      ]),
      if (_jsPreview != null) ..._buildPreview(cs),
    ];
  }

  Widget _selectorRow(String key, String label, ColorScheme cs) {
    final count = _testCounts[key];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: TextField(
            controller: _selectorCtls[key],
            autocorrect: false,
            style: GoogleFonts.robotoMono(fontSize: 12.5),
            decoration: _inputDecoration('CSS selector', cs, label: label)
                .copyWith(
              // Tap to pick from cataloged selectors for this field.
              suffixIcon: IconButton(
                tooltip: 'Pick a known selector',
                icon: Icon(Icons.expand_more_rounded, size: 20, color: cs.outline),
                onPressed: () => _pickSelector(key, label, cs),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        if (count != null) _matchBadge(count, cs),
        // A clearer "test" affordance than a bare play icon.
        TextButton.icon(
          onPressed: () => _testSelector(key),
          icon: Icon(Icons.play_arrow_rounded, size: 18, color: cs.primary),
          label: Text('Test',
              style: GoogleFonts.manrope(
                  fontSize: 12, fontWeight: FontWeight.w700, color: cs.primary)),
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 36),
          ),
        ),
      ]),
    );
  }

  /// Bottom-sheet list of cataloged selectors for [key], searchable, so a user
  /// who doesn't know CSS can choose one that's known to work for this field.
  Future<void> _pickSelector(String key, String label, ColorScheme cs) async {
    final detected = _selectorCtls[key]!.text.trim();
    final candidates = FrameworkDetectorService.candidateSelectorsForRole(
      key,
      detected: detected.isEmpty ? null : detected,
    );
    if (candidates.isEmpty) {
      AppTheme.showSnackBar(context, 'No cataloged selectors for "$label"');
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: cs.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
      ),
      builder: (_) => _SelectorPickerSheet(
        title: label,
        candidates: candidates,
        current: detected,
        // Live match count so the user can see which selector actually hits.
        countFor: (sel) => _fetchedHtml == null
            ? null
            : RepoForgeFetcher.countMatches(_fetchedHtml!, sel),
      ),
    );
    if (picked != null) {
      _selectorCtls[key]!.text = picked;
      _testSelector(key);
    }
  }

  Widget _matchBadge(int count, ColorScheme cs) {
    final invalid = count < 0;
    final none = count == 0;
    // 0 matches is a warning (amber), not a hard error — the selector is valid,
    // it just found nothing. Only a syntactically invalid selector is red.
    final color = invalid
        ? AppTheme.error
        : none
            ? AppTheme.warning
            : Colors.green;
    final text = invalid
        ? 'invalid'
        : none
            ? 'no match'
            : '$count';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: GoogleFonts.manrope(
            fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  List<Widget> _buildPreview(ColorScheme cs) => [
        const SizedBox(height: 20),
        Row(children: [
          _sectionLabel('Generated source', cs),
          const Spacer(),
          IconButton(
            tooltip: 'Copy',
            icon: Icon(Icons.copy_rounded, size: 18, color: cs.outline),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _jsPreview ?? ''));
              AppTheme.showSnackBar(context, 'Copied source to clipboard');
            },
          ),
        ]),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 320),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              _jsPreview ?? '',
              style: GoogleFonts.robotoMono(fontSize: 11, height: 1.45),
            ),
          ),
        ),
      ];

  Widget _confidenceChip(int confidence, ColorScheme cs) {
    final color = confidence >= 70
        ? Colors.green
        : confidence >= 40
            ? Colors.orange
            : AppTheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(20)),
      child: Text('$confidence%',
          style: GoogleFonts.manrope(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _sectionLabel(String text, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(),
            style: GoogleFonts.manrope(
                fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: cs.primary)),
      );

  InputDecoration _inputDecoration(String hint, ColorScheme cs, {String? label}) => InputDecoration(
        hintText: hint,
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );
}

/// Searchable list of cataloged CSS selectors for one field. Each row shows the
/// selector and — when a page is loaded — how many elements it matches on it, so
/// the user can pick one that actually hits without knowing CSS.
class _SelectorPickerSheet extends StatefulWidget {
  final String title;
  final List<String> candidates;
  final String current;
  final int? Function(String selector) countFor;

  const _SelectorPickerSheet({
    required this.title,
    required this.candidates,
    required this.current,
    required this.countFor,
  });

  @override
  State<_SelectorPickerSheet> createState() => _SelectorPickerSheetState();
}

class _SelectorPickerSheetState extends State<_SelectorPickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _query.isEmpty
        ? widget.candidates
        : widget.candidates
            .where((s) => s.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Selector for ${widget.title}',
                    style: GoogleFonts.manrope(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                style: GoogleFonts.robotoMono(fontSize: 12.5),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search selectors…',
                  prefixIcon: Icon(Icons.search_rounded,
                      size: 18, color: cs.outline),
                  border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final sel = filtered[i];
                  final count = widget.countFor(sel);
                  final isCurrent = sel == widget.current;
                  return ListTile(
                    dense: true,
                    title: Text(sel,
                        style: GoogleFonts.robotoMono(
                            fontSize: 12.5,
                            color: cs.onSurface,
                            fontWeight: isCurrent
                                ? FontWeight.w700
                                : FontWeight.w400)),
                    leading: isCurrent
                        ? Icon(Icons.check_rounded, size: 18, color: cs.primary)
                        : const SizedBox(width: 18),
                    trailing: count == null
                        ? null
                        : Text(
                            count < 0
                                ? 'invalid'
                                : count == 0
                                    ? 'no match'
                                    : '$count',
                            style: GoogleFonts.manrope(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: count > 0
                                  ? Colors.green
                                  : (count < 0
                                      ? AppTheme.error
                                      : AppTheme.warning),
                            ),
                          ),
                    onTap: () => Navigator.pop(context, sel),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
