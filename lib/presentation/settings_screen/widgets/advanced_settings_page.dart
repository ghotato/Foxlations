import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/app_logger.dart';
import '../../../core/services/image_loader.dart';
import '../../../theme/app_theme.dart';

/// Advanced preference keys. Switches persist; some have no runtime effect
/// yet (DNS-over-HTTPS, third-party extensions, external browser) — those
/// will be wired up when their underlying features land.
class AdvancedPrefs {
  static const verboseLogging = 'adv_verbose_logging';
  static const dnsOverHttps = 'adv_dns_over_https';
  static const dnsProvider = 'adv_dns_provider';
  static const thirdPartyExtensions = 'adv_third_party_extensions';
  static const extensionUpdateNotify = 'adv_extension_update_notify';
  static const externalBrowser = 'adv_external_browser';
}

class AdvancedSettingsPage extends StatefulWidget {
  const AdvancedSettingsPage({super.key});
  @override
  State<AdvancedSettingsPage> createState() => _AdvancedSettingsPageState();
}

class _AdvancedSettingsPageState extends State<AdvancedSettingsPage> {
  bool _verboseLogging = false;
  bool _dnsOverHttps = false;
  String _dnsProvider = 'Cloudflare';
  bool _thirdPartyExtensions = false;
  bool _extensionUpdateNotify = true;
  bool _externalBrowser = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _verboseLogging = p.getBool(AdvancedPrefs.verboseLogging) ?? false;
      _dnsOverHttps = p.getBool(AdvancedPrefs.dnsOverHttps) ?? false;
      _dnsProvider = p.getString(AdvancedPrefs.dnsProvider) ?? 'Cloudflare';
      _thirdPartyExtensions =
          p.getBool(AdvancedPrefs.thirdPartyExtensions) ?? false;
      _extensionUpdateNotify =
          p.getBool(AdvancedPrefs.extensionUpdateNotify) ?? true;
      _externalBrowser = p.getBool(AdvancedPrefs.externalBrowser) ?? false;
    });
  }

  Future<void> _setBool(String key, bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, value);
  }

  Future<void> _setString(String key, String value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, value);
  }

  Future<void> _clearChapterCache() async {
    ImageLoader().clearCache();
    if (mounted) AppTheme.showSnackBar(context, 'Chapter image cache cleared');
  }

  Future<void> _confirmClearDatabase() async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cs.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
        title: Text('Clear database?',
            style: GoogleFonts.manrope(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: cs.onSurface)),
        content: Text(
          'This permanently deletes your library, categories, and read '
          'history. Installed extensions and downloads are not affected.',
          style: GoogleFonts.manrope(fontSize: 13, color: cs.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.manrope(color: cs.outline)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Clear',
                style: GoogleFonts.manrope(
                    color: AppTheme.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Clear both library and vault hive boxes. Names match LibraryService.
    for (final prefix in ['library', 'vault']) {
      for (final suffix in ['_manga', '_chapters', '_categories']) {
        try {
          if (Hive.isBoxOpen('$prefix$suffix')) {
            await Hive.box('$prefix$suffix').clear();
          }
        } catch (e) {
          await logger.error('Failed to clear box $prefix$suffix',
              category: LogCategory.general, detail: e.toString());
        }
      }
    }
    if (mounted) {
      AppTheme.showSnackBar(
          context, 'Database cleared — restart the app to reseed defaults');
    }
  }


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface, elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: cs.onSurface, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: Text('Advanced',
            style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
      ),
      body: ListView(
        padding: EdgeInsets.only(
            top: 8, bottom: 8 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          _SectionHeader(title: 'Logging'),
          _SwitchTile(icon: Icons.bug_report_rounded, iconColor: cs.outline,
              title: 'Verbose Logging', subtitle: 'Log detailed debug information',
              value: _verboseLogging, onChanged: (v) {
                setState(() => _verboseLogging = v);
                _setBool(AdvancedPrefs.verboseLogging, v);
              }),
          _ActionTile(icon: Icons.list_alt_rounded, iconColor: AppTheme.warning,
              title: 'View Error Logs', subtitle: 'Browse debug and error logs',
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const ErrorLogViewerPage()))),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Network'),
          _SwitchTile(icon: Icons.dns_rounded, iconColor: const Color(0xFF06B6D4),
              title: 'DNS over HTTPS', subtitle: 'Use secure DNS resolution',
              value: _dnsOverHttps, onChanged: (v) {
                setState(() => _dnsOverHttps = v);
                _setBool(AdvancedPrefs.dnsOverHttps, v);
              }),
          if (_dnsOverHttps)
            _ChoiceTile(icon: Icons.cloud_rounded, iconColor: const Color(0xFF06B6D4),
                title: 'DNS Provider', value: _dnsProvider,
                options: const ['Cloudflare', 'Google', 'AdGuard', 'Custom'],
                onChanged: (v) {
                  setState(() => _dnsProvider = v);
                  _setString(AdvancedPrefs.dnsProvider, v);
                }),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Extensions'),
          _SwitchTile(icon: Icons.extension_rounded, iconColor: AppTheme.warning,
              title: 'Third-Party Extensions', subtitle: 'Allow extensions from unknown sources',
              value: _thirdPartyExtensions, onChanged: (v) {
                setState(() => _thirdPartyExtensions = v);
                _setBool(AdvancedPrefs.thirdPartyExtensions, v);
              }),
          _SwitchTile(icon: Icons.system_update_alt_rounded, iconColor: AppTheme.warning,
              title: 'Extension Update Alerts', subtitle: 'Notify when extensions have updates',
              value: _extensionUpdateNotify, onChanged: (v) {
                setState(() => _extensionUpdateNotify = v);
                _setBool(AdvancedPrefs.extensionUpdateNotify, v);
              }),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Browser'),
          _SwitchTile(icon: Icons.open_in_browser_rounded, iconColor: AppTheme.secondary,
              title: 'External Browser', subtitle: 'Open links in system browser',
              value: _externalBrowser, onChanged: (v) {
                setState(() => _externalBrowser = v);
                _setBool(AdvancedPrefs.externalBrowser, v);
              }),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Data'),
          _ActionTile(icon: Icons.cleaning_services_rounded, iconColor: AppTheme.error,
              title: 'Clear Chapter Cache', subtitle: 'Free up storage space',
              onTap: _clearChapterCache),
          _ActionTile(icon: Icons.delete_sweep_rounded, iconColor: AppTheme.error,
              title: 'Clear Database', subtitle: 'Reset library, categories, and read history',
              onTap: _confirmClearDatabase),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(title.toUpperCase(),
          style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: cs.primary)),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon; final Color iconColor; final String title; final String subtitle;
  final bool value; final ValueChanged<bool> onChanged;
  const _SwitchTile({required this.icon, required this.iconColor, required this.title,
      required this.subtitle, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: cs.outlineVariant)),
      child: Row(children: [
        Container(width: 36, height: 36,
            decoration: BoxDecoration(color: iconColor.withAlpha(25), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
          Text(subtitle, style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
        ])),
        Switch(value: value, onChanged: onChanged, activeThumbColor: cs.onPrimary, activeTrackColor: cs.primary),
      ]),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon; final Color iconColor; final String title; final String subtitle;
  final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.iconColor, required this.title,
      required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: cs.outlineVariant)),
        child: Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(color: iconColor.withAlpha(25), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
            Text(subtitle, style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
          ])),
          Icon(Icons.chevron_right_rounded, color: cs.outline, size: 20),
        ]),
      ),
    );
  }
}

