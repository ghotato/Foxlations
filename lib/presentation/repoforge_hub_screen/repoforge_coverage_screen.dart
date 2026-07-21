import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/repoforge/mangayomi_js_generator.dart';
import '../../core/repoforge/selector_knowledge_base.dart';
import '../../theme/app_theme.dart';

/// What RepoForge can build: the supported frameworks + a "is this site covered?"
/// check against the manga (~1220) and novel (250+) knowledge bases.
class RepoForgeCoverageScreen extends StatefulWidget {
  const RepoForgeCoverageScreen({super.key});

  @override
  State<RepoForgeCoverageScreen> createState() =>
      _RepoForgeCoverageScreenState();
}

class _RepoForgeCoverageScreenState extends State<RepoForgeCoverageScreen> {
  final _checkCtl = TextEditingController();
  int _mangaKb = 0;
  int _novelKb = 0;
  _CoverageResult? _result;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    SelectorKnowledgeBase.siteCount().then((n) {
      if (mounted) setState(() => _mangaKb = n);
    });
    SelectorKnowledgeBase.novelSiteCount().then((n) {
      if (mounted) setState(() => _novelKb = n);
    });
  }

  @override
  void dispose() {
    _checkCtl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final raw = _checkCtl.text.trim();
    if (raw.isEmpty) return;
    final url = raw.startsWith('http') ? raw : 'https://$raw';
    setState(() => _checking = true);
    final novel = await SelectorKnowledgeBase.novelLookup(url);
    final manga = await SelectorKnowledgeBase.lookup(url);
    if (!mounted) return;
    _CoverageResult r;
    if (novel != null) {
      final fw = (novel['framework'] as String?) ?? 'Custom';
      r = _CoverageResult(
        covered: fw != 'Custom',
        title: 'Known light-novel site',
        detail: fw == 'Custom'
            ? 'Recognized as a novel site — generated with the generic novel body (browse may need selector tuning).'
            : 'Generated as a Novel source using the $fw body — browsing + reader work out of the box.',
      );
    } else if (manga != null) {
      final theme = (manga['theme'] as String?);
      final isApi = manga['api'] == true;
      r = _CoverageResult(
        covered: true,
        title: 'Known manga site',
        detail: isApi
            ? 'Community-verified API source — RepoForge builds it from the site’s API.'
            : theme != null
                ? 'Community-verified theme: $theme — selectors are known.'
                : 'Community-verified custom selectors are on file for this site.',
      );
    } else {
      r = _CoverageResult(
        covered: false,
        title: 'Not in the knowledge base',
        detail: 'RepoForge will detect its framework live when you add it, then '
            'fall back to heuristic “what-is-what” scraping if it’s bespoke.',
      );
    }
    setState(() {
      _result = r;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // group frameworks by their 'group'
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final f in MangayomiJsGenerator.supportedFrameworks) {
      (groups[f['group'] as String] ??= []).add(f);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Coverage',
            style: GoogleFonts.manrope(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          _statsRow(cs),
          const SizedBox(height: 20),
          _label('Check a site', cs),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _checkCtl,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: 'paste a site URL',
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusMedium)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onSubmitted: (_) => _check(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _checking ? null : _check,
              child: _checking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Check'),
            ),
          ]),
          if (_result != null) ...[
            const SizedBox(height: 12),
            _resultCard(_result!, cs),
          ],
          const SizedBox(height: 24),
          _label('Supported frameworks', cs),
          const SizedBox(height: 4),
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Text(entry.key.toUpperCase(),
                  style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: cs.outline)),
            ),
            ...entry.value.map((f) => _frameworkTile(f, cs)),
          ],
        ],
      ),
    );
  }

  Widget _statsRow(ColorScheme cs) => Row(children: [
        Expanded(child: _statCard('$_mangaKb', 'manga sites', cs)),
        const SizedBox(width: 12),
        Expanded(child: _statCard('$_novelKb', 'novel sites', cs)),
        const SizedBox(width: 12),
        Expanded(
            child: _statCard(
                '${MangayomiJsGenerator.supportedFrameworks.length}',
                'frameworks',
                cs)),
      ]);

  Widget _statCard(String value, String label, ColorScheme cs) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        child: Column(children: [
          Text(value,
              style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: cs.primary)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(fontSize: 11, color: cs.outline)),
        ]),
      );

  Widget _resultCard(_CoverageResult r, ColorScheme cs) {
    final color = r.covered ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(r.covered ? Icons.check_circle_rounded : Icons.help_rounded,
            color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.title,
                style: GoogleFonts.manrope(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
            const SizedBox(height: 3),
            Text(r.detail,
                style: GoogleFonts.manrope(
                    fontSize: 12, height: 1.4, color: cs.onSurfaceVariant)),
          ]),
        ),
      ]),
    );
  }

  Widget _frameworkTile(Map<String, dynamic> f, ColorScheme cs) {
    final kinds = (f['kinds'] as List).cast<String>();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f['name'] as String,
                style: GoogleFonts.manrope(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(f['note'] as String,
                style: GoogleFonts.manrope(fontSize: 11.5, color: cs.outline)),
          ]),
        ),
        const SizedBox(width: 8),
        Wrap(
          spacing: 4,
          children: kinds.map((k) => _kindChip(k, cs)).toList(),
        ),
      ]),
    );
  }

  Widget _kindChip(String kind, ColorScheme cs) {
    final icon = kind == 'anime'
        ? Icons.movie_rounded
        : kind == 'novel'
            ? Icons.menu_book_rounded
            : Icons.import_contacts_rounded;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration:
          BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle),
      child: Icon(icon, size: 13, color: cs.primary),
    );
  }

  Widget _label(String text, ColorScheme cs) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(),
            style: GoogleFonts.manrope(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: cs.primary)),
      );
}

class _CoverageResult {
  final bool covered;
  final String title;
  final String detail;
  const _CoverageResult(
      {required this.covered, required this.title, required this.detail});
}
