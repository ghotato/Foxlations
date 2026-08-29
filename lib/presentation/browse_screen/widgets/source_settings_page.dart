import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/source_model.dart';
import '../../../core/models/source_settings.dart';
import '../../../core/providers/source_provider.dart';
import '../../../eval/lib.dart';
import '../../../eval/model/source_preference.dart';
import '../../../theme/app_theme.dart';

/// Per-source settings, driven entirely by what the extension itself declares
/// through `getSourcePreferences()` (e.g. Asura's "Hide premium chapters").
///
/// Values are read and written with the SAME key scheme the JS bridge uses —
/// `source_pref_<MSource.id>_<key>`, where `MSource.id` is `source.id.hashCode`
/// (see JsPreferences.init). Writing anywhere else would store settings the
/// extension never reads.
class SourceSettingsPage extends StatefulWidget {
  final MangaSource source;
  final String sourceCode;

  const SourceSettingsPage({
    super.key,
    required this.source,
    required this.sourceCode,
  });

  static Future<void> open(
    BuildContext context, {
    required MangaSource source,
    required String sourceCode,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SourceSettingsPage(source: source, sourceCode: sourceCode),
      ),
    );
  }

  @override
  State<SourceSettingsPage> createState() => _SourceSettingsPageState();
}

class _SourceSettingsPageState extends State<SourceSettingsPage> {
  List<SourcePreference> _prefs = const [];
  final Map<String, dynamic> _values = {};
  bool _loading = true;
  String? _error;
  SourceSettings _options = const SourceSettings();