// ── Error Log Viewer ───────────────────────────────────────────────────────────

class ErrorLogViewerPage extends StatefulWidget {
  const ErrorLogViewerPage({super.key});
  @override
  State<ErrorLogViewerPage> createState() => _ErrorLogViewerPageState();
}

class _ErrorLogViewerPageState extends State<ErrorLogViewerPage> {
  LogCategory? _selectedCategory;
  LogLevel? _minLevel;

  static const _categoryLabels = <LogCategory?, String>{
    null: 'All',
    LogCategory.repo: 'Repo',
    LogCategory.extension: 'Extension',
    LogCategory.network: 'Network',
    LogCategory.install: 'Install',
    LogCategory.library: 'Library',
    LogCategory.general: 'General',
  };

  static const _levelLabels = <LogLevel?, String>{
    null: 'All',
    LogLevel.debug: 'Debug',
    LogLevel.info: 'Info',
    LogLevel.warning: 'Warning',
    LogLevel.error: 'Error',
  };

  Color _levelColor(LogLevel level, ColorScheme cs) {
    switch (level) {
      case LogLevel.debug: return cs.outline;
      case LogLevel.info: return AppTheme.success;
      case LogLevel.warning: return AppTheme.warning;
      case LogLevel.error: return AppTheme.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface, elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: cs.onSurface, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: Text('Error Logs',
            style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w700, color: cs.onSurface)),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: cs.outline),
            tooltip: 'Clear all logs',
            onPressed: () => _confirmClear(context)),
        ],
      ),
      body: Column(children: [
        // Filter bar
        Container(
          color: cs.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(child: _FilterDropdown<LogCategory?>(
              label: 'Category', value: _selectedCategory, items: _categoryLabels,
              onChanged: (v) => setState(() => _selectedCategory = v), cs: cs)),
            const SizedBox(width: 8),
            Expanded(child: _FilterDropdown<LogLevel?>(
              label: 'Level', value: _minLevel, items: _levelLabels,
              onChanged: (v) => setState(() => _minLevel = v), cs: cs)),
          ]),
        ),
        // Log list
        Expanded(
          child: ValueListenableBuilder<List<LogEntry>>(
            valueListenable: AppLogger.instance.logsNotifier,
            builder: (context, allLogs, _) {
              final filtered = AppLogger.instance.getFiltered(
                category: _selectedCategory, minLevel: _minLevel);
              final reversed = filtered.reversed.toList();
              if (reversed.isEmpty) {
                return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle_outline_rounded, color: cs.outline, size: 48),
                  const SizedBox(height: 12),
                  Text('No logs yet', style: GoogleFonts.manrope(
                      fontSize: 15, color: cs.outline, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Logs will appear here as you use the app',
                      style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
                ]));
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: reversed.length,
                itemBuilder: (context, index) {
                  final entry = reversed[index];
                  return _LogEntryTile(entry: entry, levelColor: _levelColor(entry.level, cs), cs: cs);
                });
            }),
        ),
      ]),
    );
  }

  void _confirmClear(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text('Clear all logs?',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: cs.onSurface)),
      content: Text('This will permanently delete all stored log entries.',
          style: GoogleFonts.manrope(fontSize: 13, color: cs.outline)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.manrope(color: cs.outline))),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            await AppLogger.instance.clearLogs();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('Logs cleared', style: GoogleFonts.manrope(color: Colors.white)),
                backgroundColor: AppTheme.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
            }
          },
          child: Text('Clear', style: GoogleFonts.manrope(
              color: AppTheme.error, fontWeight: FontWeight.w700))),
      ],
    ));
  }
}

