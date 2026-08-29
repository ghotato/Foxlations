import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/providers/source_provider.dart';
import '../../../presentation/webview_screen/webview_screen.dart';
import '../../../theme/app_theme.dart';

class BrowseSettingsPage extends StatefulWidget {
  const BrowseSettingsPage({super.key});

  @override
  State<BrowseSettingsPage> createState() => _BrowseSettingsPageState();
}

class _BrowseSettingsPageState extends State<BrowseSettingsPage> {
  bool _adBlockEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _adBlockEnabled = prefs.getBool(WebViewScreen.adBlockKey) ?? true;
    });
  }

  Future<void> _setAdBlock(bool value) async {
    setState(() => _adBlockEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(WebViewScreen.adBlockKey, value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final source = context.watch<SourceProvider>();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: cs.onSurface, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Browse',
          style: GoogleFonts.manrope(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.only(
            top: 8, bottom: 8 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          _SectionHeader(title: 'Sources'),
          _SwitchTile(
            icon: Icons.eighteen_up_rating_rounded,
            iconColor: AppTheme.error,
            title: 'Show NSFW Sources',
            subtitle: 'Show 18+ sources in browse and search',
            value: source.showNsfw,
            onChanged: source.setShowNsfw,
          ),
          _SwitchTile(
            icon: Icons.push_pin_rounded,
            iconColor: cs.primary,
            title: 'Pinned Sources Only',
            subtitle: 'Only show pinned sources in browse',
            value: source.pinnedOnlyBrowse,
            onChanged: source.setPinnedOnlyBrowse,
          ),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Global Search'),
          _SwitchTile(
            icon: Icons.travel_explore_rounded,
            iconColor: cs.primary,
            title: 'Pinned Sources Only',
            subtitle: 'Only search pinned sources in global search',
            value: source.pinnedOnlyGlobalSearch,
            onChanged: source.setPinnedOnlyGlobalSearch,
          ),
          const SizedBox(height: 8),
          _SectionHeader(title: 'WebView'),
          _SwitchTile(
            icon: Icons.block_rounded,
            iconColor: AppTheme.warning,
            title: 'Ad Blocker',
            subtitle: 'Block ads, popups, and overlays in the browser',
            value: _adBlockEnabled,
            onChanged: _setAdBlock,
          ),
          const SizedBox(height: 8),
          _SectionHeader(title: 'Extensions'),
          _SwitchTile(
            icon: Icons.system_update_alt_rounded,
            iconColor: AppTheme.secondary,
            title: 'Auto-Update Extensions',
            subtitle: 'Refresh installed extension code on app launch',
            value: source.autoUpdateExtensions,
            onChanged: source.setAutoUpdateExtensions,
          ),
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
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
          color: cs.primary,
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface)),
                Text(subtitle,
                    style: GoogleFonts.manrope(
                        fontSize: 12, color: cs.outline)),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: cs.onPrimary,
            activeTrackColor: cs.primary,
          ),
        ],
      ),
    );
  }
}