  String get _prefix => 'source_pref_${widget.source.id.hashCode}_';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // App-level options load first so the page is useful even if running the
    // extension to read its own preferences fails.
    final opts = await SourceSettings.load(widget.source.id);
    if (mounted) setState(() => _options = opts);
    try {
      final declared = await withExtensionService(
        widget.source,
        widget.sourceCode,
        (service) async => service.fetchSourcePreferences(),
      );
      final store = await SharedPreferences.getInstance();
      final values = <String, dynamic>{};
      for (final p in declared) {
        values[p.key] = store.get('$_prefix${p.key}') ?? p.defaultValue;
      }
      if (!mounted) return;
      setState(() {
        _prefs = declared;
        _values.addAll(values);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _write(String key, dynamic value) async {
    setState(() => _values[key] = value);
    final store = await SharedPreferences.getInstance();
    final k = '$_prefix$key';
    if (value is bool) {
      await store.setBool(k, value);
    } else if (value is int) {
      await store.setInt(k, value);
    } else if (value is double) {
      await store.setDouble(k, value);
    } else if (value is List) {
      await store.setStringList(k, value.map((e) => '$e').toList());
    } else {
      await store.setString(k, '$value');
    }
    // Host-backed (Kotlin) sources read prefs from their own runtime store, not
    // the app's SharedPreferences — push the value there too so the extension
    // actually sees it. No-op for JS/Dart sources.
    try {
      await withExtensionService(
        widget.source,
        widget.sourceCode,
        (service) async => service.setSourcePreference(key, value),
      );
    } catch (_) {}
  }

  Future<void> _confirmRemove() async {
    final cs = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
        title: Text('Remove ${widget.source.name}?',
            style: GoogleFonts.manrope(
                fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'The source will be uninstalled. Your library entries from it are '
          'kept, but you won\'t be able to open them until you reinstall it.',
          style: GoogleFonts.manrope(fontSize: 13.5, color: cs.outline),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Remove',
                style: GoogleFonts.manrope(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<SourceProvider>().uninstallSource(widget.source.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lang = widget.source.lang.toUpperCase();
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        title: Text(
          '${widget.source.name}${lang.isEmpty ? '' : ' ($lang)'}',
          style: GoogleFonts.manrope(
              fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface),
        ),
        actions: [
          // The extension row's button is now "Settings", so uninstalling has
          // to be reachable from in here.
          TextButton(
            onPressed: _confirmRemove,
            child: Text('Remove',
                style: GoogleFonts.manrope(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.error)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.only(
                  bottom: 24 + MediaQuery.of(context).viewPadding.bottom),
              children: [
                _sectionLabel(cs, 'FOXLATIONS'),
                _appSettings(cs),
                const SizedBox(height: 8),
                _sectionLabel(cs, 'PROVIDED BY THIS SOURCE'),
                if (_error != null)
                  _message(cs, Icons.error_outline_rounded,
                      'Could not load the source\'s options', _error!)
                else if (_prefs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Text(
                      'This source doesn\'t define any options of its own. '
                      'The settings above still apply to it.',
                      style:
                          GoogleFonts.manrope(fontSize: 13, color: cs.outline),
                    ),
                  )
                else
                  for (final p in _prefs) _tile(cs, p),
              ],
            ),
    );
  }

  Widget _sectionLabel(ColorScheme cs, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Text(text,
            style: GoogleFonts.manrope(
                fontSize: 11,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: cs.primary)),
      );

  /// Options Foxlations provides for every source, whatever its author
  /// implemented.
  Widget _appSettings(ColorScheme cs) {
    final o = _options;
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text('Base URL',
              style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
          subtitle: Text(
            o.baseUrlOverride.isEmpty
                ? widget.source.baseUrl.isEmpty
                    ? 'Using the source default'
                    : '${widget.source.baseUrl}  (default)'
                : o.baseUrlOverride,
            style: GoogleFonts.manrope(fontSize: 12.5, color: cs.outline),
          ),
          trailing: o.baseUrlOverride.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.undo_rounded, size: 18, color: cs.outline),
                  tooltip: 'Reset to default',
                  onPressed: () => _saveOptions(
                      o.copyWith(baseUrlOverride: '')),
                ),
          onTap: _editBaseUrl,
        ),
        SwitchListTile(
          value: o.pinned,
          onChanged: (v) => _saveOptions(o.copyWith(pinned: v)),
          activeThumbColor: cs.primary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text('Pin to top',
              style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
          subtitle: Text('Show this source first in the sources list',
              style: GoogleFonts.manrope(fontSize: 12.5, color: cs.outline)),
        ),
        SwitchListTile(
          value: o.excludeFromGlobalSearch,
          onChanged: (v) =>
              _saveOptions(o.copyWith(excludeFromGlobalSearch: v)),
          activeThumbColor: cs.primary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text('Skip in global search',
              style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
          subtitle: Text('Leave this source out when searching everything',
              style: GoogleFonts.manrope(fontSize: 12.5, color: cs.outline)),
        ),
        SwitchListTile(
          value: o.excludeFromUpdates,
          onChanged: (v) => _saveOptions(o.copyWith(excludeFromUpdates: v)),
          activeThumbColor: cs.primary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text('Skip in library updates',
              style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
          subtitle: Text('Don\'t check this source for new chapters',
              style: GoogleFonts.manrope(fontSize: 12.5, color: cs.outline)),
        ),
        SwitchListTile(
          value: o.requestDesktopSite,
          onChanged: (v) => _saveOptions(o.copyWith(requestDesktopSite: v)),
          activeThumbColor: cs.primary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text('Request desktop site',
              style: GoogleFonts.manrope(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface)),
          subtitle: Text(
              'Try this if the source finds nothing, or shows no chapters — '
              'some sites send phones a cut-down page',
              style: GoogleFonts.manrope(fontSize: 12.5, color: cs.outline)),
        ),
      ],
    );
  }

  Future<void> _editBaseUrl() async {
    final cs = Theme.of(context).colorScheme;
    final controller = TextEditingController(
        text: _options.baseUrlOverride.isEmpty
            ? widget.source.baseUrl
            : _options.baseUrlOverride);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
        title: Text('Base URL',
            style:
                GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          style: GoogleFonts.manrope(fontSize: 14),
          decoration: const InputDecoration(hintText: 'https://example.com'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (result == null) return;
    // Storing the site's own URL is the same as no override.
    final next = result == widget.source.baseUrl ? '' : result;
    await _saveOptions(_options.copyWith(baseUrlOverride: next));
  }

  Future<void> _saveOptions(SourceSettings next) async {
    setState(() => _options = next);
    // baseUrl is needed so the source's host can be added to (or removed from)
    // the desktop-UA set the HTTP layer consults.
    await next.save(widget.source.id, baseUrl: widget.source.baseUrl);
    SourceSettings.updateCache(widget.source.id, next);
  }

  Widget _message(ColorScheme cs, IconData icon, String title, String body) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: cs.outline),
            const SizedBox(height: 12),
            Text(title,
                style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(fontSize: 13, color: cs.outline)),
          ],
        ),
      ),
    );
  }

  Widget _tile(ColorScheme cs, SourcePreference p) {
    final title = Text(p.title,
        style: GoogleFonts.manrope(
            fontSize: 15, fontWeight: FontWeight.w600, color: cs.onSurface));
    final summary = (p.summary == null || p.summary!.isEmpty)
        ? null
        : Text(p.summary!,
            style: GoogleFonts.manrope(fontSize: 12.5, color: cs.outline));

    switch (p.type) {
      case 'switch':
        return SwitchListTile(
          value: _values[p.key] == true,
          onChanged: (v) => _write(p.key, v),
          activeThumbColor: cs.primary,
          title: title,
          subtitle: summary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        );

      case 'list':
        final entries = p.entries ?? const [];
        final current = _values[p.key];
        final match = entries.where((e) => e.value == current);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: title,
          subtitle: Text(
            match.isNotEmpty ? match.first.title : (p.summary ?? ''),
            style: GoogleFonts.manrope(fontSize: 12.5, color: cs.outline),
          ),
          onTap: entries.isEmpty
              ? null
              : () async {
                  final picked = await showDialog<dynamic>(
                    context: context,
                    builder: (_) => SimpleDialog(
                      backgroundColor: cs.surfaceContainerHighest,
                      title: Text(p.title,
                          style: GoogleFonts.manrope(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      children: [
                        for (final e in entries)
                          SimpleDialogOption(
                            onPressed: () => Navigator.pop(context, e.value),
                            child: Row(
                              children: [
                                Icon(
                                  e.value == current
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  size: 18,
                                  color: e.value == current
                                      ? cs.primary
                                      : cs.outline,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(e.title,
                                      style: GoogleFonts.manrope(
                                          fontSize: 14, color: cs.onSurface)),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                  if (picked != null) await _write(p.key, picked);
                },
        );

      case 'multi_select':
        final entries = p.entries ?? const [];
        final selected = (_values[p.key] is List)
            ? (_values[p.key] as List).map((e) => '$e').toSet()
            : <String>{};
        return ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 20),
          title: title,
          subtitle: Text(
            selected.isEmpty ? (p.summary ?? 'None') : '${selected.length} selected',
            style: GoogleFonts.manrope(fontSize: 12.5, color: cs.outline),
          ),
          children: [
            for (final e in entries)
              CheckboxListTile(
                value: selected.contains('${e.value}'),
                activeColor: cs.primary,
                contentPadding: const EdgeInsets.only(left: 32, right: 20),
                title: Text(e.title,
                    style: GoogleFonts.manrope(
                        fontSize: 14, color: cs.onSurface)),
                onChanged: (v) {
                  final next = Set<String>.from(selected);
                  (v ?? false) ? next.add('${e.value}') : next.remove('${e.value}');
                  _write(p.key, next.toList());
                },
              ),
          ],
        );

      case 'edit_text':
      default:
        final current = _values[p.key]?.toString() ?? '';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: title,
          subtitle: Text(
            current.isEmpty ? (p.summary ?? 'Not set') : current,
            style: GoogleFonts.manrope(fontSize: 12.5, color: cs.outline),
          ),
          onTap: () async {
            final controller = TextEditingController(text: current);
            final result = await showDialog<String>(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: cs.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppTheme.radiusMedium)),
                title: Text(p.title,
                    style: GoogleFonts.manrope(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                content: TextField(
                  controller: controller,
                  autofocus: true,
                  style: GoogleFonts.manrope(fontSize: 14),
                  decoration: InputDecoration(hintText: p.summary ?? ''),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, controller.text),
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
            if (result != null) await _write(p.key, result);
          },
        );
    }
  }
}