class _LogEntryTile extends StatefulWidget {
  final LogEntry entry;
  final Color levelColor;
  final ColorScheme cs;
  const _LogEntryTile({required this.entry, required this.levelColor, required this.cs});
  @override
  State<_LogEntryTile> createState() => _LogEntryTileState();
}

class _LogEntryTileState extends State<_LogEntryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final cs = widget.cs;
    final timeStr =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:'
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:'
        '${entry.timestamp.second.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: () { if (entry.detail != null) setState(() => _expanded = !_expanded); },
      onLongPress: () {
        Clipboard.setData(ClipboardData(
          text: '[${entry.levelLabel}][${entry.categoryLabel}] ${entry.message}'
              '${entry.detail != null ? '\n${entry.detail}' : ''}'));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Copied to clipboard', style: GoogleFonts.manrope(color: Colors.white)),
          backgroundColor: cs.primary, behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: widget.levelColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(5)),
                child: Text(entry.levelLabel, style: GoogleFonts.sourceCodePro(
                    fontSize: 10, fontWeight: FontWeight.w700, color: widget.levelColor))),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(5)),
                child: Text(entry.categoryLabel, style: GoogleFonts.sourceCodePro(
                    fontSize: 10, fontWeight: FontWeight.w600, color: cs.primary))),
              const Spacer(),
              Text(timeStr, style: GoogleFonts.sourceCodePro(fontSize: 10, color: cs.outline)),
              if (entry.detail != null) ...[
                const SizedBox(width: 4),
                Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    size: 16, color: cs.outline),
              ],
            ])),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(entry.message, style: GoogleFonts.manrope(fontSize: 12, color: cs.onSurface),
                overflow: TextOverflow.ellipsis, maxLines: _expanded ? 10 : 2)),
          if (_expanded && entry.detail != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(6)),
              child: Text(entry.detail!, style: GoogleFonts.sourceCodePro(fontSize: 11, color: cs.outline))),
        ]),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final ColorScheme cs;
  const _FilterDropdown({required this.label, required this.value,
      required this.items, required this.onChanged, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: cs.surface,
          borderRadius: BorderRadius.circular(8), border: Border.all(color: cs.outlineVariant)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value, isExpanded: true, dropdownColor: cs.surfaceContainerHighest,
          style: GoogleFonts.manrope(fontSize: 12, color: cs.onSurface),
          hint: Text(label, style: GoogleFonts.manrope(fontSize: 12, color: cs.outline)),
          items: items.entries.map((e) => DropdownMenuItem<T>(
            value: e.key,
            child: Text(e.value, style: GoogleFonts.manrope(fontSize: 12, color: cs.onSurface)),
          )).toList(),
          onChanged: (v) { if (v != null || null is T) onChanged(v as T); },
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  final IconData icon; final Color iconColor; final String title; final String value;
  final List<String> options; final ValueChanged<String> onChanged;
  const _ChoiceTile({required this.icon, required this.iconColor, required this.title,
      required this.value, required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () {
        showModalBottomSheet(
          context: context, backgroundColor: cs.surface,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge))),
          builder: (_) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: cs.outline, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text(title, style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w700, color: cs.onSurface)),
              Divider(color: cs.outlineVariant),
              ...options.map((opt) {
                final isSelected = opt == value;
                return InkWell(
                  onTap: () { onChanged(opt); Navigator.pop(context); },
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                        color: isSelected ? cs.primary.withAlpha(26) : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
                    child: Row(children: [
                      Expanded(child: Text(opt, style: GoogleFonts.manrope(
                          fontSize: 14, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500, color: cs.onSurface))),
                      if (isSelected) Icon(Icons.check_rounded, size: 18, color: cs.primary),
                    ]),
                  ),
                );
              }),
            ]),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(color: cs.outlineVariant)),
        child: Row(children: [
          Container(width: 36, height: 36,
              decoration: BoxDecoration(color: iconColor.withAlpha(25), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface))),
          Text(value, style: GoogleFonts.manrope(fontSize: 13, color: cs.outline)),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, color: cs.outline, size: 20),
        ]),
      ),
    );
  }
}
